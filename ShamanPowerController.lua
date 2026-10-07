-- ShamanPowerController.lua
-- Controller mode (3.0.8 alpha, A19, "just totems"), WoW: Forever only: the
-- controller bar. Its four totems as a d-pad cross (Up Earth, Right Fire, Down
-- Water, Left Air) with Drop All in the middle, or the five in a row (round or
-- square). Every slot is a secure "click" button whose clickbutton is the REAL
-- totem bar button, so a click on a slot presses that button: nothing is cast
-- from here, and whatever the real button does (its assignment, a flyout pick
-- made in this fight, Drop All's sequence) a slot does too.
--
-- What a slot shows comes from the totem bar's own data: the real button's icon
-- (mirrored when the bar sets it), the time left as a ring in the element's color
-- (GetElementTotemInfo: readable in fights on Forever, the core's record from your
-- own casts), the pulse sweep (GetActivePulsingTotem), the red warning and the
-- countdown at the Effects tab's Expiring Soon seconds, and the bound pad button's
-- picture (Blizzard's InputIconTextureSetUtility: Xbox / PlayStation / Switch swap
-- by themselves). The repaint is a subsystem of the central update loop that
-- sleeps whenever no totem is down (SP._whileTotemsDown), and is switched off while
-- the bar is hidden: no polling of its own.
--
-- Shown / hidden / moved / resized out of combat only (its slots are protected); a
-- change during a fight waits for the fight's end. Its own spot and Size, moved in
-- Unlock UI (its own box: "Move the Controller Bar").
--
-- The other two controller parts (the pad layer, the totem picker) build on the
-- names here: SP.Controller, :IsActive(), :OnChange(fn), :TargetButton(key),
-- :Glyph(padKey, size), :PaintGlyph(...), .frame, .slot[key], .pageArgs.

local SP = ShamanPower
if not SP then return end
-- General > Themes: the bar's looks are part of a theme (Layout and the pad pictures;
-- its colors are the element colors and WoW's own, which themes already hold). On both
-- clients, data only (nothing shows on Anniversary): a theme shared from WoW: Forever then
-- reads the same on Anniversary instead of turning Custom there.
if SP.ThemeSpotSettings then
	local LAYOUTS = { dpad = true, row = true, square = true }
	local function O() return SP.opt and SP.opt.controller end
	local function changed() if SP.Controller and SP.Controller.Refresh then SP.Controller:Refresh() end end
	SP:ThemeSpotSettings("ctrl.bar", {
		{ key = "layout", label = "Controller Layout",
			get = function() local o = O(); local v = o and o.layout; return LAYOUTS[v] and v or "dpad" end,
			set = function(v) local o = O(); if o and LAYOUTS[v] then o.layout = v; changed() end end },
		{ key = "glyphs", label = "Controller Pad Button Pictures",
			get = function() local o = O(); return not (o and o.glyphs == false) end,
			set = function(v) local o = O(); if o and type(v) == "boolean" then o.glyphs = v; changed() end end },
	})
end

if not (SPCompat and SPCompat.FOREVER) then return end   -- Anniversary has no Gamepad UI: nothing new there

local C = SP.Controller or {}
SP.Controller = C
C.slot = C.slot or {}
C.KEYS = { "earth", "fire", "water", "air", "dropall" }
C.ELEMENT = { earth = 1, fire = 2, water = 3, air = 4 }
C.LABEL = { earth = "Earth Totem", fire = "Fire Totem", water = "Water Totem", air = "Air Totem", dropall = "Drop All" }
-- the recommended pad buttons (the pad layer owns opt.controller.binds; these are the defaults)
C.DEFAULT_BINDS = { layer = "PADLSHOULDER", earth = "PADDUP", fire = "PADDRIGHT", water = "PADDDOWN", air = "PADDLEFT",
	dropall = "PAD1", picker = "PADRSHOULDER" }

local isSecret = issecretvalue or function() return false end
local TEX = "Interface\\AddOns\\ShamanPower\\Media\\Textures\\"
local MASK_CIRCLE = TEX .. "Mask_Circle"
local RING = TEX .. "Ring_Circle_5"   -- 5 px of 64: about 3 px round a 40-unit slot
local WHITE = "Interface\\Buttons\\WHITE8X8"
local REAL = { earth = "ShamanPowerTotemBtn1", fire = "ShamanPowerTotemBtn2", water = "ShamanPowerTotemBtn3",
	air = "ShamanPowerTotemBtn4", dropall = "ShamanPowerAutoDropAll" }
local SLOT_NAME = { earth = "ShamanPowerControllerEarth", fire = "ShamanPowerControllerFire",
	water = "ShamanPowerControllerWater", air = "ShamanPowerControllerAir", dropall = "ShamanPowerControllerDropAll" }

-- layout, in UI units before Size: a 40-unit slot, 46 between slot centers
local SLOT, STEP, ARC_N, ARC_W = 40, 46, 36, 3
local SQUARE_BAR_H = 4
local POS = {
	dpad = { earth = { 0, 1 }, fire = { 1, 0 }, water = { 0, -1 }, air = { -1, 0 }, dropall = { 0, 0 } },
	row  = { earth = { -2, 0 }, fire = { -1, 0 }, water = { 0, 0 }, air = { 1, 0 }, dropall = { 2, 0 } },
}
POS.square = POS.row
C.DEFAULT_POSITION = { anchor = "CENTER", x = -420, y = -280 }

local function O() return SP.opt and SP.opt.controller end
local isShaman = select(2, UnitClass("player")) == "SHAMAN"

-- ---------------------------------------------------------------------------
-- WoW's own colors (each client's RED_FONT_COLOR / NORMAL_FONT_COLOR), read once
-- ---------------------------------------------------------------------------
local RED, GOLD = { 1, 0.125, 0.125 }, { 1, 0.82, 0 }
do
	for _, pair in ipairs({ { RED_FONT_COLOR, RED }, { NORMAL_FONT_COLOR, GOLD } }) do
		local c, into = pair[1], pair[2]
		if c and c.GetRGB then
			local ok, r, g, b = pcall(c.GetRGB, c)
			if ok and type(r) == "number" then into[1], into[2], into[3] = r, g, b end
		end
	end
end
-- the element colors (Appearance > Element Colors, which the themes write), cached as numbers
local ELEM = { { 0.6, 0.4, 0.2 }, { 1, 0.4, 0.1 }, { 0.2, 0.6, 1 }, { 0.8, 0.8, 1 } }
local function ReadElementColors()
	for e = 1, 4 do
		local ok, r, g, b = pcall(SP.ElementPaletteColor, SP, e)
		if ok and type(r) == "number" then ELEM[e][1], ELEM[e][2], ELEM[e][3] = r, g, b
		else
			local c = SP.ElementColors and SP.ElementColors[e]
			if c then ELEM[e][1], ELEM[e][2], ELEM[e][3] = c.r, c.g, c.b end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Pad button pictures
-- ---------------------------------------------------------------------------
-- short words for a pad button where the game has no picture for it (never on
-- Forever with a pad: only when the atlas is missing)
local GLYPH_WORD = { PAD1 = "A", PAD2 = "B", PAD3 = "X", PAD4 = "Y", PADDUP = "Up", PADDDOWN = "Dn", PADDLEFT = "Lt",
	PADDRIGHT = "Rt", PADLSHOULDER = "LB", PADRSHOULDER = "RB", PADLTRIGGER = "LT", PADRTRIGGER = "RT",
	PADLSTICK = "L3", PADRSTICK = "R3", PADBACK = "Bk", PADFORWARD = "St" }

-- Glyph(padKey, size) -> atlas, width, height, isAtlas, word
-- atlas: Blizzard's picture for that pad button on the pad in use (nil when the
-- game has none); word: a short fallback label ("A", "LB", "Up"...).
function C:Glyph(padKey, size)
	size = size or 16
	if type(padKey) ~= "string" or padKey == "" then return nil, size, size, false, nil end
	local key = padKey:match("([^%-]+)$") or padKey   -- a modifier pair: the button itself
	local atlas
	local U = rawget(_G, "InputIconTextureSetUtility")
	if U and U.GetNormalActiveInputIconButtonTexture then
		local ok, a = pcall(U.GetNormalActiveInputIconButtonTexture, key)
		if ok and type(a) == "string" and a ~= "" then atlas = a end
	end
	if atlas and C_Texture and C_Texture.GetAtlasInfo then
		local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
		if not (ok and info) then atlas = nil end
	end
	if atlas then return atlas, size, size, true, GLYPH_WORD[key] or key end
	return nil, size, size, false, GLYPH_WORD[key] or key
end

-- Paints a pad button's picture on `tex` (and its fallback word on `fs`, shown only
-- when there is no picture; `bg` is the fallback's round plate). Any of them may be nil.
function C:PaintGlyph(tex, fs, padKey, size, bg)
	local atlas, w, h, isAtlas, word = self:Glyph(padKey, size)
	if tex then
		if isAtlas then
			tex:SetAtlas(atlas)
			tex:SetSize(w, h)
			tex:Show()
		else
			tex:Hide()
		end
	end
	local useWord = not isAtlas and word ~= nil
	if fs then
		if useWord then fs:SetText(word); fs:Show() else fs:Hide() end
	end
	if bg then bg:SetShown(useWord) end
	return isAtlas
end

local glyphFns = {}
-- fn() runs when the pad type changes (Xbox / PlayStation / Switch pictures)
function C:OnGlyphsChanged(fn) if type(fn) == "function" then glyphFns[#glyphFns + 1] = fn end end

-- ---------------------------------------------------------------------------
-- The real buttons
-- ---------------------------------------------------------------------------
-- TargetButton(key) -> button, mouseButton, name: the totem bar button a pad key
-- should press for "earth" | "fire" | "water" | "air" | "dropall", and the mouse
-- button that is its main action (Swap Left and Right Click: the same mapping
-- Keybind Mode uses, ShamanPower:KeyMouseButton).
function C:TargetButton(key)
	local name = REAL[key]
	if not name then return nil end
	local e = C.ELEMENT[key]
	local btn = (e and SP.totemButtons and SP.totemButtons[e]) or _G[name]
	if not btn then return nil end
	name = btn:GetName() or name
	return btn, SP:KeyMouseButton(name), name
end

-- ---------------------------------------------------------------------------
-- On / off
-- ---------------------------------------------------------------------------
local applied = false   -- what is on screen, and what OnChange last said
local pending = false   -- a change waiting for the fight to end
local unlockDemo = false
local changeFns = {}

local function GamepadUI()
	local S = rawget(_G, "C_InputInterfaceStyle")
	if not (S and S.GetCurrentStyle and Enum and Enum.InputDeviceInterfaceType) then return false end
	local ok, style = pcall(S.GetCurrentStyle)
	return ok and style ~= nil and not isSecret(style) and style == Enum.InputDeviceInterfaceType.Gamepad or false
end
C.GamepadUI = GamepadUI

-- the look the settings ask for right now (it shows once out of combat)
function C:WantsActive()
	local o = O()
	if not (o and o.enabled and isShaman) or SP:IsOff() then return false end
	if o.look == "always" then return true end
	return GamepadUI()
end

-- true while the controller bar is on (out of combat this follows the settings at
-- once; a change during a fight lands when it ends)
function C:IsActive() return applied end

-- fn(active) runs when the controller look turns on or off, always out of combat
function C:OnChange(fn) if type(fn) == "function" then changeFns[#changeFns + 1] = fn end end

-- the totem bar hides while the controller bar shows (Hide My Totem Bar While This Shows, on to start);
-- read by the totem bar's own hide rules (ShamanPower.lua UpdateTotemBarVisibility)
function SP:ControllerHidesTotemBar()
	if not C:IsActive() then return false end
	local o = self.opt and self.opt.controller
	return not (o and o.hideTotemBar == false)
end
C:OnChange(function() if SP.UpdateTotemBarVisibility then SP:UpdateTotemBarVisibility(true) end end)

-- ---------------------------------------------------------------------------
-- The bar
-- ---------------------------------------------------------------------------
local bar, header

local function ArcPoint(i, r)
	local a = math.rad(90 - (i - 1) * 360 / ARC_N)
	return r * math.cos(a), r * math.sin(a)
end

local function MirrorIcon(s, tex)
	if tex == nil or isSecret(tex) then return end
	if s.iconTex == tex then return end
	s.iconTex = tex
	s.icon:SetTexture(tex)
end
local function MirrorDesat(s, on)
	if on == nil or isSecret(on) then return end
	on = on and true or false
	if s.iconDesat == on then return end
	s.iconDesat = on
	s.icon:SetDesaturated(on)
end

local hookedIcon = setmetatable({}, { __mode = "k" })
local function RealIcon(key)
	local btn = C:TargetButton(key)
	if not btn then return nil end
	return btn.icon or (key == "dropall" and _G["ShamanPowerAutoDropAllIcon"]) or _G[(btn:GetName() or "") .. "Icon"]
end
-- the slot shows what its real button shows: copy the icon now, and again whenever the
-- totem bar sets it (a hook on that one texture: runs only when it changes)
local function WatchIcon(s)
	local icon = RealIcon(s.key)
	if not icon then
		if s.element then
			local idx = SP:AssignedIndex(s.element)
			MirrorIcon(s, (idx and idx > 0 and SP.GetTotemIcon and SP:GetTotemIcon(s.element, idx)) or (SP.ElementIcons and SP.ElementIcons[s.element]))
		end
		return
	end
	if not hookedIcon[icon] then
		hookedIcon[icon] = s.key
		hooksecurefunc(icon, "SetTexture", function(_, tex)
			local slot = C.slot[hookedIcon[icon]]
			if slot then MirrorIcon(slot, tex) end
		end)
		hooksecurefunc(icon, "SetDesaturated", function(_, on)
			local slot = C.slot[hookedIcon[icon]]
			if slot then MirrorDesat(slot, on) end
		end)
	end
	local ok, tex = pcall(icon.GetTexture, icon)
	if ok then MirrorIcon(s, tex) end
	local okD, desat = pcall(icon.IsDesaturated, icon)
	if okD then MirrorDesat(s, desat) end
end

local function SlotTooltip(s)
	if not GameTooltip then return end
	GameTooltip:SetOwner(s, "ANCHOR_TOP")
	GameTooltip:SetText(C.LABEL[s.key] or s.key, 1, 1, 1)
	if s.element then
		local have, name = SP:GetElementTotemInfo(s.element)
		if have and type(name) == "string" and not isSecret(name) and name ~= "" then
			GameTooltip:AddLine(name, ELEM[s.element][1], ELEM[s.element][2], ELEM[s.element][3])
		end
	end
	GameTooltip:AddLine("Click: the same as this button on your totem bar.", 0.8, 0.8, 0.8, true)
	GameTooltip:Show()
end

local function MakeSlot(key)
	local s = CreateFrame("Button", SLOT_NAME[key], bar, "SecureActionButtonTemplate")
	s.key, s.element = key, C.ELEMENT[key]
	s:SetSize(SLOT, SLOT)
	s:RegisterForClicks("AnyUp")
	s:SetAttribute("type", "click")
	s:SetAttribute("useOnKeyDown", false)   -- acts on the release (see the wrap below)

	-- the round plate, the icon (round: masked to a circle), a hover light
	s.plate = s:CreateTexture(nil, "BACKGROUND")
	s.plate:SetPoint("TOPLEFT", -2, 2)
	s.plate:SetPoint("BOTTOMRIGHT", 2, -2)
	s.icon = s:CreateTexture(nil, "ARTWORK")
	s.icon:SetPoint("TOPLEFT", 4, -4)
	s.icon:SetPoint("BOTTOMRIGHT", -4, 4)
	s.iconMask = s:CreateMaskTexture()
	s.iconMask:SetAllPoints(s.icon)
	s.iconMask:SetTexture(MASK_CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	s.hl = s:CreateTexture(nil, "HIGHLIGHT")
	s.hl:SetAllPoints(s.icon)
	s.hl:SetColorTexture(1, 1, 1, 0.15)
	s.hlMask = s:CreateMaskTexture()
	s.hlMask:SetAllPoints(s.icon)
	s.hlMask:SetTexture(MASK_CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	-- square layout: a 1 px dark edge round the icon and the time left as a bar under it
	s.edge = {}
	for i = 1, 4 do s.edge[i] = s:CreateTexture(nil, "BORDER"); s.edge[i]:SetColorTexture(0, 0, 0, 0.9) end
	s.edge[1]:SetPoint("TOPLEFT", -1, 1); s.edge[1]:SetPoint("TOPRIGHT", 1, 1); s.edge[1]:SetHeight(1)
	s.edge[2]:SetPoint("BOTTOMLEFT", -1, -1); s.edge[2]:SetPoint("BOTTOMRIGHT", 1, -1); s.edge[2]:SetHeight(1)
	s.edge[3]:SetPoint("TOPLEFT", -1, 1); s.edge[3]:SetPoint("BOTTOMLEFT", -1, -1); s.edge[3]:SetWidth(1)
	s.edge[4]:SetPoint("TOPRIGHT", 1, 1); s.edge[4]:SetPoint("BOTTOMRIGHT", 1, -1); s.edge[4]:SetWidth(1)
	s.barBg = s:CreateTexture(nil, "BORDER")
	s.barBg:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -2)
	s.barBg:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -2)
	s.barBg:SetHeight(SQUARE_BAR_H)
	s.barBg:SetColorTexture(0, 0, 0, 0.7)
	s.bar = s:CreateTexture(nil, "ARTWORK")
	s.bar:SetPoint("TOPLEFT", s.barBg, "TOPLEFT", 0, 0)
	s.bar:SetHeight(SQUARE_BAR_H)
	s.bar:SetTexture(WHITE)

	-- the pulse: the engine sweeps it round (one restart per pulse)
	s.pulse = CreateFrame("Cooldown", nil, s, "CooldownFrameTemplate")
	s.pulse:SetAllPoints(s.icon)
	s.pulse:SetDrawEdge(false)
	if s.pulse.SetDrawBling then s.pulse:SetDrawBling(false) end
	s.pulse:SetHideCountdownNumbers(true)
	s.pulse:SetReverse(true)
	s.pulse:SetSwipeColor(1, 1, 1, 0.32)
	s.pulse:Hide()

	-- the ring: a dim track, the time-left arc (ARC_N short lines, clockwise from the
	-- top) and a red glow while it is running out
	s.ringFrame = CreateFrame("Frame", nil, s)
	s.ringFrame:SetAllPoints(s)
	s.ringFrame:SetFrameLevel(s.pulse:GetFrameLevel() + 1)
	s.track = s.ringFrame:CreateTexture(nil, "ARTWORK")
	s.track:SetAllPoints(s)
	s.track:SetTexture(RING)
	s.glow = s.ringFrame:CreateTexture(nil, "BACKGROUND")
	s.glow:SetPoint("TOPLEFT", -3, 3)
	s.glow:SetPoint("BOTTOMRIGHT", 3, -3)
	s.glow:SetTexture(TEX .. "Ring_Circle_8")
	s.glow:SetBlendMode("ADD")
	s.glow:Hide()
	s.arc = {}
	local r = SLOT / 2 - ARC_W / 2
	for i = 1, ARC_N do
		local l = s.ringFrame:CreateLine(nil, "OVERLAY")
		local x1, y1 = ArcPoint(i, r)
		local x2, y2 = ArcPoint(i + 1, r)
		l:SetStartPoint("CENTER", s, x1, y1)
		l:SetEndPoint("CENTER", s, x2, y2)
		l:SetThickness(ARC_W)
		l:SetColorTexture(1, 1, 1, 1)
		l:Hide()
		s.arc[i] = l
	end
	s.lit = 0

	-- the time left, and the pad button's picture in the corner
	s.top = CreateFrame("Frame", nil, s)
	s.top:SetAllPoints(s)
	s.top:SetFrameLevel(s.ringFrame:GetFrameLevel() + 1)
	s.time = s.top:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(s.time, "timers", 13, "OUTLINE")
	s.time:SetPoint("CENTER", s, "CENTER", 0, 0)
	s.time:Hide()
	s.glyph = s.top:CreateTexture(nil, "OVERLAY")
	s.glyph:SetPoint("CENTER", s, "BOTTOMRIGHT", -5, 5)
	s.glyphBg = s.top:CreateTexture(nil, "ARTWORK")
	s.glyphBg:SetPoint("CENTER", s.glyph, "CENTER")
	s.glyphBg:SetSize(17, 17)
	s.glyphBg:SetTexture(MASK_CIRCLE)
	s.glyphBg:SetVertexColor(0.07, 0.08, 0.10, 0.95)
	s.glyphText = s.top:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(s.glyphText, "timers", 8, "OUTLINE")
	s.glyphText:SetPoint("CENTER", s.glyph, "CENTER", 0, 0)
	s.glyphText:SetTextColor(1, 1, 1)

	s:SetScript("OnEnter", SlotTooltip)
	s:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	C.slot[key] = s
	return s
end

-- A click on a slot presses the real button through the secure "click" action, which
-- hands it a release (Click(button), never a press). With "Cast action keybinds on key
-- down" on (ActionButtonUseKeyDown, WoW's default) a button only acts on a press, so the
-- release would do nothing. A secure wrap round the slot's click tells the real button
-- to act on that one release (its useOnKeyDown), and puts it back right after: the real
-- button's own keys and clicks are never touched. Snippets run in fights; where they do
-- not work on this client (SPCompat.SecureSnippetsWork), a slot click works with that
-- setting off only.
local PRE = [[
	local t = self:GetFrameRef("spTarget")
	if t then
		self:SetAttribute("sp-prevkd", t:GetAttribute("useOnKeyDown"))
		t:SetAttribute("useOnKeyDown", false)
		return nil, "restore"
	end
]]
local POST = [[
	local t = self:GetFrameRef("spTarget")
	if t and message == "restore" then t:SetAttribute("useOnKeyDown", self:GetAttribute("sp-prevkd")) end
]]
local function WireSlot(s)
	local real = C:TargetButton(s.key)
	s:SetAttribute("clickbutton", real)
	if real and SecureHandlerSetFrameRef then SecureHandlerSetFrameRef(s, "spTarget", real) end
	if not s.spWrapped and header and SecureHandlerWrapScript and SPCompat.SecureSnippetsWork and SPCompat.SecureSnippetsWork() then
		local ok = pcall(SecureHandlerWrapScript, s, "OnClick", header, PRE, POST)
		s.spWrapped = ok and true or nil
	end
end

local function Build()
	if bar then return true end
	if InCombatLockdown() then return false end
	bar = CreateFrame("Frame", "ShamanPowerControllerBar", UIParent)
	bar:SetFrameStrata("MEDIUM")
	bar:SetClampedToScreen(true)
	bar:SetSize(SLOT * 3, SLOT * 3)
	bar:Hide()
	header = CreateFrame("Frame", "ShamanPowerControllerHeader", UIParent, "SecureHandlerBaseTemplate")
	C.frame, C.header = bar, header
	for _, key in ipairs(C.KEYS) do MakeSlot(key) end
	return true
end

-- ---------------------------------------------------------------------------
-- Paint: the parts that only change with a setting, the theme or the pad
-- ---------------------------------------------------------------------------
local function LayoutKey()
	local o = O()
	local l = o and o.layout
	if l == "row" or l == "square" then return l end
	return "dpad"
end

local function PaintGlyphs()
	local o = O()
	local binds = o and o.binds
	local on = not (o and o.glyphs == false)
	for _, key in ipairs(C.KEYS) do
		local s = C.slot[key]
		if s then
			if on and binds and binds[key] then
				C:PaintGlyph(s.glyph, s.glyphText, binds[key], 18, s.glyphBg)
			else
				s.glyph:Hide(); s.glyphText:Hide(); s.glyphBg:Hide()
			end
		end
	end
end

local function SlotColor(s)
	if s.element then return ELEM[s.element] end
	return GOLD   -- Drop All: WoW's gold
end

local function PaintStatic()
	ReadElementColors()
	local square = LayoutKey() == "square"
	for _, key in ipairs(C.KEYS) do
		local s = C.slot[key]
		if s then
			local c = SlotColor(s)
			s.square = square
			SP:SetSPFont(s.time, "timers", 13, "OUTLINE")
			SP:SetSPFont(s.glyphText, "timers", 8, "OUTLINE")
			if square then
				s.plate:Hide()
				if s.masked then
					s.icon:RemoveMaskTexture(s.iconMask)
					s.hl:RemoveMaskTexture(s.hlMask)
					s.masked = nil
				end
				s.icon:ClearAllPoints(); s.icon:SetAllPoints(s)
				s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				for i = 1, 4 do s.edge[i]:Show() end
				s.track:Hide(); s.glow:Hide()
				for i = 1, ARC_N do s.arc[i]:Hide() end
				s.lit = 0
				s.barBg:Show()
				s.pulse:SetSwipeTexture(WHITE)
				s.glyph:ClearAllPoints(); s.glyph:SetPoint("CENTER", s, "BOTTOMRIGHT", -3, 3)
			else
				s.plate:Show()
				s.plate:SetTexture(MASK_CIRCLE)
				s.plate:SetVertexColor(0.04, 0.05, 0.06, 0.85)
				s.icon:ClearAllPoints()
				s.icon:SetPoint("TOPLEFT", 4, -4); s.icon:SetPoint("BOTTOMRIGHT", -4, 4)
				s.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
				if not s.masked then
					s.icon:AddMaskTexture(s.iconMask)
					s.hl:AddMaskTexture(s.hlMask)
					s.masked = true
				end
				for i = 1, 4 do s.edge[i]:Hide() end
				s.barBg:Hide(); s.bar:Hide()
				s.track:Show()
				s.pulse:SetSwipeTexture(MASK_CIRCLE)
				s.glyph:ClearAllPoints(); s.glyph:SetPoint("CENTER", s, "BOTTOMRIGHT", -5, 5)
			end
			-- Drop All: a whole ring (or bar) in gold; a totem: its element, dim until one is down
			if s.element then
				s.track:SetVertexColor(c[1], c[2], c[3], 0.35)
				s.bar:SetVertexColor(c[1], c[2], c[3], 1)
				s.barW = nil
			else
				s.track:SetVertexColor(c[1], c[2], c[3], 1)
				if square then
					s.bar:SetVertexColor(c[1], c[2], c[3], 1)
					s.bar:SetWidth(SLOT); s.bar:Show()
				end
			end
			for i = 1, ARC_N do s.arc[i]:SetColorTexture(c[1], c[2], c[3], 1) end
			s.warn = nil   -- the next pass paints the time and the warning again
			s.shownSec = nil
		end
	end
	PaintGlyphs()
end

local function Place()
	local o = O()
	local lk = LayoutKey()
	local pos = POS[lk]
	local cols, rows = 3, 3
	if lk ~= "dpad" then cols, rows = 5, 1 end
	local extraH = (lk == "square") and (SQUARE_BAR_H + 2) or 0
	bar:SetSize((cols - 1) * STEP + SLOT + 8, (rows - 1) * STEP + SLOT + 8 + extraH)
	for _, key in ipairs(C.KEYS) do
		local s = C.slot[key]
		local p = pos[key]
		s:ClearAllPoints()
		s:SetPoint("CENTER", bar, "CENTER", p[1] * STEP, p[2] * STEP + extraH / 2)
	end
	local scale = tonumber(o and o.scale) or 1.35
	if scale < 0.5 then scale = 0.5 elseif scale > 2.5 then scale = 2.5 end
	bar:SetScale(scale)
	SP:ApplyPositionRecord(bar, (o and o.position) or C.DEFAULT_POSITION)
end

-- ---------------------------------------------------------------------------
-- The pass (central update loop, 10 a second while a totem is down, asleep otherwise)
-- ---------------------------------------------------------------------------
local pulseData, pulseStart, pulseGen, pulseAt = {}, {}, -1, 0

local function Rumble()
	local G = rawget(_G, "C_GamePad")
	if not (G and G.SetVibration) then return end
	pcall(G.SetVibration, "Low", 0.6)
	pcall(G.SetVibration, "High", 0.6)
	if G.StopVibration and C_Timer then C_Timer.After(0.35, function() pcall(G.StopVibration) end) end
end

local function SetLit(s, k)
	local lit = s.lit
	if k == lit then return end
	if k > lit then for i = lit + 1, k do s.arc[i]:Show() end
	else for i = k + 1, lit do s.arc[i]:Hide() end end
	s.lit = k
end

local function ClearSlot(s)
	SetLit(s, 0)
	if s.timeShown then s.time:Hide(); s.timeShown = nil end
	if s.warn then
		s.warn = nil
		s.glow:Hide()
		local c = SlotColor(s)
		for i = 1, ARC_N do s.arc[i]:SetColorTexture(c[1], c[2], c[3], 1) end
	end
	if s.square and s.bar:IsShown() then s.bar:Hide() end
	s.shownSec = nil
	if s.pulseCycle then s.pulse:Clear(); s.pulse:Hide(); s.pulseCycle = nil end
end

local function PassSlot(s, now, secs, o)
	local e = s.element
	local have, _, start, dur = SP:GetElementTotemInfo(e)
	if isSecret(have) or not have or type(start) ~= "number" or type(dur) ~= "number" or isSecret(start) or isSecret(dur)
		or dur <= 0 then
		ClearSlot(s)
		return
	end
	local left = start + dur - now
	if left <= 0 then ClearSlot(s) return end
	local frac = left / dur
	if frac > 1 then frac = 1 end
	-- running out: the Effects tab's Expiring Soon seconds (a totem must last longer than that)
	local warn = dur > secs + 1 and left <= secs
	if warn ~= (s.warn or false) then
		s.warn = warn or nil
		local c = warn and RED or SlotColor(s)
		for i = 1, ARC_N do s.arc[i]:SetColorTexture(c[1], c[2], c[3], 1) end
		if s.square then s.bar:SetVertexColor(c[1], c[2], c[3], 1) end
		if warn then
			s.glow:SetVertexColor(RED[1], RED[2], RED[3], 0.3)
			s.glow:SetShown(not s.square)
			s.time:SetTextColor(RED[1], RED[2], RED[3])
			if o.rumble and s.rumbledFor ~= start then s.rumbledFor = start; Rumble() end
		else
			s.glow:Hide()
			s.time:SetTextColor(1, 1, 1)
		end
		s.shownSec = nil
	end
	if s.square then
		local w = SLOT * frac
		if w < 1 then w = 1 end
		if not s.barW or math.abs(s.barW - w) > 0.25 then s.barW = w; s.bar:SetWidth(w) end
		if not s.bar:IsShown() then s.bar:Show() end
	else
		SetLit(s, math.ceil(frac * ARC_N))
	end
	local sec = math.ceil(left)
	if sec ~= s.shownSec then
		s.shownSec = sec
		if warn or sec < 60 then s.time:SetText(sec)
		else s.time:SetFormattedText("%d:%02d", math.floor(sec / 60), sec % 60) end
		if not s.timeShown then s.time:Show(); s.timeShown = true end
	end
	-- the pulse sweep: restarted once per pulse, the engine draws it in between
	local data, pstart = pulseData[e], pulseStart[e]
	local interval = data and data.interval
	if type(interval) == "number" and interval > 0 and type(pstart) == "number" and not isSecret(pstart) then
		local cycle = pstart + math.floor((now - pstart) / interval) * interval
		if cycle ~= s.pulseCycle then
			s.pulseCycle = cycle
			s.pulse:Show()
			s.pulse:SetCooldown(cycle, interval)
		end
	elseif s.pulseCycle then
		s.pulse:Clear(); s.pulse:Hide(); s.pulseCycle = nil
	end
end

local function Pass()
	if not (bar and bar:IsShown()) then return end
	local o = O()
	if not o then return end
	local now = GetTime()
	-- which totem pulses (and since when) only changes with the totems: as the pulse pass does
	local gen = SP._totemInfoGen
	if gen ~= pulseGen or (now - pulseAt) > 0.5 then
		pulseGen, pulseAt = gen, now
		for e = 1, 3 do
			local ok, d, st = pcall(SP.GetActivePulsingTotem, SP, e)
			if ok then pulseData[e], pulseStart[e] = d or nil, st else pulseData[e], pulseStart[e] = nil, nil end
		end
	end
	local secs = tonumber(SP.opt.totemCueExpiringSecs) or 5
	for e = 1, 4 do
		local s = C.slot[C.KEYS[e]]
		if s then PassSlot(s, now, secs, o) end
	end
end
C.Pass = Pass

local passState = {}
local function EnsureSubsystem()
	if SP.updateSystem and not SP.updateSystem.subsystems["controllerBar"] then
		SP:RegisterUpdateSubsystem("controllerBar", 0.1, function()
			if SP._whileTotemsDown then SP._whileTotemsDown(passState, Pass) else Pass() end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Apply: show / hide / layout, out of combat only
-- ---------------------------------------------------------------------------
local regen = CreateFrame("Frame")
regen:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	if pending then C:Refresh() end
end)

local function FireChange(active)
	for _, fn in ipairs(changeFns) do
		local ok, err = pcall(fn, active)
		if not ok and geterrorhandler then geterrorhandler()(err) end
	end
end

function C:Refresh()
	if InCombatLockdown() then
		pending = true
		regen:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	pending = false
	local want = self:WantsActive()
	local show = want or unlockDemo
	if show and Build() then
		for _, key in ipairs(C.KEYS) do
			local s = C.slot[key]
			WireSlot(s)
			WatchIcon(s)
		end
		PaintStatic()
		Place()
		bar:Show()
		EnsureSubsystem()
		SP:EnableUpdateSubsystem("controllerBar")
		SP:WakeUpdateSubsystem("controllerBar")
		Pass()
	elseif bar then
		bar:Hide()
		if SP.updateSystem and SP.updateSystem.subsystems["controllerBar"] then SP:DisableUpdateSubsystem("controllerBar") end
	end
	if want ~= applied then
		applied = want
		FireChange(want)
	end
end

-- a look-only change (colors, pictures): no protected work, so also in a fight
function C:Repaint()
	if not bar then return end
	ReadElementColors()
	if InCombatLockdown() then
		PaintGlyphs()
		for _, key in ipairs(C.KEYS) do local s = C.slot[key]; if s then s.warn = nil; s.shownSec = nil end end
		-- the ring colors are set again on the next pass (warn reset)
		for _, key in ipairs(C.KEYS) do
			local s = C.slot[key]
			if s then
				local c = SlotColor(s)
				for i = 1, ARC_N do s.arc[i]:SetColorTexture(c[1], c[2], c[3], 1) end
				s.track:SetVertexColor(c[1], c[2], c[3], s.element and 0.35 or 1)
			end
		end
		Pass()
		return
	end
	self:Refresh()
end

-- the totem bar made or rebuilt its buttons: point the slots at them again (out of combat)
function C:Rewire()
	if not bar or InCombatLockdown() then return end
	for _, key in ipairs(C.KEYS) do
		local s = C.slot[key]
		WireSlot(s)
		WatchIcon(s)
	end
end

function C:SetEnabled(on)
	local o = O()
	if not o then return end
	o.enabled = on and true or false
	self:Refresh()
end

-- Unlock UI: the bar on screen to be moved even when the controller look is off now
function SP:ControllerUnlockDemo(on)
	unlockDemo = on and true or false
	C:Refresh()
end

-- ---------------------------------------------------------------------------
-- Unlock UI: its own box ("Move the Controller Bar" unlocks only this one)
-- ---------------------------------------------------------------------------
if SP.RegisterPreview then
	SP:RegisterPreview("controller", { frame = function() return bar end, demo = "SP:ControllerUnlockDemo" })
end
if SP.UnlockModules then
	table.insert(SP.UnlockModules, { key = "controller", label = "Controller Bar",
		enabled = function() local o = O(); return o and o.enabled and isShaman and true or false end,
		frames = function()
			if not bar then Build() end
			return bar and { bar } or {}
		end,
		save = function(frame)
			local o = O()
			if o then o.position = SP:SavePositionRecord(frame) end
		end,
		reset = function()
			local o = O()
			if o then o.position = nil end
			if bar and not InCombatLockdown() then SP:ApplyPositionRecord(bar, C.DEFAULT_POSITION) end
		end })
end

-- ---------------------------------------------------------------------------
-- Settings: Bars > Controller (Window.lua lists it after Loadouts, with its switch)
-- ---------------------------------------------------------------------------
do
	local F = SP.options and SP.options.args and SP.options.args.fluffy and SP.options.args.fluffy.args
	if F then
		local function set(field)
			return function(_, v)
				local o = O()
				if not o then return end
				o[field] = v
				C:Refresh()
			end
		end
		local function get(field, default)
			return function()
				local o = O()
				local v = o and o[field]
				if v == nil then return default end
				return v
			end
		end
		local args = {
			controller_intro = { type = "description", width = "full",
				name = "Your four totems shaped like your controller, with Drop All in the middle. Clicking a slot presses the same button on your totem bar." },
			controller_look = { type = "select", width = 1.0, name = "Controller Look",
				desc = "Automatic: shows while Blizzard's controller mode (Gamepad UI) is on. Always: shows whenever the Controller switch is on. It shows, hides, moves and changes size out of a fight only.",
				values = { auto = "Automatic", always = "Always" }, sorting = { "auto", "always" },
				get = get("look", "auto"), set = set("look") },
			controller_layout = { type = "select", width = 1.0, name = "Layout",
				desc = "Controller Layout: a d-pad cross (Up Earth, Right Fire, Down Water, Left Air) with Drop All in the middle. Round Slots In A Row and Square: the four totems and Drop All side by side.",
				values = { dpad = "Controller Layout", row = "Round Slots In A Row", square = "Square" },
				sorting = { "dpad", "row", "square" },
				get = get("layout", "dpad"), set = set("layout") },
			controller_scale = { type = "range", width = 1.0, name = "Size", isPercent = true, min = 0.5, max = 2.5, step = 0.05,
				desc = "How big the controller bar is. Your keyboard totem bar keeps its own size.",
				get = get("scale", 1.35), set = set("scale") },
			controller_glyphs = { type = "toggle", width = 1.0, name = "Show The Pad Button's Picture",
				desc = "Shows the controller button for each slot in its corner, as Xbox, PlayStation or Switch pictures, whichever pad you use.",
				get = function() local o = O(); return not (o and o.glyphs == false) end, set = set("glyphs") },
			controller_hide_bar = { type = "toggle", width = "full", name = "Hide My Totem Bar While This Shows",
				desc = "While the controller bar shows, your normal totem bar hides: they are the same buttons. Your totem keys and the controller bar keep working while it is hidden. It hides and comes back out of a fight only.",
				get = function() local o = O(); return not (o and o.hideTotemBar == false) end,
				set = function(_, v) local o = O(); if not o then return end; o.hideTotemBar = v and true or false
					if SP.UpdateTotemBarVisibility then SP:UpdateTotemBarVisibility(true) end end },
			controller_rumble = { type = "toggle", width = "full", name = "Rumble When A Totem Is About To Expire",
				desc = "Your controller rumbles once when a totem has a few seconds left (the same seconds as Totem Bar > Effects > Expiring Soon).",
				get = get("rumble", false), set = set("rumble") },
			controller_move = { type = "execute", width = "full", name = "Move the Controller Bar",
				desc = "Unlocks only the controller bar: drag its box where you want it, then press Done. It can't be done in a fight. Turn on the Controller switch first.",
				disabled = function() local o = O(); return not (o and o.enabled) end,
				func = function() SP:UnlockModuleFrames("controller") end },
		}
		-- The Controller Buttons list is the pad layer's part (ShamanPower_Config ControllerButtons.lua,
		-- ns.CustomRows.controller_buttons): it draws itself in this row, under this band's heading
		args.controller_buttons = { type = "description", width = "full", name = " ",
			desc = "Controller Buttons: Hold For ShamanPower's Buttons, Earth Totem, Fire Totem, Water Totem, Air Totem,"
				.. " Drop All, Open Totem Picker. Use The Recommended Buttons, Reset." }
		F.controller_page = { type = "group", name = "Controller", order = 12.5, args = args }
		SP.OptionCustomRow = SP.OptionCustomRow or {}
		SP.OptionCustomRow[args.controller_buttons] = "controller_buttons"
		SP.OrderSettingsBands(F.controller_page, {
			{ keys = { "controller_intro", "controller_move" } },
			{ header = "controller_look_header", name = "Look", keys = { "controller_look", "controller_layout",
				"controller_scale", "controller_glyphs", "controller_hide_bar", "controller_rumble" } },
			{ header = "controller_buttons_header", name = "Controller Buttons", keys = { "controller_buttons" } },
		})
		C.pageArgs = args
	end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(ev.RegisterEvent, ev, "INPUT_DEVICE_INTERFACE_TRANSITION")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		isShaman = select(2, UnitClass("player")) == "SHAMAN"
		-- the pad type (Xbox / PlayStation / Switch) changed: new pictures
		local M = rawget(_G, "InputDeviceIconSetManager")
		if M and M.RegisterActiveInputDeviceIconSetUpdatedCallback then
			pcall(M.RegisterActiveInputDeviceIconSetUpdatedCallback, M, function()
				PaintGlyphs()
				for _, fn in ipairs(glyphFns) do pcall(fn) end
			end, C)
		end
	end
	C:Refresh()
end)
if SP.OnOnOff then SP:OnOnOff(function() C:Refresh() end) end
if hooksecurefunc then
	if SP.ApplyElementColors then hooksecurefunc(SP, "ApplyElementColors", function() C:Repaint() end) end
	if SP.OnProfileChanged then hooksecurefunc(SP, "OnProfileChanged", function() C:Refresh() end) end
	if SP.CreateTotemButtons then hooksecurefunc(SP, "CreateTotemButtons", function() C:Rewire() end) end
	if SP.SetupKeybindings then hooksecurefunc(SP, "SetupKeybindings", function() C:Rewire() end) end
	-- a totem placed / gone: the pass right away (the loop wakes on the same events)
	if SP.InvalidateTotemInfo then hooksecurefunc(SP, "InvalidateTotemInfo", function()
		if bar and bar:IsShown() and SP.updateSystem.subsystems["controllerBar"] then SP:WakeUpdateSubsystem("controllerBar") end
	end) end
end
