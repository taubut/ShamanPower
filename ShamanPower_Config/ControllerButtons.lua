-- ShamanPower_Config :: ControllerButtons
-- The Controller page's Controller Buttons list (A19 section 4, 2026-10-07; "just
-- totems" 2026-10-07): one line per button ShamanPower's pad layer uses (Hold For
-- ShamanPower's Buttons, the four totems, Drop All, Open Totem Picker), each with
-- the pad button's own picture (SP.Controller:Glyph: Blizzard's art, Xbox /
-- PlayStation / Switch). Pick a line (click it, or move with the d-pad and press
-- A), then press the controller button you want; "Press a controller button..."
-- shows in gold meanwhile, Esc stops. Right-click a line: no button. A gold line
-- says when the picked button also does something for Blizzard. Use The
-- Recommended Buttons / Reset under the list.
--
-- The buttons themselves live in the pad layer (ShamanPowerControllerPad.lua,
-- SP.ControllerPad): Get / Set / UseRecommended / ClearAll, saved in
-- SP.opt.controller.binds. WoW: Forever only (Anniversary has no controller mode).
--
-- Pad input: while the list is on screen (out of a fight, the game taking pad
-- input) the list's own frame takes the d-pad Up / Down, A and B
-- (EnableGamePadButton) and lets every other button through to the game; while a
-- line waits for a button it takes any pad button and the Escape key. A fight
-- starting stops all of that before the lockdown. Nothing runs while idle.
local _, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not (Core and SP) then return end
if not (SPCompat and SPCompat.FOREVER) then return end   -- Anniversary: nothing new

local floor, max, ceil = math.floor, math.max, math.ceil

local PAD_X      = 12     -- the settings rows' inner padding (plus a card's inset: Widgets.CARD_INSET)
local PAD_TOP    = 10
local PAD_BOTTOM = 12
local ROW_GAP    = 6      -- the settings rows' gap (Widgets.ROW_GAP)
local LINE_H     = 34     -- a line (the settings rows' height)
local GLYPH      = 22     -- a pad button's picture
local BOX        = 10     -- the tiny totem box before a totem's name
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0   -- gold text (ui-style-guide 2.3)
-- (the words that say what to do in the settings' blue, so a player sees them first)
local CAPTION_HOW = " |cff3FA9F5CLICK|r a line (or move with the |cff3FA9F5d-pad|r and press |cff3FA9F5A|r), then press the"
	.. " controller button you want. |cff3FA9F5RIGHT-CLICK|r a line to take its button off. |cff3FA9F5Esc|r stops."
local PRESS = "Press a controller button..."
local HINTS = { { "PADDUP", "Up" }, { "PADDDOWN", "Down" }, { "PAD1", "Change" }, { "PAD2", "Back" } }
local ELEMENT_OF = { earth = "earth", fire = "fire", water = "water", air = "air" }
local TIPS = {
	layer = "Hold this button and ShamanPower's buttons below work; let go and the pad is Blizzard's again. While the controller look is on, this one button is ShamanPower's.",
	earth = "drops your Earth totem.",
	fire = "drops your Fire totem.",
	water = "drops your Water totem.",
	air = "drops your Air totem.",
	dropall = "drops all your totems.",
	picker = "opens the totem picker: d-pad Left / Right picks the element, Up / Down scrolls, A picks, B closes.",
}

local List = { rows = {}, hints = {} }
ns.CustomRows.controller_buttons = List

local function Pad() return SP.ControllerPad end

local function PadInput()
	if not (C_GamePad and C_GamePad.IsEnabled) then return false end
	local ok, on = pcall(C_GamePad.IsEnabled)
	return ok and on and true or false
end

local function Relayout()
	local cfg = _G.ShamanPowerConfig
	if cfg and cfg.RefreshCurrent then cfg:RefreshCurrent() end
end

-- ---------------------------------------------------------------------------
-- A pad button's picture: SP.Controller:Glyph (Blizzard's art for this pad);
-- without it (or a button Blizzard has no picture for) a small key cap with its name
-- ---------------------------------------------------------------------------
local function GlyphSource(padKey, size)
	local C = SP.Controller
	local r
	if C and C.Glyph then
		local ok, v = pcall(C.Glyph, C, padKey, size)
		if ok then r = v end
	end
	local atlas, file, coords
	if type(r) == "string" then
		if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(r) then atlas = r else file = r end
	elseif type(r) == "number" then
		file = r
	elseif type(r) == "table" then
		if r.GetAtlas then   -- a texture
			atlas = r:GetAtlas()
			if not atlas and r.GetTexture then file = r:GetTexture() end
		else
			atlas, file, coords = r.atlas, r.file or r.texture, r.coords
		end
	end
	if not (atlas or file) then
		local U = InputIconTextureSetUtility
		if U and U.GetNormalActiveInputIconButtonTexture then
			local ok, a = pcall(U.GetNormalActiveInputIconButtonTexture, padKey)
			if ok and type(a) == "string" and a ~= "" then atlas = a end
		end
	end
	return atlas, file, coords
end

local function NewGlyph(parent)
	local g = CreateFrame("Frame", nil, parent)
	g.tex = g:CreateTexture(nil, "ARTWORK")
	g.tex:SetAllPoints(g)
	g.cap = CreateFrame("Frame", nil, g)
	g.cap:SetAllPoints(g)
	g.cap.bg = Core:SolidTex(g.cap, "windowBg", "BACKGROUND")
	Core:MakeBorder(g.cap, "border")
	g.cap.text = g.cap:CreateFontString(nil, "OVERLAY")
	g.cap.text:SetFontObject(Core.fonts.strip)
	g.cap.text:SetTextColor(Core:Color("text"))
	g.cap.text:SetPoint("CENTER", g.cap, "CENTER", 0, 0)
	return g
end

-- returns the picture's width
local function PaintGlyph(g, padKey, size)
	local atlas, file, coords = GlyphSource(padKey, size)
	g:SetHeight(size)
	if atlas or file then
		if atlas then g.tex:SetAtlas(atlas) else g.tex:SetTexture(file) end
		if coords then g.tex:SetTexCoord(unpack(coords)) else g.tex:SetTexCoord(0, 1, 0, 1) end
		g.tex:Show()
		g.cap:Hide()
		g:SetWidth(size)
	else
		g.tex:Hide()
		g.cap.text:SetText(Pad() and Pad():KeyName(padKey) or padKey)
		g.cap:Show()
		g:SetWidth(max(size, ceil(g.cap.text:GetStringWidth()) + 10))
	end
	g:Show()
	return g:GetWidth()
end

-- ---------------------------------------------------------------------------
-- State: the line the d-pad is on (sel), the line waiting for a button (capture),
-- the gold line about the last pick (warn)
-- ---------------------------------------------------------------------------
local Paint   -- forward

local function SetInput()
	local f = List.frame
	if not f then return end
	local on = f:IsVisible() and not InCombatLockdown()
	if f.EnableGamePadButton then f:EnableGamePadButton(on and PadInput()) end
	f:EnableKeyboard(on and List.capture ~= nil)
end

local function StopCapture()
	if List.capture == nil then return end
	List.capture = nil
	SetInput()
	if List.frame and List.frame:IsVisible() then Paint() end
end

local function StartCapture(index)
	local P = Pad()
	if not P then return end
	if InCombatLockdown() then
		List.fightNote = true
		Relayout()
		return
	end
	List.sel = index
	List.capture = P.ORDER[index]
	SetInput()
	Paint()
end

-- The gold line: what the picked button also does for Blizzard.
local function WarningFor(key, padKey)
	local P = Pad()
	if not (P and padKey) then return nil end
	local name = P:KeyName(padKey)
	local use = P:BlizzardUse(padKey)
	if not use and not P:BlizzardControllerMode() then return nil end
	local layer = P:Get("layer")
	if key == "layer" then
		if use then
			return name .. " is also Blizzard's " .. use .. ": while the controller look is on, it only holds ShamanPower's buttons."
		end
		return name .. " is also one of Blizzard's controller buttons: while the controller look is on, it only holds ShamanPower's buttons."
	end
	local hold = layer and P:KeyName(layer) or "the first button"
	if use then
		return name .. " is also Blizzard's " .. use .. ": ShamanPower only takes it while you hold " .. hold .. "."
	end
	return name .. " is also one of Blizzard's controller buttons: ShamanPower only takes it while you hold " .. hold .. "."
end

local function Pick(key, padKey)
	local P = Pad()
	if not P then return end
	List.capture = nil
	if P:Set(key, padKey) then
		List.warn = WarningFor(key, padKey)
	end
	SetInput()
	Relayout()   -- the gold line can change the list's height
end

-- ---------------------------------------------------------------------------
-- Pad and keys on the list
-- ---------------------------------------------------------------------------
local function Consume(f, taken)
	if f.SetPropagateKeyboardInput and not InCombatLockdown() then f:SetPropagateKeyboardInput(not taken) end
end

local function OnPadButton(f, button)
	local P = Pad()
	if not P or InCombatLockdown() then return end
	if List.capture then
		Consume(f, true)
		if not P:IsPadKey(button) then return end
		-- the hold half of a pair (hold LB, press the d-pad): wait for the second button
		if List.capture ~= "layer" and button == P:Get("layer") then return end
		Pick(List.capture, button)
		return
	end
	local n = #P.ORDER
	if button == "PADDUP" or button == "PADDDOWN" then
		Consume(f, true)
		local step = (button == "PADDUP") and -1 or 1
		List.sel = List.sel and ((List.sel - 1 + step) % n + 1) or 1
		Paint()
	elseif button == "PAD1" then
		Consume(f, true)
		if List.sel then StartCapture(List.sel) else List.sel = 1; Paint() end
	elseif button == "PAD2" and List.sel then
		Consume(f, true)
		List.sel = nil
		Paint()
	else
		Consume(f, false)   -- everything else is the game's
	end
end

local function OnKey(f, key)
	if List.capture and key == "ESCAPE" then
		Consume(f, true)
		StopCapture()
		return
	end
	Consume(f, false)
end

-- ---------------------------------------------------------------------------
-- The lines
-- ---------------------------------------------------------------------------
local function NewLine(f, index)
	local row = CreateFrame("Button", nil, f)
	row.index = index
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints(row)
	row.bg:SetColorTexture(1, 1, 1, 0)
	Core:MakeBorder(row, "accent")
	Core:SetBorderColor(row, "accent", 0)
	row.label = row:CreateFontString(nil, "OVERLAY")
	row.label:SetFontObject(Core.fonts.row)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(true)
	if SP.CreateElementBox then row.box = SP:CreateElementBox(row, BOX) end
	row.g1, row.g2 = NewGlyph(row), NewGlyph(row)
	row.plus = row:CreateFontString(nil, "OVERLAY")
	row.plus:SetFontObject(Core.fonts.rowDim)
	row.plus:SetText("+")
	row.state = row:CreateFontString(nil, "OVERLAY")
	row.state:SetFontObject(Core.fonts.row)
	row.state:SetJustifyH("LEFT")
	row.state:SetWordWrap(true)
	row:SetScript("OnClick", function(self, button)
		local P = Pad()
		if not P then return end
		if InCombatLockdown() then List.fightNote = true; Relayout() return end
		local key = P.ORDER[self.index]
		if button == "RightButton" then
			StopCapture()
			List.sel = self.index
			P:Set(key, nil)
			List.warn = nil
			Relayout()
		elseif List.capture == key then
			StopCapture()
		else
			StartCapture(self.index)
		end
	end)
	row:SetScript("OnEnter", function(self) self.hover = true; Paint() end)
	row:SetScript("OnLeave", function(self) self.hover = false; Paint() end)
	return row
end

-- the right side of a line: its pictures, or "Press a controller button..."
local function PaintLine(row, key, glyphX)
	local P = Pad()
	local sel = (List.sel == row.index)
	local capturing = (List.capture == key)
	if capturing or sel then
		row.bg:SetColorTexture(Core:Color("accent", 0.22))
		Core:SetBorderColor(row, "accent", 1)
	elseif row.hover then
		row.bg:SetColorTexture(Core:Color("rowHover", Core.opacity))
		Core:SetBorderColor(row, "accent", 0)
	else
		row.bg:SetColorTexture(1, 1, 1, 0)
		Core:SetBorderColor(row, "accent", 0)
	end
	row.label:SetTextColor(Core:Color("text"))
	row.g1:Hide(); row.g2:Hide(); row.plus:Hide()
	row.state:ClearAllPoints()
	row.state:SetPoint("LEFT", row, "LEFT", glyphX, 0)
	row.state:SetPoint("RIGHT", row, "RIGHT", -PAD_X, 0)
	if capturing then
		row.state:SetText(PRESS)
		row.state:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
		row.state:Show()
		return
	end
	local padKey = P and P:Get(key)
	if not padKey then
		row.state:SetText("No button")
		row.state:SetTextColor(Core:Color("textMute"))
		row.state:Show()
		return
	end
	row.state:Hide()
	local x = glyphX
	local layer = P:Get("layer")
	if key ~= "layer" and layer and layer ~= padKey then
		row.g1:ClearAllPoints()
		row.g1:SetPoint("LEFT", row, "LEFT", x, 0)
		x = x + PaintGlyph(row.g1, layer, GLYPH) + 6
		row.plus:ClearAllPoints()
		row.plus:SetPoint("LEFT", row, "LEFT", x, 0)
		row.plus:Show()
		x = x + ceil(row.plus:GetStringWidth()) + 6
	end
	row.g2:ClearAllPoints()
	row.g2:SetPoint("LEFT", row, "LEFT", x, 0)
	PaintGlyph(row.g2, padKey, GLYPH)
end

function Paint()
	local f = List.frame
	local P = Pad()
	if not (f and P) then return end
	for i, key in ipairs(P.ORDER) do
		local row = List.rows[i]
		if row then PaintLine(row, key, f.glyphX or 200) end
	end
end

-- ---------------------------------------------------------------------------
-- The card (ns.CustomRows: drawn by Window.lua's page packer, released on every redraw)
-- ---------------------------------------------------------------------------
local function Build(body)
	local f = CreateFrame("Frame", nil, body)
	f.caption = f:CreateFontString(nil, "OVERLAY")
	f.caption:SetFontObject(Core.fonts.rowDim)
	f.caption:SetJustifyH("LEFT")
	f.caption:SetWordWrap(true)
	f.warn = f:CreateFontString(nil, "OVERLAY")
	f.warn:SetFontObject(Core.fonts.row)
	f.warn:SetJustifyH("LEFT")
	f.warn:SetWordWrap(true)
	f.warn:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
	f.fight = f:CreateFontString(nil, "OVERLAY")
	f.fight:SetFontObject(Core.fonts.row)
	f.fight:SetJustifyH("LEFT")
	f.fight:SetWordWrap(true)
	f.fight:SetTextColor(Core:Color("warn"))
	f.fight:SetText("Controller buttons can't change in a fight. They work as set; change them after the fight.")
	f.recommended = Core:MakeButton(f, "Use The Recommended Buttons", 120, false)
	f.recommended:SetScript("OnClick", function()
		local P = Pad()
		if not P then return end
		if InCombatLockdown() then List.fightNote = true; Relayout() return end
		StopCapture()
		P:UseRecommended()
		List.warn = nil
		Relayout()
	end)
	Core:AttachTooltip(f.recommended, "Use The Recommended Buttons",
		"Hold LB for ShamanPower's buttons: the d-pad drops your Earth (Up), Fire (Right), Water (Down) and Air (Left) totems,"
		.. " A drops them all, and RB opens the totem picker.")
	f.reset = Core:MakeButton(f, "Reset", 80, false)
	f.reset:SetScript("OnClick", function()
		local P = Pad()
		if not P then return end
		if InCombatLockdown() then List.fightNote = true; Relayout() return end
		StopCapture()
		P:ClearAll()
		List.warn = nil
		Relayout()
	end)
	Core:AttachTooltip(f.reset, "Reset",
		"Takes every button off this list: ShamanPower then uses no controller button at all until you set one"
		.. " or press Use The Recommended Buttons.")
	-- d-pad Up / Down / A / B, as the game's own pictures (only while the game takes pad input)
	for i, h in ipairs(HINTS) do
		local hint = CreateFrame("Frame", nil, f)
		hint.g = NewGlyph(hint)
		hint.g:SetPoint("LEFT", hint, "LEFT", 0, 0)
		hint.text = hint:CreateFontString(nil, "OVERLAY")
		hint.text:SetFontObject(Core.fonts.rowDim)
		hint.text:SetText(h[2])
		hint.key = h[1]
		List.hints[i] = hint
	end
	f:SetScript("OnGamePadButtonDown", OnPadButton)
	f:SetScript("OnKeyDown", OnKey)
	f:SetScript("OnShow", SetInput)
	f:SetScript("OnHide", function(self)
		List.capture = nil
		if self.EnableGamePadButton then self:EnableGamePadButton(false) end
		self:EnableKeyboard(false)
	end)
	f:RegisterEvent("PLAYER_REGEN_DISABLED")   -- (before the lockdown: input off, the wait stopped)
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:SetScript("OnEvent", function(self, event)
		if not self:IsVisible() then return end
		if event == "PLAYER_REGEN_DISABLED" then
			List.capture = nil
			if self.EnableGamePadButton then self:EnableGamePadButton(false) end
			self:EnableKeyboard(false)
		else
			List.fightNote = nil
			SetInput()
		end
		Relayout()
	end)
	f.spNoCull = true
	List.frame = f
	-- the settings window closing forgets the picked line and the gold line
	local win = _G.ShamanPowerConfigUIFrame
	if win then win:HookScript("OnHide", function() List.sel, List.warn, List.capture, List.fightNote = nil, nil, nil, nil end) end
	return f
end

function List:Render(body, x, y, width)
	local P = Pad()
	if not P then return nil, 0 end
	local f = self.frame or Build(body)
	f:SetParent(body)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", body, "TOPLEFT", x or 0, -(y or 0))
	f:SetWidth(width)

	local padX = PAD_X + (ns.Widgets and tonumber(ns.Widgets.CARD_INSET) or 0)   -- in line with the rows' labels
	local inner = width - padX * 2
	f.caption:ClearAllPoints()
	f.caption:SetPoint("TOPLEFT", f, "TOPLEFT", padX, -PAD_TOP)
	f.caption:SetWidth(inner)
	local layer = P:Get("layer")
	local holdName = layer and P:KeyName(layer)
	f.caption:SetText((holdName and ("Hold " .. holdName .. " for ShamanPower's buttons; let go and the pad is Blizzard's again.")
		or "Set the button you hold for ShamanPower's buttons first (the first line).") .. CAPTION_HOW)
	local top = PAD_TOP + ceil(f.caption:GetStringHeight()) + 8

	-- the labels' column: the longest name (with the totem box), at least 40% of the line
	local labelW = 0
	for i, key in ipairs(P.ORDER) do
		local row = self.rows[i] or NewLine(f, i)
		self.rows[i] = row
		row.label:SetWidth(0)
		row.label:SetText(P.LABEL[key])
		labelW = max(labelW, ceil(row.label:GetStringWidth()) + (ELEMENT_OF[key] and (BOX + 8) or 0))
	end
	local lineX = padX - PAD_X   -- the selection box reaches the card's inset, the words stay in line
	local lineW = inner + PAD_X * 2
	local glyphX = max(floor(lineW * 0.42), PAD_X + labelW + 24)
	f.glyphX = glyphX
	for i, key in ipairs(P.ORDER) do
		local row = self.rows[i]
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", f, "TOPLEFT", lineX, -top)
		row:SetWidth(lineW)
		local lx = PAD_X
		if row.box then
			if ELEMENT_OF[key] then
				row.box:SetElement(ELEMENT_OF[key])
				row.box:ClearAllPoints()
				row.box:SetPoint("LEFT", row, "LEFT", PAD_X, 0)
				row.box:Show()
				lx = PAD_X + BOX + 8
			else
				row.box:Hide()
			end
		end
		row.label:ClearAllPoints()
		row.label:SetPoint("LEFT", row, "LEFT", lx, 0)
		row.label:SetWidth(glyphX - lx - 12)   -- wraps (never cut) if a name ever runs long
		local h = max(LINE_H, ceil(row.label:GetStringHeight()) + 14)
		row:SetHeight(h)
		local tip = TIPS[key]
		if key ~= "layer" then tip = "While you hold " .. (holdName or "the button on the first line") .. ", this " .. tip end
		Core:AttachTooltip(row, P.LABEL[key], tip, "Click: set   Right-click: no button")
		row:Show()
		top = top + h + 2
	end
	for i = #P.ORDER + 1, #self.rows do self.rows[i]:Hide() end

	-- the gold line (the last pick) and the fight line
	top = top + 6
	if self.warn then
		f.warn:ClearAllPoints()
		f.warn:SetPoint("TOPLEFT", f, "TOPLEFT", padX, -top)
		f.warn:SetWidth(inner)
		f.warn:SetText(self.warn)
		f.warn:Show()
		top = top + ceil(f.warn:GetStringHeight()) + 8
	else
		f.warn:Hide()
	end
	if InCombatLockdown() or self.fightNote then
		f.fight:ClearAllPoints()
		f.fight:SetPoint("TOPLEFT", f, "TOPLEFT", padX, -top)
		f.fight:SetWidth(inner)
		f.fight:Show()
		top = top + ceil(f.fight:GetStringHeight()) + 8
	else
		f.fight:Hide()
	end

	-- the buttons, then the pad's hints beside them (under them when there is no room)
	f.recommended:ClearAllPoints()
	f.recommended:SetPoint("TOPLEFT", f, "TOPLEFT", padX, -top)
	f.reset:ClearAllPoints()
	f.reset:SetPoint("LEFT", f.recommended, "RIGHT", 8, 0)
	local bh = f.recommended:GetHeight()
	local hx = f.recommended:GetWidth() + 8 + f.reset:GetWidth() + 24
	local hy = top + floor((bh - GLYPH) / 2)
	local showHints = PadInput()
	local hintsH = 0
	for _, hint in ipairs(self.hints) do
		if showHints then
			local gw = PaintGlyph(hint.g, hint.key, GLYPH)
			hint.text:ClearAllPoints()
			hint.text:SetPoint("LEFT", hint.g, "RIGHT", 6, 0)
			local w = gw + 6 + ceil(hint.text:GetStringWidth())
			hint:SetSize(w, GLYPH)
			if hx + w > inner then hx, hy = 0, hy + max(bh, GLYPH) + 6 end
			hint:ClearAllPoints()
			hint:SetPoint("TOPLEFT", f, "TOPLEFT", padX + hx, -hy)
			hint:Show()
			hx = hx + w + 16
			hintsH = hy + GLYPH - top
		else
			hint:Hide()
		end
	end
	top = top + max(bh, hintsH)

	local h = top + PAD_BOTTOM + 2
	f:SetHeight(h)
	f:Show()
	Paint()
	SetInput()
	return f, h + ROW_GAP
end

function List:Release()
	if self.frame then self.frame:Hide() end
	for _, row in ipairs(self.rows) do Core:HideTooltipFor(row) end
	if self.frame then
		Core:HideTooltipFor(self.frame.recommended)
		Core:HideTooltipFor(self.frame.reset)
	end
end
