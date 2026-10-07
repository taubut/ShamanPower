-- ============================================================================
-- Controller Mode (WoW: Forever): the totem picker
--
-- The pad layer (ShamanPowerControllerPad.lua) binds RB to the secure button
-- ShamanPowerControllerPickerOpen while LB is held, so LB + RB opens a column
-- of one element's totems above that element's slot on the controller bar
-- (SP.Controller.slot.earth / fire / water / air; ShamanPowerController.lua).
-- It opens on the element used last (Earth to start). While it is open the
-- picker holds six pad buttons of its own, as priority override bindings:
--   d-pad Up / Down     move the highlight through the column (it wraps round)
--   d-pad Left / Right  the previous / next element's column
--   A (PAD1)            pick: clicks the highlighted totem's own secure button,
--                       which drops that totem (in a fight too); out of a
--                       fight the pick also becomes that element's totem
--   B (PAD2)            close
-- A pick closes the picker too. Closing clears all six bindings, so the pad is
-- Blizzard's again.
--
-- In a fight: the header's restricted snippets do everything. They show and
-- hide the column frames and each totem's highlight frames, size and place the
-- totem buttons, and set / clear the override bindings. No insecure code
-- touches a protected frame or a binding during a fight. The totem lists,
-- attributes, anchors, sizes and textures are set out of a fight only; a
-- change during one (a spell learned, a respec, the look switched) waits for
-- PLAYER_REGEN_ENABLED. The column leaves out the element's assigned totem, as
-- the flyouts do: the snippet compares each button with the totem button's
-- spell when the column opens, so a mid-fight flyout pick is followed.
--
-- Needs working secure snippets (SPCompat.SecureSnippetsWork()); where they
-- do not work the picker never gets ready and the open button does nothing.
-- Anniversary has no controller mode: this file does nothing there.
-- ============================================================================

local SP = ShamanPower
if not SP then return end
if not (SPCompat and SPCompat.FOREVER) then return end

local P = {}
-- SP.Controller is the bar's namespace (ShamanPowerController.lua). Looked up
-- again every time it is used, so the load order of the two files never matters.
local function Ctl()
	local c = SP.Controller
	if type(c) ~= "table" then c = {}; SP.Controller = c end
	if c.Picker ~= P then c.Picker = P end
	return c
end
Ctl()

local ELEMENT_KEY = { "earth", "fire", "water", "air" }
local TEX = "Interface\\AddOns\\ShamanPower\\Media\\Textures\\"
local HEADER_NAME = "ShamanPowerControllerPicker"
local OPEN_NAME = "ShamanPowerControllerPickerOpen"   -- the pad layer binds RB to this name
local KEYS_NAME = "ShamanPowerControllerPickerKeys"
local PICK_PREFIX = "ShamanPowerControllerPick"
-- the picker's own pad buttons (fixed: they exist only while it is open)
local HINTS = {
	{ key = "PADDUP",   text = "Scroll up",   fallback = "Up" },
	{ key = "PADDDOWN", text = "Scroll down", fallback = "Down" },
	{ key = "PAD1",     text = "Pick",        fallback = "A" },
	{ key = "PAD2",     text = "Close",       fallback = "B" },
}
local PLATE = { 0.031, 0.047, 0.078, 0.82 }   -- the column's dark plate (A19)
local DISC = { 0.020, 0.025, 0.035, 0.95 }    -- behind each round icon

-- ---------------------------------------------------------------------------
-- The restricted snippets (attributes of the header, run with RunAttribute)
--   header attributes, set out of a fight: n<e> totems listed for element e,
--   frame refs b<e>_<i> (button), g<e>_<i> (glow behind it), d<e>_<i> (gold
--   ring + name over it), c<e> (column), t<e> (the totem bar's button for e),
--   keys; sp-small / sp-big / sp-pitch / sp-pad sizes; sp-cnt and o<pos> / p<e>
--   (the columns' order left to right, or clockwise from the top for the d-pad
--   cross); sp-ready. Column attribute sp-dir: 1 = grows up, -1 = down.
--   state: sp-isopen, sp-e (element shown, kept for the next open), sp-k
--   (highlighted row), m<e> (rows shown), button sp-k (its row, 0 = left out).
-- ---------------------------------------------------------------------------
local SNIPPETS = {}

-- (e) lay column e out: leave out the assigned totem, stack the rest from the
-- slot outward, all small and unlit. Returns the number of rows.
SNIPPETS["spx-layout"] = [[
	local e = ...
	local n = self:GetAttribute("n" .. e) or 0
	local c = self:GetFrameRef("c" .. e)
	if n < 1 or not c then
		self:SetAttribute("m" .. e, 0)
		return 0
	end
	local t = self:GetFrameRef("t" .. e)
	local cur = t and t:GetAttribute("spell1")
	local up = (c:GetAttribute("sp-dir") or 1) > 0
	local small = self:GetAttribute("sp-small") or 30
	local pitch = self:GetAttribute("sp-pitch") or 40
	local pad = self:GetAttribute("sp-pad") or 5
	local m = 0
	for i = 1, n do
		local b = self:GetFrameRef("b" .. e .. "_" .. i)
		if b then
			local g = self:GetFrameRef("g" .. e .. "_" .. i)
			local d = self:GetFrameRef("d" .. e .. "_" .. i)
			if g then g:Hide() end
			if d then d:Hide() end
			b:SetWidth(small)
			b:SetHeight(small)
			if cur and b:GetAttribute("sp-spell") == cur then
				b:SetAttribute("sp-k", 0)
				b:Hide()
			else
				m = m + 1
				b:SetAttribute("sp-k", m)
				b:ClearAllPoints()
				if up then
					b:SetPoint("CENTER", c, "BOTTOM", 0, pad + (m - 0.5) * pitch)
				else
					b:SetPoint("CENTER", c, "TOP", 0, -(pad + (m - 0.5) * pitch))
				end
				b:Show()
			end
		end
	end
	if m > 0 then c:SetHeight(pad * 2 + m * pitch) end
	self:SetAttribute("m" .. e, m)
	return m
]]

-- (k) highlight row k of the shown column (wraps round): bigger, gold glow,
-- gold ring and name; A now clicks that totem's button.
SNIPPETS["spx-select"] = [[
	local k = ...
	local e = self:GetAttribute("sp-e") or 1
	local m = self:GetAttribute("m" .. e) or 0
	if m < 1 then return end
	if k < 1 then k = m elseif k > m then k = 1 end
	self:SetAttribute("sp-k", k)
	local n = self:GetAttribute("n" .. e) or 0
	local small = self:GetAttribute("sp-small") or 30
	local big = self:GetAttribute("sp-big") or 38
	for i = 1, n do
		local b = self:GetFrameRef("b" .. e .. "_" .. i)
		if b then
			local g = self:GetFrameRef("g" .. e .. "_" .. i)
			local d = self:GetFrameRef("d" .. e .. "_" .. i)
			if b:GetAttribute("sp-k") == k then
				b:SetWidth(big)
				b:SetHeight(big)
				if g then g:Show() end
				if d then d:Show() end
				self:SetBindingClick(true, "PAD1", b)
			else
				b:SetWidth(small)
				b:SetHeight(small)
				if g then g:Hide() end
				if d then d:Hide() end
			end
		end
	end
]]

-- (e) show element e's column (when it has a totem to offer), hide the others.
SNIPPETS["spx-column"] = [[
	local e = ...
	if self:RunAttribute("spx-layout", e) < 1 then return false end
	for i = 1, 4 do
		local c = self:GetFrameRef("c" .. i)
		if c then
			if i == e then c:Show() else c:Hide() end
		end
	end
	local up = (self:GetFrameRef("c" .. e):GetAttribute("sp-dir") or 1) > 0
	local hb, ha = self:GetFrameRef("hb"), self:GetFrameRef("ha")
	if hb then if up then hb:Show() else hb:Hide() end end
	if ha then if up then ha:Hide() else ha:Show() end end
	self:SetAttribute("sp-e", e)
	self:RunAttribute("spx-select", 1)
	return true
]]

SNIPPETS["spx-open"] = [[
	self:CallMethod("SPBeforeOpen")   -- out of a fight: reads the bar's spot, size and glyphs again (a fight: nothing)
	if not self:GetAttribute("sp-ready") then return end
	local cnt = self:GetAttribute("sp-cnt") or 0
	if cnt < 1 then return end
	local p = self:GetAttribute("p" .. (self:GetAttribute("sp-e") or 1)) or 1
	local shown = false
	for i = 0, cnt - 1 do
		local x = self:GetAttribute("o" .. ((p - 1 + i) % cnt + 1))
		if x and self:RunAttribute("spx-column", x) then
			shown = true
			break
		end
	end
	if not shown then return end
	self:SetAttribute("sp-isopen", true)
	self:Show()
	local keys = self:GetFrameRef("keys")
	self:SetBindingClick(true, "PADDUP", keys, "Up")
	self:SetBindingClick(true, "PADDDOWN", keys, "Down")
	self:SetBindingClick(true, "PADDLEFT", keys, "Left")
	self:SetBindingClick(true, "PADDRIGHT", keys, "Right")
	self:SetBindingClick(true, "PAD2", keys, "Close")
]]

SNIPPETS["spx-close"] = [[
	self:ClearBindings()
	self:SetAttribute("sp-isopen", false)
	for i = 1, 4 do
		local c = self:GetFrameRef("c" .. i)
		if c then c:Hide() end
	end
	self:Hide()
]]

SNIPPETS["spx-toggle"] = [[
	if self:GetAttribute("sp-isopen") then
		self:RunAttribute("spx-close")
	else
		self:RunAttribute("spx-open")
	end
]]

-- (button) one of the picker's own pad buttons: Up / Down / Left / Right /
-- Close, or Done (pressed by a pick's macro after the cast).
SNIPPETS["spx-key"] = [[
	local button = ...
	if not self:GetAttribute("sp-isopen") then return end
	if button == "Close" or button == "Done" then
		self:RunAttribute("spx-close")
		return
	end
	local e = self:GetAttribute("sp-e") or 1
	if button == "Up" or button == "Down" then
		local c = self:GetFrameRef("c" .. e)
		local dir = c and c:GetAttribute("sp-dir") or 1
		if button == "Down" then dir = -dir end
		self:RunAttribute("spx-select", (self:GetAttribute("sp-k") or 1) + dir)
	elseif button == "Left" or button == "Right" then
		local cnt = self:GetAttribute("sp-cnt") or 0
		local p = self:GetAttribute("p" .. e) or 1
		local step = 1
		if button == "Left" then step = -1 end
		for i = 1, cnt - 1 do
			local x = self:GetAttribute("o" .. ((p - 1 + step * i) % cnt + 1))
			if x and self:RunAttribute("spx-column", x) then return end
		end
	end
]]

-- The pad buttons arrive as clicks with a mouse-button name; the binding sends
-- the press (down) and the let-go: only the press counts. "Done" comes once,
-- from a pick's macro (/click sends a release).
local KEYS_ONCLICK = [[
	if button ~= "Done" and not down then return end
	local picker = self:GetFrameRef("picker")
	if picker then picker:RunAttribute("spx-key", button) end
]]
local OPEN_ONCLICK = [[
	if not down then return end
	local picker = self:GetFrameRef("picker")
	if picker then picker:RunAttribute("spx-toggle") end
]]

-- ---------------------------------------------------------------------------
-- Frames. The header, the open button and the key button exist from file load
-- (the pad layer wires RB to the open button at PLAYER_LOGIN); their snippets
-- are written out of a fight.
-- ---------------------------------------------------------------------------
local header = CreateFrame("Frame", HEADER_NAME, UIParent, "SecureHandlerBaseTemplate")
local keys = CreateFrame("Button", KEYS_NAME, UIParent, "SecureHandlerClickTemplate")
local open = CreateFrame("Button", OPEN_NAME, UIParent, "SecureHandlerClickTemplate")
P.header, P.keys, P.open = header, keys, open
P.cols, P.lists, P.made = {}, { {}, {}, {}, {} }, { {}, {}, {}, {} }

-- out of a fight: write the snippets and the fixed refs (once)
function P:Wire()
	if self.wired then return true end
	if InCombatLockdown() then self.dirty = true return false end
	-- a client that cannot run snippets would throw on every press: leave the buttons inert
	if SPCompat.SecureSnippetsWork and not SPCompat.SecureSnippetsWork() then return false end
	header:SetFrameStrata("DIALOG")   -- over the controller bar, like the totem flyouts
	header:SetSize(1, 1)
	header:SetPoint("CENTER", UIParent, "CENTER")
	header:Hide()
	for name, body in pairs(SNIPPETS) do header:SetAttribute(name, body) end
	header:SetAttribute("sp-e", 1)
	header:SetAttribute("sp-isopen", false)
	header:SetAttribute("sp-ready", false)
	for i, b in ipairs({ keys, open }) do
		b:SetSize(1, 1)
		b:SetPoint("CENTER", UIParent, "CENTER")
		b:EnableMouse(false)
		b:RegisterForClicks("AnyUp", "AnyDown")
		b:SetFrameRef("picker", header)
		b:SetAttribute("_onclick", i == 1 and KEYS_ONCLICK or OPEN_ONCLICK)
	end
	header:SetFrameRef("keys", keys)
	for e = 1, 4 do
		local col = self:Column(e)
		header:SetFrameRef("c" .. e, col)
		local tb = SP.totemButtons and SP.totemButtons[e]
		if tb then header:SetFrameRef("t" .. e, tb) end
	end
	-- the CallMethod target (insecure, runs before every open; does nothing in a fight)
	header.SPBeforeOpen = function() P:BeforeOpen() end
	self.wired = true
	return true
end

local function Gold()
	local c = NORMAL_FONT_COLOR   -- WoW's own gold
	if c and c.r then return c.r, c.g, c.b end
	return 1, 0.82, 0
end

local function LabelFont(fs, size)
	local path = SP.Brand and SP.Brand.fonts and SP.Brand.fonts.semibold
	if SP.SetSPFont then
		SP:SetSPFont(fs, "labels", size, "OUTLINE", path)
	else
		fs:SetFont(path or STANDARD_TEXT_FONT, size, "OUTLINE")
	end
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 0.9)
end

-- a column: the rounded dark plate (two half discs and a band) the totems sit on
function P:Column(e)
	local col = self.cols[e]
	if col then return col end
	col = CreateFrame("Frame", HEADER_NAME .. "Col" .. e, header, "SecureFrameTemplate")
	col:Hide()
	col:SetSize(40, 40)
	local top = col:CreateTexture(nil, "BACKGROUND")
	top:SetTexture(TEX .. "Mask_Circle")
	top:SetTexCoord(0, 1, 0, 0.5)
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	local bot = col:CreateTexture(nil, "BACKGROUND")
	bot:SetTexture(TEX .. "Mask_Circle")
	bot:SetTexCoord(0, 1, 0.5, 1)
	bot:SetPoint("BOTTOMLEFT")
	bot:SetPoint("BOTTOMRIGHT")
	local mid = col:CreateTexture(nil, "BACKGROUND")
	mid:SetColorTexture(1, 1, 1, 1)
	mid:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
	mid:SetPoint("BOTTOMRIGHT", bot, "TOPRIGHT")
	for _, t in ipairs({ top, bot, mid }) do t:SetVertexColor(PLATE[1], PLATE[2], PLATE[3], PLATE[4]) end
	col.capTop, col.capBot = top, bot
	self.cols[e] = col
	return col
end

-- PostClick of a pick: the secure click already dropped the totem. Out of a
-- fight the pick also becomes the element's totem (the flyout's own path,
-- ShamanPower:ApplyAssignment); in a fight nothing else changes. Only the click
-- that acted counts (the binding sends a press and a let-go).
local function PickPostClick(self, _, down)
	if InCombatLockdown() then return end
	local onDown
	if SecureActionButton_ShouldUseOnKeyDown then
		onDown = SecureActionButton_ShouldUseOnKeyDown(self) and true or false
	else
		onDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") and true or false
	end
	if (down and true or false) ~= onDown then return end
	if self.spElement and self.spIndex and SP.ApplyAssignment then
		SP:ApplyAssignment(self.spElement, self.spIndex)
	end
end

-- one totem's button: a secure action button (macro: cast, then close the
-- picker), its round look, and two highlight frames the snippets show / hide
function P:Button(e, idx)
	local made = self.made[e]
	local b = made[idx]
	if b then return b end
	local name = PICK_PREFIX .. e .. "_" .. idx
	b = CreateFrame("Button", name, self:Column(e), "SecureActionButtonTemplate")
	b:Hide()
	b:EnableMouse(false)   -- a pad window: the picks come from A, never from a stray mouse click
	b:RegisterForClicks("AnyUp", "AnyDown")
	b.spElement, b.spIndex = e, idx

	local disc = b:CreateTexture(nil, "BACKGROUND")
	disc:SetTexture(TEX .. "Mask_Circle")
	disc:SetVertexColor(DISC[1], DISC[2], DISC[3], DISC[4])
	disc:SetAllPoints(b)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
	icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local mask = b:CreateMaskTexture()
	mask:SetTexture(TEX .. "Mask_Circle", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(icon)
	icon:AddMaskTexture(mask)
	local ring = b:CreateTexture(nil, "OVERLAY")
	ring:SetAllPoints(b)
	b.icon, b.ring = icon, ring

	-- behind the button: the soft gold glow (a sibling one level down, so it
	-- draws under the icon)
	local g = CreateFrame("Frame", name .. "Glow", self:Column(e), "SecureFrameTemplate")
	g:Hide()
	g:SetAllPoints(b)
	local glow = g:CreateTexture(nil, "BACKGROUND")
	glow:SetTexture(SP.Brand and SP.Brand.radialLight or (TEX .. "SP_RadialLight"))
	glow:SetBlendMode("ADD")
	glow:SetPoint("CENTER", g, "CENTER")
	g.tex = glow
	-- over the button: the gold ring and the totem's name
	local d = CreateFrame("Frame", name .. "Lit", b, "SecureFrameTemplate")
	d:Hide()
	d:SetAllPoints(b)
	local gold = d:CreateTexture(nil, "OVERLAY")
	gold:SetAllPoints(d)
	local label = d:CreateFontString(nil, "OVERLAY")
	LabelFont(label, 13)   -- (never given a width: the whole name always shows)
	d.ring, d.label = gold, label
	b.glow, b.lit = g, d

	b:SetScript("PostClick", PickPostClick)
	made[idx] = b
	return b
end

-- ---------------------------------------------------------------------------
-- Out of a fight: the lists, the look and the spot
-- ---------------------------------------------------------------------------
-- the element's totems, as the totem bar's flyout lists them: known (by spell
-- ID, every rank), castable by name, and not switched off in the flyout's list
local function ListTotems(e, out)
	wipe(out)
	local totems = SP.Totems and SP.Totems[e]
	if not totems then return out end
	local on = SP.opt and SP.opt.flyoutTotems
	for idx, spellID in pairs(totems) do
		local cast = GetSpellInfo(spellID)
		if SPCompat.HasTotemCastAliases(spellID) then cast = SPCompat.TotemCastName(spellID) end
		local enabled = on == nil or on[ELEMENT_KEY[e] .. "_" .. idx] ~= false
		if cast and enabled and SP.PlayerKnowsTotem and SP.PlayerKnowsTotem(spellID) then out[#out + 1] = idx end
	end
	table.sort(out)
	return out
end

-- what the lists hold now, as text (to tell whether a refresh changes them)
local keyParts, keyScratch = {}, {}
function P:ListsKey()
	wipe(keyParts)
	for e = 1, 4 do keyParts[e] = table.concat(ListTotems(e, keyScratch), ",") end
	return table.concat(keyParts, "|")
end

function P:FillLists()
	self.listsKey = self:ListsKey()
	for e = 1, 4 do
		local list = ListTotems(e, self.lists[e])
		for _, b in pairs(self.made[e]) do
			b:Hide()
			b.glow:Hide()
			b.lit:Hide()
			b.spListed = nil
		end
		for k, idx in ipairs(list) do
			local spellID = SP.Totems[e][idx]
			local cast = GetSpellInfo(spellID)
			if SPCompat.HasTotemCastAliases(spellID) then cast = SPCompat.TotemCastName(spellID) end
			local b = self:Button(e, idx)
			b:SetAttribute("type", "macro")
			b:SetAttribute("macrotext", "/cast " .. cast .. "\n/click " .. KEYS_NAME .. " Done")
			b:SetAttribute("sp-spell", cast)   -- compared with the totem button's spell1 (the flyouts' rule)
			b:SetAttribute("sp-k", 0)
			b.icon:SetTexture(SP.GetTotemIcon and SP:GetTotemIcon(e, idx) or "Interface\\Icons\\INV_Misc_QuestionMark")
			b.lit.label:SetText(GetSpellInfo(spellID) or cast)
			b.spListed = true
			header:SetFrameRef("b" .. e .. "_" .. k, b)
			header:SetFrameRef("g" .. e .. "_" .. k, b.glow)
			header:SetFrameRef("d" .. e .. "_" .. k, b.lit)
		end
		header:SetAttribute("n" .. e, #list)
		header:SetAttribute("m" .. e, 0)
		local tb = SP.totemButtons and SP.totemButtons[e]
		if tb then header:SetFrameRef("t" .. e, tb) end
	end
end

-- a frame's rectangle in UIParent units (nil while it has no spot)
local function Rect(f)
	if not (f and f.GetLeft and f:IsShown()) then return nil end
	local l, b, w, h = f:GetLeft(), f:GetBottom(), f:GetWidth(), f:GetHeight()
	if not (l and b and w and h) then return nil end
	local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return l * k, b * k, (l + w) * k, (b + h) * k
end

-- a pad button's picture from the bar's Glyph (an atlas name, a file, or a
-- table { atlas = } / { file =, coords = }); false = none to show
local function SetGlyph(tex, key, size)
	local c = Ctl()
	if not c.Glyph then return false end
	local ok, g = pcall(c.Glyph, c, key, size)
	if not ok or g == nil or g == false then return false end
	local atlas, file, coords
	if type(g) == "table" then
		atlas, file, coords = g.atlas, g.file or g.texture, g.coords
	elseif type(g) == "string" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(g) then
		atlas = g
	else
		file = g
	end
	if atlas then
		tex:SetAtlas(atlas)
	elseif file then
		tex:SetTexture(file)
		if type(coords) == "table" and #coords >= 4 then tex:SetTexCoord(unpack(coords)) else tex:SetTexCoord(0, 1, 0, 1) end
	else
		return false
	end
	return true
end

-- the hints row: Scroll up / Scroll down / Pick / Close with the real glyphs.
-- Two copies: row 1 under the bar (beside it when the screen ends below), row 2
-- over it, for a column that opens downward; spx-column shows the free one.
function P:Hints(i, size, font)
	self.hints = self.hints or {}
	local f = self.hints[i]
	if not f then
		f = CreateFrame("Frame", HEADER_NAME .. "Hints" .. i, header, "SecureFrameTemplate")
		f:SetShown(i == 1)
		header:SetFrameRef(i == 1 and "hb" or "ha", f)
		f.items = {}
		for i, h in ipairs(HINTS) do
			local it = {}
			it.glyph = f:CreateTexture(nil, "ARTWORK")
			it.key = f:CreateFontString(nil, "OVERLAY")   -- the key's name, when there is no picture
			it.text = f:CreateFontString(nil, "OVERLAY")
			f.items[#f.items + 1] = it
		end
		self.hints[i] = f
	end
	local x = 0
	for n, h in ipairs(HINTS) do
		local it = f.items[n]
		LabelFont(it.text, font)
		it.text:SetTextColor(0.94, 0.94, 0.94)
		it.text:SetText(h.text)
		it.glyph:SetSize(size, size)
		it.glyph:ClearAllPoints()
		it.glyph:SetPoint("LEFT", f, "LEFT", x, 0)
		it.key:ClearAllPoints()
		it.key:SetPoint("LEFT", f, "LEFT", x, 0)
		local w
		if SetGlyph(it.glyph, h.key, size) then
			it.glyph:Show()
			it.key:Hide()
			w = size
		else
			it.glyph:Hide()
			LabelFont(it.key, font)
			local r, g, b = Gold()
			it.key:SetTextColor(r, g, b)
			it.key:SetText(h.fallback)
			it.key:Show()
			w = math.ceil(it.key:GetStringWidth())
		end
		it.text:ClearAllPoints()
		it.text:SetPoint("LEFT", f, "LEFT", x + w + 5, 0)
		x = x + w + 5 + math.ceil(it.text:GetStringWidth()) + (n < #HINTS and 18 or 0)
	end
	f:SetSize(math.max(x, 1), size)
	return f
end

-- the look and the spot, from the bar's slots: size (the slots' size), which
-- way each column grows, which side the names go, the columns' order
function P:Place()
	local c = Ctl()
	local slots = c.slot
	if type(slots) ~= "table" then return false end
	local ref
	for e = 1, 4 do
		ref = ref or (slots[ELEMENT_KEY[e]] and slots[ELEMENT_KEY[e]]:IsShown() and slots[ELEMENT_KEY[e]])
	end
	if not ref then return false end
	local ui = UIParent:GetEffectiveScale()
	local s = ref:GetEffectiveScale() / ui
	header:SetScale(s)   -- draws in the bar's scale (Size %)
	local B = ref:GetWidth() or 40
	if B < 20 then B = 40 end
	local small = math.floor(B * 0.74 + 0.5)
	local big = math.floor(B * 0.92 + 0.5)
	local pitch = big + 6
	local pad = 5
	local W = big + 10
	local gap = math.floor(B * 0.12 + 0.5)
	header:SetAttribute("sp-small", small)
	header:SetAttribute("sp-big", big)
	header:SetAttribute("sp-pitch", pitch)
	header:SetAttribute("sp-pad", pad)
	local font = math.max(11, math.floor(B * 0.34 + 0.5))
	local ringK = math.min(12, math.max(1, math.floor(64 * 2.2 / small + 0.5)))
	local goldK = math.min(12, math.max(1, math.floor(64 * 3 / big + 0.5)))
	local gr, gg, gb = Gold()

	-- where the slots are (UIParent units): order, direction, label side
	local rects, cx, cy, nPresent = {}, 0, 0, 0
	for e = 1, 4 do
		local l, b, r, t = Rect(slots[ELEMENT_KEY[e]])
		if l then
			rects[e] = { l, b, r, t, (l + r) / 2, (b + t) / 2 }
			cx, cy, nPresent = cx + (l + r) / 2, cy + (b + t) / 2, nPresent + 1
		end
	end
	if nPresent == 0 then return false end
	cx, cy = cx / nPresent, cy / nPresent
	local others = {}   -- every slot of the bar (Drop All too) for "is something above me"
	for key, f in pairs(slots) do
		local l, b, r, t = Rect(f)
		if l then others[#others + 1] = { key, (l + r) / 2, (b + t) / 2 } end
	end
	local Bs = B * s
	local row = true
	for e = 1, 4 do
		if rects[e] and math.abs(rects[e][6] - cy) > Bs * 0.5 then row = false end
	end
	local order = {}
	for e = 1, 4 do if rects[e] then order[#order + 1] = e end end
	if row then
		table.sort(order, function(a, b) return rects[a][5] < rects[b][5] end)
	else
		-- clockwise from the top (the d-pad cross: Earth, Fire, Water, Air)
		local function ang(e)
			local a = math.atan2(rects[e][5] - cx, rects[e][6] - cy)
			if a < -0.0001 then a = a + 2 * math.pi end
			return a
		end
		table.sort(order, function(a, b) return ang(a) < ang(b) end)
	end
	header:SetAttribute("sp-cnt", #order)
	for i = 1, 4 do header:SetAttribute("o" .. i, order[i]) end
	for e = 1, 4 do header:SetAttribute("p" .. e, nil) end
	for i, e in ipairs(order) do header:SetAttribute("p" .. e, i) end

	local screenH = UIParent:GetHeight()
	local screenW = UIParent:GetWidth()
	for e = 1, 4 do
		local col = self:Column(e)
		local slot = slots[ELEMENT_KEY[e]]
		local rc = rects[e]
		col:SetWidth(W)
		col.capTop:SetHeight(W / 2)
		col.capBot:SetHeight(W / 2)
		col:SetFrameLevel(header:GetFrameLevel() + 2)
		if rc then
			local n = #self.lists[e]
			local colH = (pad * 2 + math.max(n - 1, 1) * pitch + gap) * s
			-- up, unless another slot sits right above (the cross's Water) or the screen ends
			local over   -- the highest slot right above this one (the cross's Water: Drop All, Earth)
			for _, o in ipairs(others) do
				if o[1] ~= ELEMENT_KEY[e] and math.abs(o[2] - rc[5]) < Bs * 0.6 and o[3] > rc[6] + Bs * 0.25
					and (not over or o[3] > over[3]) then over = o end
			end
			local roomUp, roomDown = rc[4] + colH <= screenH, rc[2] - colH >= 0
			local dir, anchor = 1, slot
			if over then
				if roomDown then dir = -1 else anchor = slots[over[1]] end   -- no room below: over the whole bar
			elseif not roomUp and roomDown then
				dir = -1
			end
			col:SetAttribute("sp-dir", dir)
			col:ClearAllPoints()
			if dir == 1 then
				col:SetPoint("BOTTOM", anchor, "TOP", 0, gap)
			else
				col:SetPoint("TOP", anchor, "BOTTOM", 0, -gap)
			end
			col:SetClampedToScreen(true)
			col:SetHeight(pad * 2 + math.max(n - 1, 1) * pitch)
			-- names on the side away from the bar's middle (and away from the screen's edge)
			local right = rc[5] >= cx - Bs * 0.25
			if right and rc[3] + 160 * s > screenW then right = false end
			if not right and rc[1] - 160 * s < 0 then right = true end
			col.spNameRight = right
		end
		for _, b in pairs(self.made[e]) do
			b:SetSize(small, small)
			b:SetFrameLevel(col:GetFrameLevel() + 2)
			b.glow:SetFrameLevel(col:GetFrameLevel() + 1)
			b.lit:SetFrameLevel(col:GetFrameLevel() + 3)
			local er, eg, eb = SP:ElementPaletteColor(e)
			b.ring:SetTexture(TEX .. "Ring_Circle_" .. ringK)
			b.ring:SetVertexColor(er, eg, eb, 1)
			b.glow.tex:SetSize(big * 1.9, big * 1.9)
			b.glow.tex:SetVertexColor(gr, gg, gb, 0.7)
			b.lit.ring:SetTexture(TEX .. "Ring_Circle_" .. goldK)
			b.lit.ring:SetVertexColor(gr, gg, gb, 1)
			local label = b.lit.label
			LabelFont(label, font)
			label:SetTextColor(gr, gg, gb)
			label:ClearAllPoints()
			if col.spNameRight == false then
				label:SetJustifyH("RIGHT")
				label:SetPoint("RIGHT", b, "LEFT", -6, 0)
			else
				label:SetJustifyH("LEFT")
				label:SetPoint("LEFT", b, "RIGHT", 6, 0)
			end
		end
	end

	-- the hints rows: under the bar (beside it when the screen ends below), and over it
	local gsize, gfont = math.floor(B * 0.5 + 0.5), math.max(11, math.floor(B * 0.3 + 0.5))
	local below, above = self:Hints(1, gsize, gfont), self:Hints(2, gsize, gfont)
	local bar = (c.frame and c.frame.GetBottom and c.frame) or ref
	local _, bb = Rect(bar)
	local hgap = math.floor(B * 0.2 + 0.5)
	below:ClearAllPoints()
	if bb and bb - (below:GetHeight() + hgap + 4) * s < 0 then
		below:SetPoint("LEFT", bar, "RIGHT", 14, 0)
	else
		below:SetPoint("TOP", bar, "BOTTOM", 0, -hgap)
	end
	above:ClearAllPoints()
	above:SetPoint("BOTTOM", bar, "TOP", 0, hgap)
	for _, f in ipairs(self.hints) do f:SetClampedToScreen(true) end
	return true
end

-- Is the picker for now? The controller look on, its slots built, ShamanPower
-- on, and secure snippets working on this client.
function P:ShouldRun()
	if SP.IsOff and SP:IsOff() then return false end
	local c = Ctl()
	if not (c.IsActive and c:IsActive()) then return false end
	if type(c.slot) ~= "table" then return false end
	if SPCompat.SecureSnippetsWork and not SPCompat.SecureSnippetsWork() then return false end
	return true
end

function P:Available()
	return (self.wired and header:GetAttribute("sp-ready")) and true or false
end

-- close it and release the pad (out of a fight)
function P:Shutdown()
	if InCombatLockdown() then self.dirty = true return end
	if not self.wired then return end
	ClearOverrideBindings(header)
	header:SetAttribute("sp-isopen", false)
	header:SetAttribute("sp-ready", false)
	for e = 1, 4 do if self.cols[e] then self.cols[e]:Hide() end end
	header:Hide()
end

-- Everything again, out of a fight (a fight: when it ends).
function P:Refresh()
	self:Hook()
	if InCombatLockdown() then self.dirty = true return false end
	self.dirty = nil
	if not self:Wire() then return false end
	if not self:ShouldRun() then self:Shutdown() return false end
	if header:GetAttribute("sp-isopen") then
		-- open: leave it alone unless its totems changed (then close it and build them again)
		if self:ListsKey() == self.listsKey then return true end
		self:Shutdown()
	end
	self:FillLists()
	local placed = self:Place()
	header:SetAttribute("sp-ready", placed and true or false)
	return placed
end

-- run by spx-open through CallMethod: out of a fight read the bar again (it
-- may have moved, changed size or layout, or the pad type changed)
function P:BeforeOpen()
	if InCombatLockdown() then return end
	if self.dirty or not header:GetAttribute("sp-ready") then
		self:Refresh()
	elseif self:ShouldRun() then
		self:Place()
	else
		self:Shutdown()
	end
end

-- ---------------------------------------------------------------------------
-- Events: nothing runs while idle. Changes are gathered into one refresh.
-- ---------------------------------------------------------------------------
local queued
local function Queue()
	if queued then return end
	queued = true
	C_Timer.After(0, function()
		queued = nil
		P:Refresh()
	end)
end
P.Queue = Queue

-- the bar's on / off callback and the flyout list changes (once each)
function P:Hook()
	local c = Ctl()
	if not self.hookedChange and c.OnChange then
		self.hookedChange = true
		c:OnChange(function() if InCombatLockdown() then P.dirty = true else Queue() end end)
	end
	if not self.hookedFlyouts and hooksecurefunc then
		self.hookedFlyouts = true
		for _, fn in ipairs({ "RecreateTotemFlyouts", "AddMissingFlyoutButtons" }) do
			if type(SP[fn]) == "function" then
				hooksecurefunc(SP, fn, function() if P.wired and header:GetAttribute("sp-ready") then Queue() end end)
			end
		end
	end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("SPELLS_CHANGED")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		P:Wire()
		P:Hook()
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- the last moment before the lockdown: the column spots follow the bar
		if P.wired and header:GetAttribute("sp-ready") and not P.dirty and not header:GetAttribute("sp-isopen") then P:Place() end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if P.dirty or not P.wired then Queue() end
	elseif event == "SPELLS_CHANGED" then
		-- a totem learned or a respec: only matters once the picker is in use
		if P.wired and header:GetAttribute("sp-ready") then
			if InCombatLockdown() then P.dirty = true else Queue() end
		end
	else   -- PLAYER_ENTERING_WORLD
		Queue()
	end
end)
