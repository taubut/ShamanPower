-- ShamanPower_Config :: IconRow
-- The icon row and its right-click menu, shared by the icon pages (A13 on, 2026-10-07):
-- the look Ready Reminders' Spells row (ReadyIcons.lua) and Target Tracker's (TTIcons.lua)
-- drew first, made once so every later page draws the same thing. 36 px icons on thin
-- plates (#05070A), 4 px apart, wrapping to the card's width, a caption under them.
-- Not learned: gray and dark; hidden: gray and dim; a small accentHi corner marks an
-- item with settings of its own; hover: the plate's edge in accent; its menu open: a
-- 2 px accentHi outline. Up to three textures per item, shown as slices (Combined
-- Shocks, the shield, the weapon imbue). Left-click: the page's toggle. Right-click:
-- the item's menu in ns.ContextMenu. Drag (when the page gives `move`): the item lifts
-- (its place goes empty), an accentHi line shows where it lands, letting go moves it.
-- Ready Reminders and Target Tracker keep their own copies (unchanged, pixel for pixel).
--
-- local row = ns.IconRow.New(def); ns.CustomRows.<key> = row
-- def = {
--   caption  = "text" or function() return text end,
--   list     = function(out) fill out with the items, in order (each { key = ..., name = ... }) end,
--   textures = function(item, out) return n end,     up to three textures into out
--   shown    = function(item) return on end,
--   learned  = function(item) return known end,       (nil: every item counts as learned)
--   hasOwn   = function(item) return own end,         (nil: no corner)
--   tooltip  = function(item) return body end,       (nil: the shared one)
--   hint     = "Click: ...\nRight-click: ...",
--   toggle   = function(item) end,                    left-click
--   menu     = function(item) return { menu item, ... } end,   ns.ContextMenu items
--   move     = function(item, index) end,             drag: the item to place `index` (optional)
--   locked   = function() return true end,            (optional) no drag right now (a fight)
-- }
-- row:Render(body, x, y, width, onChanged) / row:Release()   (ns.CustomRows)
-- row:Changed(keepMenu)  row:Repaint()  row:OpenMenu(key, path)  row:ShowDrag(key, gap)
--
-- Menu rows (ns.IconRow.Menu): Choice, OnOff, Slider, Group; each value read by the
-- page's own get (value, own: own = the item's own value, drawn in accentHi).
local _, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not (Core and SP) then return end

local floor, max, ceil, min = math.floor, math.max, math.ceil, math.min

local ICON         = 36    -- the icon
local PLATE        = 40    -- its plate, 2 px round it
local PITCH        = 44    -- plate to plate: 4 px apart
local PAD_X        = 12    -- the settings rows' inner padding (plus a card's inset: Widgets.CARD_INSET)
local PAD_TOP      = 10
local CAPTION_GAP  = 10
local PAD_BOTTOM   = 12
local ROW_GAP      = 6     -- the settings rows' gap (Widgets.ROW_GAP)
local CORNER       = 11
local HIDDEN_SHADE = 0.5   -- hidden: gray and half as bright
local NOT_LEARNED_SHADE = 0.3   -- not learned yet: gray and dark
local LIFTED_ALPHA = 0.55  -- a dragged item's empty place
local DRAG_LIFT    = 8     -- the lifted copy sits this much above the row

local IconRow = {}
ns.IconRow = IconRow

local function Report(err) geterrorhandler()(err) end
local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if not ok then Report(a) return nil end
	return a, b
end

-- ---------------------------------------------------------------------------
-- A plate (the button)
-- ---------------------------------------------------------------------------
local function NewPlate(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(PLATE, PLATE)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local plate = SP.Brand and SP.Brand.plate or { 5 / 255, 7 / 255, 10 / 255 }   -- #05070A, the totem boxes' plate
	b.plate = b:CreateTexture(nil, "BACKGROUND")
	b.plate:SetAllPoints(b)
	b.plate:SetColorTexture(plate[1], plate[2], plate[3], 1)
	b.icons = {}
	for i = 1, 3 do   -- one icon, or slices
		local t = b:CreateTexture(nil, "ARTWORK")
		t:Hide()
		b.icons[i] = t
	end
	-- hover: the plate's edge turns accent, as a control's border does
	b.hoverEdge = CreateFrame("Frame", nil, b)
	b.hoverEdge:SetAllPoints(b)
	b.hoverEdge:SetFrameLevel(b:GetFrameLevel() + 1)
	Core:MakeBorder(b.hoverEdge, "accent", 1)
	b.hoverEdge:Hide()
	-- its menu is open (or it is the lifted copy of a drag): a 2 px accentHi outline
	b.openEdge = CreateFrame("Frame", nil, b)
	b.openEdge:SetAllPoints(b)
	b.openEdge:SetFrameLevel(b:GetFrameLevel() + 2)
	Core:MakeBorder(b.openEdge, "accentHi", 2)
	b.openEdge:Hide()
	-- settings of its own: an accentHi square in the plate's top right corner, edged in plate black
	b.corner = CreateFrame("Frame", nil, b)
	b.corner:SetSize(CORNER, CORNER)
	b.corner:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
	b.corner:SetFrameLevel(b:GetFrameLevel() + 3)
	local edge = b.corner:CreateTexture(nil, "ARTWORK")
	edge:SetAllPoints(b.corner)
	edge:SetColorTexture(plate[1], plate[2], plate[3], 1)
	local fill = b.corner:CreateTexture(nil, "OVERLAY")
	fill:SetPoint("TOPLEFT", b.corner, "TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMRIGHT", b.corner, "BOTTOMRIGHT", -1, 1)
	fill:SetColorTexture(Core:Color("accentHi"))
	b.corner:Hide()
	return b
end

-- the textures, as one icon or side by side slices, in the item's shade
local function PaintIcons(b, tex, n, on, learned)
	local shade = 1
	if not learned then shade = NOT_LEARNED_SHADE elseif not on then shade = HIDDEN_SHADE end
	for i = 1, 3 do
		local t = b.icons[i]
		if i <= n then
			t:ClearAllPoints()
			t:SetSize(ICON / n, ICON)
			t:SetPoint("TOPLEFT", b, "TOPLEFT", 2 + (i - 1) * ICON / n, -2)
			t:SetTexture(tex[i])
			t:SetTexCoord(0.08 + 0.84 * (i - 1) / n, 0.08 + 0.84 * i / n, 0.08, 0.92)
			t:SetDesaturated(not (on and learned))
			t:SetVertexColor(shade, shade, shade)
			t:Show()
		else
			t:Hide()
		end
	end
end

-- ---------------------------------------------------------------------------
-- The row
-- ---------------------------------------------------------------------------
local Proto = {}
local MT = { __index = Proto }

-- rows whose page locks in a fight (def.locked): a fight's start closes their menu and drops a drag
local lockedRows = {}
function IconRow.New(def)
	local row = setmetatable({ def = def, buttons = {}, list = {}, byKey = {}, tex = {}, scratch = {} }, MT)
	if def.locked then lockedRows[#lockedRows + 1] = row end
	return row
end

-- locked now (a fight): says why (def.onLocked) and answers true
function Proto:RefuseLocked()
	local def = self.def
	if not (def.locked and Call(def.locked)) then return false end
	Call(def.onLocked)
	return true
end

-- the menu's items, each change refused while locked (a menu left open into a fight, a key
-- pressed in it): its click, its slider and its submenu's items
local function Guard(row, items)
	if type(items) ~= "table" then return items end
	for _, it in ipairs(items) do
		if type(it) == "table" and not it.spGuarded then
			it.spGuarded = true
			local click = it.onClick
			if click then
				it.onClick = function(...)
					if row:RefuseLocked() then return false end
					return click(...)
				end
			end
			local sl = it.slider
			if sl and sl.set then
				local set = sl.set
				sl.set = function(...)
					if row:RefuseLocked() then return end
					return set(...)
				end
			end
			local sub = it.sub
			if sub then it.sub = function(...) return Guard(row, sub(...)) end end
		end
	end
	return items
end

local function CaptionText(def)
	local c = def.caption
	if type(c) == "function" then c = Call(c) end
	return c or ""
end

local function Learned(def, item)
	if not def.learned then return true end
	return Call(def.learned, item) and true or false
end

local function TooltipBody(row, item)
	local def = row.def
	if def.tooltip then return Call(def.tooltip, item) end
	if not Learned(def, item) then return "You haven't learned this yet. You can still set it up." end
	if def.hasOwn and Call(def.hasOwn, item) then return "It has settings of its own (right-click to see them)." end
	return "It uses the default settings (right-click to change them)."
end

function Proto:PaintButton(b)
	local item = b.item
	if not item then return end
	local def = self.def
	local on = Call(def.shown, item) and true or false
	local learned = Learned(def, item)
	local n = Call(def.textures, item, self.tex) or 0
	PaintIcons(b, self.tex, n, on, learned)
	b.corner:SetShown((def.hasOwn and Call(def.hasOwn, item)) and true or false)
	b.openEdge:SetShown(self.openKey == item.key)
	Core:AttachTooltip(b, item.name, TooltipBody(self, item), def.hint)
	if self.liftKey == item.key then self:PaintLifted(b) else b:SetAlpha(1) end
end

function Proto:Repaint()
	for _, b in ipairs(self.buttons) do
		if b:IsShown() then self:PaintButton(b) end
	end
	if self.ghost and self.ghost:IsShown() and self.ghost.item then
		local def = self.def
		local n = Call(def.textures, self.ghost.item, self.tex) or 0
		PaintIcons(self.ghost, self.tex, n, Call(def.shown, self.ghost.item) and true or false, Learned(def, self.ghost.item))
	end
end

function Proto:ListChanged()
	local s = self.scratch
	wipe(s)
	Call(self.def.list, s)
	if #s ~= #self.list then return true end
	for i = 1, #s do if s[i].key ~= self.list[i].key then return true end end
	return false
end

-- a setting changed here: the icons repainted now, then the page (the preview).
-- keepMenu: the menu stays open, even if the page lays itself out again (it opens
-- again on the same rows)
function Proto:Changed(keepMenu)
	self:Repaint()
	local fn = self.onChanged
	if not fn then return end
	self.writing = keepMenu and true or false
	local ok, err = pcall(fn)
	self.writing = false
	if not ok then Report(err) end
end

-- a setting changed somewhere else (a profile, the setup tour): drawn again
function Proto:OnSettingsChanged()
	if not (self.frame and self.frame:IsVisible()) then return end
	if self:ListChanged() then
		local cfg = _G.ShamanPowerConfig
		if cfg and cfg.RefreshCurrent then cfg:RefreshCurrent() end
		return
	end
	self:Repaint()
	if self.openKey and ns.ContextMenu:IsOpen() then ns.ContextMenu:Refresh() end
end

-- path: the submenus to open again (after the page laid itself out)
function Proto:OpenMenu(key, path)
	local b = self.byKey[key]
	if not (b and b.item and b:IsVisible()) then return end
	if self:RefuseLocked() then return end
	local item = b.item
	local icons = {}
	local n = Call(self.def.textures, item, self.tex) or 0
	for i = 1, n do icons[i] = self.tex[i] end
	self.openKey = key
	self:PaintButton(b)
	local row = self
	ns.ContextMenu:Open(b, {
		header = { text = item.name, icons = icons },
		items = function()
			local items = Call(row.def.menu, item) or {}
			if row.def.locked then Guard(row, items) end
			return items
		end,
		onClose = function()
			if row.openKey == key then row.openKey = nil end
			row:Repaint()
		end,
	})
	if path and #path > 0 then ns.ContextMenu:ShowPath(path) end
end

-- ---------------------------------------------------------------------------
-- Drag: the item lifted, its place empty, a line where it lands
-- ---------------------------------------------------------------------------
-- where an index's plate sits in the row frame (top left, y down)
function Proto:SlotXY(i)
	local per = self.perRow or 1
	return self.padX + ((i - 1) % per) * PITCH, PAD_TOP + floor((i - 1) / per) * PITCH
end

function Proto:PaintLifted(b)
	for i = 1, 3 do b.icons[i]:Hide() end
	b.corner:Hide()
	b:SetAlpha(LIFTED_ALPHA)
end

-- gap: the place it lands, 1 .. #list + 1 (before that item; #list + 1 = the end).
-- x, y: the lifted copy's top left in the row frame (nil: over the line, as a still picture)
function Proto:ShowDrag(key, gap, x, y)
	local f = self.frame
	local from = self.byKey[key]
	if not (f and from and from.item) then return end
	local n = #self.list
	gap = max(1, min(n + 1, gap or 1))
	self.liftKey, self.dragGap = key, gap
	self:PaintButton(from)
	local g = self.ghost
	if not g then
		g = NewPlate(f)
		g:EnableMouse(false)
		self.ghost = g
	end
	g:SetParent(f)
	g:SetFrameLevel(f:GetFrameLevel() + 20)
	g.item = from.item
	local def = self.def
	local cnt = Call(def.textures, from.item, self.tex) or 0
	PaintIcons(g, self.tex, cnt, Call(def.shown, from.item) and true or false, Learned(def, from.item))
	g.openEdge:Show()
	g.corner:Hide()
	-- the line: at the left of the place it lands (after the last plate for the end)
	local lx, ly
	if gap <= n then
		lx, ly = self:SlotXY(gap)
		lx = lx - (PITCH - PLATE) / 2 - 1
	else
		lx, ly = self:SlotXY(n)
		lx = lx + PLATE + (PITCH - PLATE) / 2 - 1
	end
	if not x then x, y = lx - PITCH / 2 + 10, ly - DRAG_LIFT end
	g:ClearAllPoints()
	g:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
	g:Show()
	local ins = self.insert
	if not ins then
		ins = f:CreateTexture(nil, "OVERLAY", nil, 7)
		ins:SetColorTexture(Core:Color("accentHi"))
		self.insert = ins
	end
	ins:ClearAllPoints()
	ins:SetSize(2, PLATE + 8)
	ins:SetPoint("TOPLEFT", f, "TOPLEFT", lx, -(ly - 4))
	ins:Show()
end

function Proto:EndDrag()
	local key = self.liftKey
	self.liftKey, self.dragGap = nil, nil
	if self.ghost then self.ghost:Hide(); self.ghost.item = nil end
	if self.insert then self.insert:Hide() end
	if self.dragFrame then self.dragFrame:SetScript("OnUpdate", nil) end
	local b = key and self.byKey[key]
	if b then self:PaintButton(b) end
end

-- the cursor over the row frame: the place it would land
function Proto:GapAt(cx, cy)
	local n = #self.list
	local per = self.perRow or 1
	local line = max(0, floor((cy - PAD_TOP) / PITCH))
	local col = floor((cx - self.padX + (PITCH - PLATE) / 2 + PITCH / 2) / PITCH)
	col = max(0, min(per, col))
	return max(1, min(n + 1, line * per + col + 1))
end

function Proto:CursorInFrame()
	local f = self.frame
	local scale = f:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	cx, cy = cx / scale, cy / scale
	return cx - (f:GetLeft() or 0), (f:GetTop() or 0) - cy
end

function Proto:StartDrag(b)
	local def = self.def
	if not (def.move and b.item) then return end
	if self:RefuseLocked() then return end
	if ns.ContextMenu:IsOpen() then ns.ContextMenu:Close() end
	local key = b.item.key
	b.dragging = true
	local row = self
	local df = self.dragFrame
	if not df then df = CreateFrame("Frame", nil, self.frame); self.dragFrame = df end
	-- only while the mouse holds an item (nothing runs otherwise)
	df:SetScript("OnUpdate", function()
		local cx, cy = row:CursorInFrame()
		row:ShowDrag(key, row:GapAt(cx, cy), cx - PLATE / 2, cy - PLATE / 2)
	end)
	local cx, cy = self:CursorInFrame()
	self:ShowDrag(key, self:GapAt(cx, cy), cx - PLATE / 2, cy - PLATE / 2)
end

function Proto:StopDrag(b)
	if not b.dragging then return end
	local key, gap = self.liftKey, self.dragGap
	self:EndDrag()
	-- (the click that ends a drag is not a click on the item)
	C_Timer.After(0, function() b.dragging = nil end)
	if not (key and gap) then return end
	local def = self.def
	if self:RefuseLocked() then return end
	local from
	for i, item in ipairs(self.list) do if item.key == key then from = i break end end
	if not from then return end
	local to = gap
	if to > from then to = to - 1 end
	if to == from then return end
	Call(def.move, self.list[from], to)
	self:Changed(false)
	-- the new order: the row is laid out again in it (the page keeps its scroll); without
	-- this the icons stayed in the old order until the page was opened again
	if self:ListChanged() then
		local cfg = _G.ShamanPowerConfig
		if cfg and cfg.RefreshCurrent then cfg:RefreshCurrent() end
	end
end

-- ---------------------------------------------------------------------------
-- Clicks
-- ---------------------------------------------------------------------------
local function ButtonClick(b, button)
	local row, item = b.row, b.item
	if not (row and item) or b.dragging then return end
	if button == "RightButton" then
		row:OpenMenu(item.key)
		return
	end
	if row:RefuseLocked() then return end
	Call(row.def.toggle, item)
	row:Changed(false)
end

function Proto:NewButton(parent)
	local b = NewPlate(parent)
	b.row = self
	b:SetScript("OnClick", ButtonClick)
	b:SetScript("OnEnter", function(s) s.hoverEdge:Show() end)
	b:SetScript("OnLeave", function(s) s.hoverEdge:Hide() end)
	if self.def.move then
		b:RegisterForDrag("LeftButton")
		b:SetScript("OnDragStart", function(s) s.row:StartDrag(s) end)
		b:SetScript("OnDragStop", function(s) s.row:StopDrag(s) end)
	end
	return b
end

-- ---------------------------------------------------------------------------
-- ns.CustomRows: drawn by Window.lua's page packer, released on every redraw
-- ---------------------------------------------------------------------------
local function OpenQueued(row)
	local q = row.queued
	row.queued = nil
	if q then row:OpenMenu(q.key, q.path) end
end

function Proto:Render(body, x, y, width, onChanged)
	self.onChanged = onChanged
	-- the menu closes with the settings window (hooked once: never SetScript on it)
	if not self.hooked and _G.ShamanPowerConfigUIFrame then
		self.hooked = true
		local row = self
		_G.ShamanPowerConfigUIFrame:HookScript("OnHide", function()
			row.reopen = nil
			if row.liftKey then row:EndDrag() end
			if row.openKey and ns.ContextMenu:IsOpen() then ns.ContextMenu:Close() end
		end)
	end

	local f = self.frame
	if not f then
		f = CreateFrame("Frame", nil, body)
		f.caption = f:CreateFontString(nil, "OVERLAY")
		f.caption:SetFontObject(Core.fonts.rowDim)
		f.caption:SetJustifyH("LEFT")
		f.caption:SetWordWrap(true)
		f.spNoCull = true
		self.frame = f
	end
	f:SetParent(body)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", body, "TOPLEFT", x or 0, -(y or 0))
	f:SetWidth(width)
	f:Show()

	local list = self.list
	wipe(list)
	Call(self.def.list, list)
	wipe(self.byKey)
	local padX = PAD_X + (ns.Widgets and tonumber(ns.Widgets.CARD_INSET) or 0)   -- in line with the rows' labels
	local perRow = max(1, floor((width - padX * 2 + (PITCH - PLATE)) / PITCH))
	self.padX, self.perRow = padX, perRow
	for i, item in ipairs(list) do
		local b = self.buttons[i] or self:NewButton(f)
		self.buttons[i] = b
		b.item = item
		b:ClearAllPoints()
		local bx, by = self:SlotXY(i)
		b:SetPoint("TOPLEFT", f, "TOPLEFT", bx, -by)
		b:Show()
		self.byKey[item.key] = b
	end
	for i = #list + 1, #self.buttons do
		local b = self.buttons[i]
		b.item = nil
		b:Hide()
	end
	local iconsH = max(1, ceil(#list / perRow)) * PITCH - (PITCH - PLATE)
	f.caption:ClearAllPoints()
	f.caption:SetPoint("TOPLEFT", f, "TOPLEFT", padX, -(PAD_TOP + iconsH + CAPTION_GAP))
	f.caption:SetWidth(width - padX * 2)
	f.caption:SetText(CaptionText(self.def))
	local h = PAD_TOP + iconsH + CAPTION_GAP + ceil(f.caption:GetStringHeight()) + PAD_BOTTOM
	f:SetHeight(h)
	self:Repaint()

	-- a menu to open: asked for (OpenMenu from elsewhere), or open before the page laid
	-- itself out after one of its own choices. Next frame: the icons are placed.
	local r = self.reopen
	self.reopen = nil
	if r and (not r.at or GetTime() - r.at < 2) and self.byKey[r.key] then
		self.queued = r
		local row = self
		C_Timer.After(0, function() OpenQueued(row) end)
	end
	return f, h + ROW_GAP
end

function Proto:Release()
	if self.liftKey then self:EndDrag() end
	if self.openKey and ns.ContextMenu:IsOpen() then
		-- a redraw made by one of the menu's own choices: open it again when drawn
		if self.writing then self.reopen = { key = self.openKey, path = ns.ContextMenu:OpenPath() } end
		ns.ContextMenu:Close()
	elseif self.queued then
		self.reopen = self.queued   -- drawn twice in one go: it still opens after the second
	end
	self.openKey, self.queued = nil, nil
	if self.frame then self.frame:Hide() end
	for _, b in ipairs(self.buttons) do
		Core:HideTooltipFor(b)
		b.hoverEdge:Hide()
	end
end

-- open an item's menu once the page is drawn (the page is opened by the caller)
function Proto:QueueMenu(key, path)
	self.reopen = { key = key, at = GetTime(), path = path }
end

-- a fight starts: the locked rows' menus close and a drag in progress is dropped (made at load)
do
	local w = CreateFrame("Frame")
	w:RegisterEvent("PLAYER_REGEN_DISABLED")
	w:SetScript("OnEvent", function()
		for _, row in ipairs(lockedRows) do
			if row.liftKey then
				local b = row.byKey[row.liftKey]
				row:EndDrag()
				if b then b.dragging = nil end
			end
			if row.openKey and ns.ContextMenu:IsOpen() then ns.ContextMenu:Close() end
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Menu rows: the value column shows the item's value (accentHi when it is its own)
-- ---------------------------------------------------------------------------
local Menu = {}
IconRow.Menu = Menu

local function OnOffText(v) if v then return "On" end return "Off" end
function Menu.LabelOf(list, v)
	for _, c in ipairs(list) do if c[1] == v then return c[2] end end
	return list[1] and list[1][2] or ""
end

-- get() -> value, own;  set(v) -> keep the menu open (true) or close it
function Menu.Choice(text, list, get, set, tip)
	return {
		text = text, tip = tip,
		value = function()
			local v, own = get()
			return Menu.LabelOf(list, v), own and true or false
		end,
		sub = function()
			local cur = get()
			local items = {}
			for _, c in ipairs(list) do
				local v = c[1]
				items[#items + 1] = { text = c[2], selected = cur == v, tip = c[3], onClick = function() return set(v) end }
			end
			return items
		end,
	}
end

function Menu.OnOff(text, get, set, tip)
	return Menu.Choice(text, { { true, "On" }, { false, "Off" } },
		function() local v, own = get(); return v and true or false, own end, set, tip)
end

function Menu.Slider(text, lo, hi, step, get, set, format, isPercent, tip)
	return {
		text = text, tip = tip,
		slider = {
			min = lo, max = hi, step = step, isPercent = isPercent,
			get = function() return (get()) end,
			set = set,
			format = format,
		},
	}
end

function Menu.Group(text, rows, tip, value)
	return { text = text, tip = tip, value = value, sub = function() return rows() end }
end

Menu.OnOffText = OnOffText
