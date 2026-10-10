-- ShamanPower_Config :: ListLook
-- "Use the Old Settings Look" (A20b, 3.0.8). With the switch on (General > Main,
-- opt.oldSettingsLook = true) every icon row (IconRow.lua, and the Ready Reminders,
-- Target Tracker and Party Strip copies through their `listDef`) is drawn as plain
-- settings rows instead of icons, built from the SAME menus the icons open: one section
-- card per item (its name, the page's element), the item's own on / off (a click on its
-- icon) as the card's first row, then its menu items as rows: a choice is a dropdown,
-- On / Off a switch, a slider a slider, a color its swatch (a click opens the picker
-- exactly as the menu does), a group a small blue heading and its rows, a plain line a
-- button, a line that only shows a value (Button Key  Not Set) a plain line of text, a
-- separator a 6 px gap; the row's "+" tile (def.add) a button after the cards. Every
-- value is read through the menu's own get / set
-- closures (the menu is read again for it), so Icons and List always agree, and every
-- change draws the page again. Nothing is stored per item: the one setting is
-- opt.oldSettingsLook. With the switch off nothing here runs and the icon rows draw
-- themselves exactly as before.
--
-- Window.lua asks ListLook:Takes(key, row) for every custom row and then calls
-- ListLook:Render(row, body, y, width, element, onChanged) -> firstFrame, height (the
-- height ends with the cards' gap, as a closed section card does) and ListLook:Release()
-- when the page is cleared.
--
-- Also here: SP:ShowOldLookPrompt() (the one-time prompt for players updating to 3.0.8,
-- called by WhatsNew.lua before What's New; What's New follows when it is closed) and
-- ListLook:ShowToggle() (Settings > General > Main with the switch's row in view).
local _, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not (Core and SP and ns.Widgets) then return end
local Widgets = ns.Widgets

local max, min, floor = math.max, math.min, math.floor

local ListLook = {}
ns.ListLook = ListLook

-- the icon rows drawn as lists (their ns.CustomRows keys); every other custom row draws itself
local ROWS = {
	readyIcons = true, ttIcons = true, stripTotems = true, cdbarIcons = true, shieldIcons = true, loadoutIcons = true,
	tbButtons = true, tbTotems = true, eaIcons = true, rtIcons = true, coverageIcons = true, rangeIcons = true,
	popoutIcons = true, raidIcons = true,
}

local CARD_GAP = 12      -- between the cards (Window.lua's CARD_GAP)
local SEP_GAP  = 6       -- a menu separator
local HEAD_H   = 24      -- a group's heading line
local PAD      = Widgets.PAD
local TOGGLE_LABEL = "Use the Old Settings Look"
local MOVE_TEXT = "Drag order: switch back to the icons (turn " .. TOGGLE_LABEL .. " off) to change it."

local function Report(err) geterrorhandler()(err) end
local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if not ok then Report(a) return nil end
	return a, b
end

function ListLook:On() return SP.opt ~= nil and SP.opt.oldSettingsLook == true end
local function DefOf(row) return row and (row.def or row.listDef) or nil end
function ListLook:Takes(key, row)
	return self:On() and ROWS[key] == true and DefOf(row) ~= nil
end

-- ---------------------------------------------------------------------------
-- The menus, read again for every value (so a row always shows what the menu would).
-- Read once per frame: a page draw asks for a menu many times; a change made here
-- invalidates it at once (Invalidate), a change made elsewhere comes in a later frame.
-- ---------------------------------------------------------------------------
local cache = { at = -1, menus = {}, subs = {} }
local function Fresh()
	local now = GetTime()
	if cache.at ~= now then
		cache.at = now
		wipe(cache.menus)
		wipe(cache.subs)
	end
end
local function Invalidate() cache.at = -1 end

local function MenuOf(def, item)
	Fresh()
	local list = cache.menus[item]
	if list then return list end
	list = Call(def.menu, item)
	if type(list) ~= "table" then list = {} end
	cache.menus[item] = list
	return list
end
local function SubOf(entry)
	if not (entry and entry.sub) then return {} end
	Fresh()
	local list = cache.subs[entry]
	if list then return list end
	list = Call(entry.sub)
	if type(list) ~= "table" then list = {} end
	cache.subs[entry] = list
	return list
end

-- a row's place in the menu: { { text, index }, ... } from the root down; found by its
-- text first, by its index when the text changed (Hide This Shield / Show This Shield)
local function Find(list, step)
	for _, e in ipairs(list) do
		if type(e) == "table" and not e.separator and e.text == step.text then return e end
	end
	local e = list[step.index]
	if type(e) == "table" and not e.separator then return e end
	return nil
end
local function Resolve(def, item, path)
	local list = MenuOf(def, item)
	local entry
	for d = 1, #path do
		entry = Find(list, path[d])
		if not entry then return nil end
		if d < #path then list = SubOf(entry) end
	end
	return entry
end
-- the choices of a resolved entry, separators left out
local function Choices(entry, out, onlyChoices)
	wipe(out)
	for _, c in ipairs(SubOf(entry)) do
		if type(c) == "table" and not c.separator and (not onlyChoices or c.selected ~= nil) then out[#out + 1] = c end
	end
	return out
end
-- a choice's own disabled flag (a value or a function), read when it is used
local function ChoiceDisabled(c)
	local d = c and c.disabled
	if type(d) == "function" then d = Call(d) end
	return d and true or false
end
local scratch = {}

-- what an entry is: a separator, a slider, a color, On / Off (a choice of exactly On and
-- Off), a choice (its sub carries `selected`), a group (a sub without), a click, or a
-- value with nothing to do (a disabled line)
local function Kind(entry, sub)
	if entry.separator then return "sep" end
	if entry.slider then return "slider" end
	if entry.swatch then return "swatch" end
	if entry.sub then
		local n, onoff, choice, other, multi = 0, true, false, 0, entry.multi and true or false
		for _, e in ipairs(sub) do
			if type(e) == "table" and not e.separator then
				n = n + 1
				if e.selected ~= nil then
					choice = true
					if not (e.text == "On" or e.text == "Off") then onoff = false end
				else
					other = other + 1
					-- a "(Clear)" line clears several picks: the menu is a pick-any list
					if type(e.text) == "string" and e.text:find("%(Clear%)$") then multi = true end
				end
			end
		end
		-- a pick-any list (Earth Shield's roles and classes): a toggle per pick, then its other lines
		if choice and multi then return "multi" end
		-- choices beside other lines (Fade Instead of Hide: On / Off, then Faded Opacity and Copy
		-- Fade): the choices as one control, the rest as their own rows
		if choice and other > 0 then return (onoff and n - other == 2) and "mixedonoff" or "mixed" end
		if choice and onoff and n == 2 then return "onoff" end
		if choice then return "choice" end
		return "group"
	end
	if entry.onClick then return "button" end
	return "value"
end

-- ---------------------------------------------------------------------------
-- A card's rows, packed as Window.lua packs a section card: two columns, a thin line
-- between the lines, the divider through a run of two-column lines, a label that does
-- not fit its column given the whole line
-- ---------------------------------------------------------------------------
local Pack = {}
Pack.__index = Pack

local function NewPack(body, card, top, fullW, onChanged)
	local p = setmetatable({}, Pack)
	p.body, p.card, p.cardTop, p.fullW, p.onChanged = body, card, top, fullW, onChanged
	p.cellW = floor(fullW / 2)
	p.rowY = top + Widgets.STRIP_H
	p.cardEnd = p.rowY
	p.col, p.rowMaxH, p.lines = 1, 0, 0
	return p
end

function Pack:FlushRun()
	if self.runTop then
		Widgets:CardLine(self.card, self.cellW, self.runTop + 6 - self.cardTop, 1, self.runEnd - self.runTop - 12, "border")
		self.runTop = nil
	end
end

function Pack:EndLine(top, height, twoCol)
	if self.lines > 0 and not self.noLine then
		Widgets:CardLine(self.card, 12, top - self.cardTop, self.fullW - 24, 1, "borderSoft")
	end
	self.noLine = nil
	self.lines = self.lines + 1
	if twoCol then
		self.runTop = self.runTop or top
		self.runEnd = top + height
	else
		self:FlushRun()
	end
	self.cardEnd = top + height
end

function Pack:BreakRow()
	if self.col == 2 then
		self:EndLine(self.rowY, self.rowMaxH, true)
		self.rowY = self.rowY + self.rowMaxH
		self.col, self.rowMaxH = 1, 0
	end
end

-- where the next row goes: x and width (span 2: the whole line)
function Pack:Cell(span)
	local INSET = Widgets.CARD_INSET
	if span == 2 then
		self:BreakRow()
		return INSET, self.fullW - 2 * INSET
	end
	if self.col == 1 then return INSET, self.cellW - 2 * INSET end
	return self.cellW + INSET, self.fullW - self.cellW - 2 * INSET
end

function Pack:Place(f, h, span)
	local INSET = Widgets.CARD_INSET
	if span == 1 and Widgets:LabelTruncated(f) then
		-- a label that cannot fit beside its control: the whole line
		if self.col == 2 then
			self:EndLine(self.rowY, self.rowMaxH, true)
			self.rowY = self.rowY + self.rowMaxH
			self.col, self.rowMaxH = 1, 0
		end
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", self.body, "TOPLEFT", INSET, -self.rowY)
		h = Widgets:Widen(f, self.fullW - 2 * INSET) or h
		span = 2
	end
	if span == 2 then
		self:EndLine(self.rowY, h, false)
		self.rowY = self.rowY + h
		self.col, self.rowMaxH = 1, 0
	else
		self.rowMaxH = max(self.rowMaxH, h)
		if self.col == 2 then
			self:EndLine(self.rowY, self.rowMaxH, true)
			self.rowY = self.rowY + self.rowMaxH
			self.col, self.rowMaxH = 1, 0
		else
			self.col = 2
		end
	end
end

function Pack:Gap(px)
	self:BreakRow()
	self.rowY = self.rowY + px
	self.cardEnd = max(self.cardEnd, self.rowY)
end

function Pack:Finish()
	self:BreakRow()
	self:FlushRun()
	Widgets:CardFinish(self.card, self.cardEnd - self.cardTop)
	return self.cardEnd
end

-- ---------------------------------------------------------------------------
-- A group's heading: small, blue (Core.fonts.group), its value after it (accentHi when
-- the item's own). Pooled here; Window.lua's ClearPage hands them back (Release).
-- ---------------------------------------------------------------------------
local heads = { free = {}, used = {} }

local function NewHead(parent)
	local f = CreateFrame("Frame", nil, parent)
	f.text = f:CreateFontString(nil, "OVERLAY")
	f.text:SetFontObject(Core.fonts.group)
	f.text:SetJustifyH("LEFT")
	f.text:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 5)
	f.value = f:CreateFontString(nil, "OVERLAY")
	f.value:SetFontObject(Core.fonts.strip)
	f.value:SetJustifyH("LEFT")
	f.value:SetPoint("BOTTOMLEFT", f.text, "BOTTOMRIGHT", 8, 0)
	return f
end

local function Heading(pack, text, value, own, disabled)
	local f = table.remove(heads.free) or NewHead(pack.body)
	heads.used[#heads.used + 1] = f
	f:SetParent(pack.body)
	local x, w = pack:Cell(2)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", pack.body, "TOPLEFT", x, -pack.rowY)
	f:SetSize(w, HEAD_H)
	f.text:SetText(text or "")
	f.text:SetTextColor(Core:ColorIf(disabled, "textMute", "accentHi"))
	f.value:SetText(value or "")
	f.value:SetTextColor(Core:ColorIf(own, "accentHi", "textDim"))
	f:Show()
	pack:Place(f, HEAD_H, 2)
	pack.noLine = true   -- its rows belong to it: no line between
end

function ListLook:Release()
	for i = #heads.used, 1, -1 do
		local f = heads.used[i]
		f:Hide()
		f:ClearAllPoints()
		heads.free[#heads.free + 1] = f
		heads.used[i] = nil
	end
end

-- ---------------------------------------------------------------------------
-- A change: the page as the menus do it (the row's onChanged, Row:Changed), then drawn
-- again on the next frame (a change can add or take away rows: Charge Bar on shows Look)
-- ---------------------------------------------------------------------------
local redrawQueued = false
function ListLook:Redraw()
	if redrawQueued then return end
	redrawQueued = true
	C_Timer.After(0, function()
		redrawQueued = false
		local cfg = _G.ShamanPowerConfig
		if cfg and cfg.RefreshCurrent then cfg:RefreshCurrent() end
	end)
end

local function Changed(pack)
	local fn = pack.onChanged
	if fn then
		local ok, err = pcall(fn)
		if not ok then Report(err) end
	end
	ListLook:Redraw()
end

-- a row refused in a fight (the row says why, as its menu does)
local function Refuse(row)
	if row.RefuseLocked then return row:RefuseLocked() end
	return false
end
local function Locked(def)
	return (def.locked and Call(def.locked)) and true or false
end

local function Cap(s) return (s:gsub("^%l", string.upper)) end
-- "save a new loadout" -> "Save A New Loadout" (the buttons' casing)
local function TitleWords(s) return (s:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end)) end

-- the item's own on / off (its icon's click), worded from the row's hint; nil: no such row
-- (a click that is not an on / off, like switching to a loadout: its menu has the line)
local function FirstRowWords(def, name)
	local hint = type(def.hint) == "string" and def.hint:match("^Click:%s*([^\n]+)") or nil
	if not hint then return nil end
	local h = hint:lower()
	local desc = Cap(hint) .. "."
	if h:find("show or hide", 1, true) then return "Show " .. name, desc end
	if h:find("^watch it") then return "Watch " .. name, desc end
	if h:find("^track it") then return "Track " .. name, desc end
	if h:find("turn it on or off", 1, true) then return "Alert On", desc end
	return nil
end

-- ---------------------------------------------------------------------------
-- The rows
-- ---------------------------------------------------------------------------
local function Opts(pack, label, desc, span, disabled)
	local x, w = pack:Cell(span or 1)
	return {
		label = label, desc = desc, x = x, y = pack.rowY, width = w, inCard = true, section = pack.card,
		disabled = disabled, onChanged = function() Changed(pack) end,
	}
end

-- an entry's disabled flag, or one of its parents', read again every time (the menus answer for
-- the moment: a group that was disabled during a fight is not after it)
local function Disabled(ctx, p, forced)
	local def, item = ctx.def, ctx.item
	local prefix = {}
	return function()
		if forced or Locked(def) then return true end
		for d = 1, #p do
			prefix[d] = p[d]
			for k = #prefix, d + 1, -1 do prefix[k] = nil end
			local e = Resolve(def, item, prefix)
			if e and ChoiceDisabled(e) then return true end
		end
		return false
	end
end

local function AddEntries(pack, ctx, list, path, forced, skipChoices)
	local def, item, row = ctx.def, ctx.item, ctx.row
	for index, entry in ipairs(list) do
		if type(entry) == "table" and not (skipChoices and entry.selected ~= nil) then
			local sub = entry.sub and SubOf(entry) or nil
			local kind = Kind(entry, sub)
			local p = {}
			for i = 1, #path do p[i] = path[i] end
			p[#p + 1] = { text = entry.text, index = index }
			local disabled = Disabled(ctx, p, forced)
			local mixed = kind == "mixed" or kind == "mixedonoff"
			if kind == "mixedonoff" then kind = "onoff" elseif kind == "mixed" then kind = "choice" end

			if kind == "sep" then
				pack:Gap(SEP_GAP)

			elseif kind == "group" then
				local vt, vown
				if entry.value then vt, vown = Call(entry.value) end
				Heading(pack, entry.text, vt, vown and true or false, (forced or ChoiceDisabled(entry)) and true or false)
				AddEntries(pack, ctx, sub, p, forced)

			elseif kind == "multi" then
				-- each pick its own On / Off row (a click on a pick toggles it, as the menu's does)
				Heading(pack, entry.text, nil, false, (forced or ChoiceDisabled(entry)) and true or false)
				for ci, c in ipairs(Choices(Resolve(def, item, p), scratch, true)) do
					local text = c.text
					local o = Opts(pack, text, c.tip or entry.tip, 1, disabled)
					o.get = function()
						local cc = Choices(Resolve(def, item, p), scratch, true)[ci]
						if cc and cc.text ~= text then cc = nil; for _, x in ipairs(Choices(Resolve(def, item, p), scratch, true)) do if x.text == text then cc = x end end end
						return cc and cc.selected and true or false
					end
					o.set = function(v)
						if Refuse(row) then return end
						local cc
						for _, x in ipairs(Choices(Resolve(def, item, p), scratch, true)) do if x.text == text then cc = x end end
						if not cc or ChoiceDisabled(cc) or (cc.selected and true or false) == (v and true or false) then return end
						Invalidate()
						if cc.onClick then Call(cc.onClick) end
					end
					local f, h = Widgets:Toggle(pack.body, o)
					pack:Place(f, h, 1)
				end
				AddEntries(pack, ctx, sub, p, forced, true)   -- (its other lines: Everyone (Clear))

			elseif kind == "onoff" then
				local o = Opts(pack, entry.text, entry.tip, 1, disabled)
				o.get = function()
					for _, c in ipairs(Choices(Resolve(def, item, p), scratch, true)) do
						if c.text == "On" then return c.selected and true or false end
					end
					return false
				end
				o.set = function(v)
					if Refuse(row) then return end
					Invalidate()
					local want = v and "On" or "Off"
					for _, c in ipairs(Choices(Resolve(def, item, p), scratch, true)) do
						if c.text == want and ChoiceDisabled(c) then return end
						if c.text == want then
							if not c.selected and c.onClick then Call(c.onClick) end
							return
						end
					end
				end
				local f, h = Widgets:Toggle(pack.body, o)
				pack:Place(f, h, 1)
				if mixed then AddEntries(pack, ctx, sub, p, forced, true) end

			elseif kind == "choice" then
				local o = Opts(pack, entry.text, entry.tip, 1, disabled)
				o.values = function()
					local v = {}
					for i, c in ipairs(Choices(Resolve(def, item, p), scratch, true)) do v[i] = c.text or "" end
					return v
				end
				o.order = function()
					local order = {}
					for i in ipairs(Choices(Resolve(def, item, p), scratch, true)) do order[i] = i end
					return order
				end
				o.get = function()
					for i, c in ipairs(Choices(Resolve(def, item, p), scratch, true)) do
						if c.selected then return i end
					end
					return nil
				end
				o.set = function(i)
					if Refuse(row) then return end
					local c = Choices(Resolve(def, item, p), scratch, true)[i]
					if not c or ChoiceDisabled(c) then return end   -- (a choice the menu grays out)
					Invalidate()
					-- the selected one too: a pick that opens something (Pick Another Icon...) or clears itself
					if c.onClick then Call(c.onClick) end
				end
				o.own = function()
					local e = Resolve(def, item, p)
					if not (e and e.value) then return false end
					local _, own = Call(e.value)
					return own and true or false
				end
				local f, h = Widgets:Dropdown(pack.body, o)
				pack:Place(f, h, 1)
				if mixed then AddEntries(pack, ctx, sub, p, forced, true) end

			elseif kind == "slider" then
				local sl = entry.slider
				local o = Opts(pack, entry.text, entry.tip, 1, disabled)
				o.min, o.max, o.step = sl.min or 0, sl.max or 100, sl.step or 1
				o.isPercent = sl.isPercent and true or false
				o.format = sl.format
				o.get = function()
					local e = Resolve(def, item, p)
					local s = e and e.slider
					local v = s and s.get and Call(s.get)
					return tonumber(v) or (s and s.min) or 0
				end
				o.set = function(v)
					if Refuse(row) then return end
					Invalidate()
					local e = Resolve(def, item, p)
					if e and e.slider and e.slider.set then Call(e.slider.set, v) end
				end
				o.onChanged = pack.onChanged   -- (the page follows a drag as its own sliders do: no redraw)
				local f, h = Widgets:Slider(pack.body, o)
				pack:Place(f, h, 1)

			elseif kind == "swatch" then
				local o = Opts(pack, entry.text, entry.tip, 1, disabled)
				o.hasAlpha = false
				o.get = function()
					local e = Resolve(def, item, p)
					local s = e and e.swatch
					if s then return s[1] or 1, s[2] or 1, s[3] or 1, 1 end
					return 1, 1, 1, 1
				end
				o.set = function() end
				-- the click opens the picker exactly as the menu's line does (the row only shows the color)
				o.click = function()
					if Refuse(row) then return end
					Invalidate()
					local e = Resolve(def, item, p)
					local fn = e and e.onClick
					if not fn and e and e.sub then   -- the picker as the submenu's first line (Pick Color...)
						local first = Choices(e, scratch)[1]
						fn = first and first.onClick
					end
					if fn then Call(fn) end
				end
				local f, h = Widgets:Color(pack.body, o)
				pack:Place(f, h, 1)

			elseif kind == "button" then
				local o = Opts(pack, entry.text, entry.tip, 1, disabled)
				o.buttonText = entry.text
				if entry.value then   -- a line that says something and takes a click (It Shows, Key Now): its words stay
					local vt = Call(entry.value)
					if vt ~= nil and vt ~= "" then o.buttonText = entry.text .. ": " .. tostring(vt) end
				end
				o.func = function()
					if Refuse(row) then return end
					Invalidate()
					local e = Resolve(def, item, p)
					if e and e.onClick then Call(e.onClick) end
				end
				local f, h = Widgets:Button(pack.body, o)
				pack:Place(f, h, 1)

			else   -- a line that only shows a value (Button Key  Not Set): its words, as a plain line
				local vt
				if entry.value then vt = Call(entry.value) end
				vt = vt ~= nil and tostring(vt) or nil
				local x, w = pack:Cell(2)
				local f, h = Widgets:Description(pack.body, {
					text = vt and (entry.text .. ": " .. vt) or entry.text,
					x = x, y = pack.rowY, width = w, inCard = true, section = pack.card,
				})
				pack:Place(f, h, 2)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- The row as a list: a description for a drag order or an empty row, then a card per item
-- ---------------------------------------------------------------------------
function ListLook:Render(row, body, y, fullW, element, onChanged)
	local def = DefOf(row)
	if not def then return nil, 0 end
	row.onChanged = onChanged   -- (the menus' Row:Changed reaches the page as it does with icons)
	local INSET = Widgets.CARD_INSET
	local top, first = y, nil
	local items = {}
	Call(def.list, items)
	local locked = function() return Locked(def) end

	if def.move and #items > 1 then
		local f, h = Widgets:Description(body, { text = MOVE_TEXT, x = INSET, y = y, width = fullW - 2 * INSET })
		first = f
		y = y + h
	end
	if #items == 0 and def.empty then
		local hint = def.empty
		if type(hint) == "function" then hint = Call(hint) end
		local f, h = Widgets:Description(body, { text = hint or "", x = INSET, y = y, width = fullW - 2 * INSET })
		first = first or f
		y = y + h
	end

	for _, item in ipairs(items) do
		local name = item.name or tostring(item.key)
		local learned = (not def.learned) or (Call(def.learned, item) and true or false)
		local card = Widgets:Card(body, { x = 0, y = y, width = fullW, element = element,
			label = learned and name or (name .. " (not learned yet)") })
		first = first or card
		local pack = NewPack(body, card, y, fullW, onChanged)
		local ctx = { row = row, def = def, item = item }

		-- the item's own on / off (a click on its icon): the first row
		if def.toggle and def.shown and not def.clickMenu then
			local label, desc = FirstRowWords(def, name)
			if label then
				local o = Opts(pack, label, desc, 1, locked)
				o.get = function() return Call(def.shown, item) and true or false end
				o.set = function(v)
					if Refuse(row) then return end
					Invalidate()
					if (Call(def.shown, item) and true or false) ~= (v and true or false) then Call(def.toggle, item) end
				end
				local f, h = Widgets:Toggle(body, o)
				pack:Place(f, h, 1)
			end
		end
		if def.menu then AddEntries(pack, ctx, MenuOf(def, item), {}, false) end
		y = pack:Finish() + CARD_GAP
	end

	-- the row's "+" tile (def.add, the Loadouts row's New): a button after the cards, worded
	-- from its hint ("Click: save a new loadout" -> "Save A New Loadout"), its tip as the tooltip
	local add = def.add
	if add and (add.shown == nil or Call(add.shown)) then
		local label = TitleWords((type(add.hint) == "string" and add.hint:match("^Click:%s*([^\n]+)")) or add.name or "New")
		local f, h = Widgets:Button(body, {
			label = label, buttonText = label, desc = add.tip, x = INSET, y = y, width = fullW - 2 * INSET,
			disabled = locked,
			func = function()
				if Refuse(row) then return end
				Invalidate()
				Call(add.click)
			end,
		})
		first = first or f
		y = y + h + CARD_GAP - Widgets.ROW_GAP   -- (ends with the cards' gap, as a card does)
	end
	return first, y - top
end

-- ---------------------------------------------------------------------------
-- Settings > General > Main with the switch's row in view (the prompt's Show Me)
-- ---------------------------------------------------------------------------
function ListLook:ShowToggle()
	local cfg = ns.SPConfig
	if not (cfg and cfg.Open) then return end
	cfg:Open({ "settings", "settings_show", "oldSettingsLook" })
	C_Timer.After(0.05, function()
		local f = _G.ShamanPowerConfigUIFrame
		local body, scroll = f and f.body, f and f.bodyScroll
		if not (body and scroll and f:IsShown()) then return end
		for _, w in ipairs(body._spWidgets or {}) do
			if w.opts and w.opts.label == TOGGLE_LABEL and w:IsShown() then
				local rowTop = (body:GetTop() or 0) - (w:GetTop() or 0)
				local seen = scroll:GetHeight() or 0
				local cur = scroll:GetVerticalScroll() or 0
				if rowTop < cur or rowTop + (w:GetHeight() or 34) > cur + seen then
					local range = scroll:GetVerticalScrollRange() or 0
					scroll:SetVerticalScroll(max(0, min(range, rowTop - 12)))
				end
				return
			end
		end
	end)
end

-- ---------------------------------------------------------------------------
-- The one-time prompt: the first login after updating to 3.0.8, for a shaman who had
-- ShamanPower before (setup done; a new install gets the tour). Saved account-wide the
-- moment it shows (db.global.oldLookPromptSeen). It shows instead of What's New, and
-- What's New comes right after it is closed (any button, the X or Escape): never both.
-- ---------------------------------------------------------------------------
local PROMPT_TEXT = "I have changed how the settings look to make them less confusing: some pages are now a row of icons."
	.. " Click an icon to show or hide it, right-click it for all of its settings."
	.. "\n\nPrefer the old look? Turn on Use the Old Settings Look in General, or press Use the Old Look below."
	.. " You can switch back any time."
local NEW_LOOK = 3000008   -- 3.0.8

local function BaseVersion(v)
	return v and (v:gsub("%-.*$", "")) or nil
end
-- "3.0.8" -> 3000008 (a test build by the part before the dash); nil if unreadable
local function VerNum(v)
	v = BaseVersion(v)
	if not v then return nil end
	local a, b, c = v:match("^(%d+)%.(%d+)%.?(%d*)")
	if not a then return nil end
	return tonumber(a) * 1000000 + tonumber(b) * 1000 + (tonumber(c) or 0)
end

local function PromptDue()
	local g = SP.db and SP.db.global
	if not g or g.oldLookPromptSeen then return false end
	if select(2, UnitClass("player")) ~= "SHAMAN" then return false end   -- (What's New's rule: the stamp is account-wide)
	if SP.IsOff and SP:IsOff() then return false end   -- (ShamanPower switched off: quiet and unstamped, as What's New)
	if not (SP.opt and SP.opt.setupDone) then return false end
	local cur = VerNum(GetAddOnMetadata and GetAddOnMetadata("ShamanPower", "Version"))
	if not cur or cur < NEW_LOOK then return false end
	local seen = VerNum(g.lastSeenVersion)
	if not seen or seen >= NEW_LOOK then return false end   -- (no readable earlier version: a new install, no prompt)
	return true
end
local promptWaiter

-- true: the prompt is up (or waits out a fight) and What's New is its to show afterwards
function SP:ShowOldLookPrompt()
	if not PromptDue() then return false end
	local wiz = _G["ShamanPowerWizard"]
	if wiz and wiz:IsShown() then return false end
	if InCombatLockdown() then
		-- once the fight ends (no polling)
		if not promptWaiter then
			promptWaiter = CreateFrame("Frame")
			promptWaiter:SetScript("OnEvent", function(self)
				self:UnregisterAllEvents()
				if not SP:ShowOldLookPrompt() then SP:ShowWhatsNew() end
			end)
		end
		promptWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
		return true
	end
	local g = SP.db.global
	g.oldLookPromptSeen = true
	SP._oldLookPromptUp = true   -- (What's New waits: ShowWhatsNew defers to `after` below)
	local version = BaseVersion(GetAddOnMetadata and GetAddOnMetadata("ShamanPower", "Version")) or "3.0.8"
	local function after()
		SP._oldLookPromptUp = nil
		local force = SP._whatsNewAfterPrompt == "force"
		SP._whatsNewAfterPrompt = nil
		C_Timer.After(0, function() SP:ShowWhatsNew(force) end)   -- (once this one is gone: never both at once)
	end
	SP:ShowSPDialog({
		key = "oldLook",
		title = "The settings have a new look",
		subtitle = "ShamanPower " .. version,
		text = PROMPT_TEXT,
		width = 420,
		strata = "DIALOG",
		buttons = {
			{ text = "Show Me", onClick = function()
				ListLook:ShowToggle()
				after()
			end },
			{ text = "Use the Old Look", onClick = function()
				SP.opt.oldSettingsLook = true
				g.oldLookSeen = true
				local cfg = _G.ShamanPowerConfig
				if cfg and cfg.IsOpen and cfg:IsOpen() and cfg.RefreshCurrent then cfg:RefreshCurrent() end
				after()
			end },
			{ text = "Keep the New Look", onClick = after },
		},
		onEscape = after,
	})
	return true
end
