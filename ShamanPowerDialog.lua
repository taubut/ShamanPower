-- ============================================================================
-- ShamanPower's own dialog: the one small window every question, notice and
-- copy box in the addon uses (the setup code, the Discord link, Reset All
-- Positions, the raid-resistance prompt ...). It has the settings window's look
-- (ShamanPower_Config/Core.lua) and is drawn only from textures, font strings
-- and plain Buttons: no Blizzard dialog or template, so it looks the same on
-- every client and works without ShamanPower_Config.
--
--   ShamanPower:ShowSPDialog(spec) -> the dialog frame
--     spec.key       unique id; showing the same key again replaces that dialog
--     spec.title     heading; spec.text the body (both wrap, never cut off)
--     spec.subtitle  optional line under the heading, upper-cased, as in the
--                    settings window's dialogs
--     spec.editText  optional read-only box with this text, focused and fully
--                    selected, so Ctrl+C copies it; typing in it changes nothing
--     spec.buttons   1-3 { text = "Accept", onClick = function(dialog) end }; a
--                    click runs onClick, then closes the dialog unless onClick
--                    returns true. The first is the main one: highlighted and
--                    rightmost, as in the settings window's dialogs. None given:
--                    one Close button.
--     spec.onEscape  runs on Escape, the close X, the timeout, and Enter or
--                    Escape in the copy box. Out of combat Escape closes the
--                    newest dialog only, as StaticPopup did. In combat an addon
--                    may not hold the key, so the game closes the dialog along
--                    with every other open window (UISpecialFrames).
--     spec.timeout   optional seconds; spec.countdown = true shows what is left
--     spec.strata    default FULLSCREEN_DIALOG at a high frame level: above the
--                    setup tour and the settings window
--     spec.width     optional minimum width
--   ShamanPower:HideSPDialog(key)   closes it without running any callback
--   (Replacing a dialog by showing its key again runs no callback either.)
--
-- Also the pieces it is built from, for ShamanPower's own bars and panels:
--   ShamanPower:CreateSPButton(parent, text, minWidth, primary) -> Button
--     (button:SetLabel(text) changes the text and refits the width;
--      button:SetPrimary(primary) switches the look)
--   ShamanPower:CreateSPCloseButton(parent, size) -> Button (an "X")
--   ShamanPower:SPColor(key, alpha) -> r, g, b, a from the palette below
--   ShamanPower:SPMakeBorder(frame, key, thickness) / SPSetBorderColor(frame, key, alpha)
--   ShamanPower.SPDialogFonts        the font objects (title, text, dim, button, tiny, group)
--
-- Costs nothing until a dialog is shown. A timed dialog runs one timer, plus a
-- one-second ticker for its countdown, only while it is up; the Escape catcher
-- listens for combat start and end only while a dialog is up.
-- ============================================================================

local SP = ShamanPower
if not SP then return end

-- The settings window's palette (ShamanPower_Config/Core.lua), repeated here
-- because this file must work without that module.
local C = {
	windowBg   = { 0.055, 0.063, 0.078 },
	sidebarBg  = { 0.071, 0.082, 0.102 },
	contentBg  = { 0.086, 0.098, 0.122 },
	rowBg      = { 0.110, 0.125, 0.153 },
	rowHover   = { 0.145, 0.165, 0.200 },
	border     = { 0.180, 0.204, 0.243 },
	borderSoft = { 0.130, 0.148, 0.180 },
	accent     = { 0.000, 0.439, 0.867 },
	accentHi   = { 0.247, 0.663, 1.000 },
	text       = { 0.902, 0.918, 0.941 },
	textDim    = { 0.541, 0.580, 0.651 },
	textMute   = { 0.353, 0.392, 0.455 },
	on         = { 0.180, 0.800, 0.443 },
	off        = { 0.320, 0.350, 0.400 },
	warn       = { 0.900, 0.290, 0.290 },
}
local function color(key, alpha)
	local c = C[key]
	if not c then return 1, 1, 1, alpha or 1 end
	return c[1], c[2], c[3], alpha or 1
end

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_NARROW = "Fonts\\ARIALN.TTF"
local function makeFont(name, size, key, path)
	local f = CreateFont(name)
	f:SetFont(path or FONT, size, "")
	f:SetShadowOffset(1, -1)
	f:SetShadowColor(0, 0, 0, 0.8)
	f:SetTextColor(color(key))
	return f
end
local FONTS = {
	title  = makeFont("ShamanPowerDialogFontTitle", 16, "text"),
	text   = makeFont("ShamanPowerDialogFontText", 12, "text"),
	dim    = makeFont("ShamanPowerDialogFontDim", 11, "textDim"),
	button = makeFont("ShamanPowerDialogFontButton", 12, "text"),
	tiny   = makeFont("ShamanPowerDialogFontTiny", 10, "textMute", FONT_NARROW),   -- subtitles, captions
	group  = makeFont("ShamanPowerDialogFontGroup", 11, "accentHi", FONT_NARROW),  -- group headers (UPPERCASE)
}

-- 1px (or thicker) border from four edge textures, like Core:MakeBorder.
local function makeBorder(frame, key, thickness)
	thickness = thickness or 1
	local edges = {}
	for i = 1, 4 do
		local t = frame:CreateTexture(nil, "BORDER")
		t:SetColorTexture(color(key))
		edges[i] = t
	end
	edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(thickness)
	edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(thickness)
	edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(thickness)
	edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(thickness)
	frame.spEdges = edges
end
local function borderColor(frame, key, alpha)
	for _, t in ipairs(frame.spEdges) do t:SetColorTexture(color(key, alpha)) end
end

-- The same palette, fonts and border for ShamanPower's other bars and panels
-- (Unlock UI, keybind mode, the ready check list, the minimap menu), so none
-- of them keeps a copy of its own.
SP.SPDialogFonts = FONTS
function SP:SPColor(key, alpha) return color(key, alpha) end
function SP:SPMakeBorder(frame, key, thickness) makeBorder(frame, key, thickness) end
function SP:SPSetBorderColor(frame, key, alpha) borderColor(frame, key, alpha) end

-- The accent rule under a header: a gradient that brightens to the right.
-- SetGradient took colour objects from 10.0 on and plain numbers before.
local function accentRule(tex)
	local r, g, b = color("accentHi")
	tex:SetColorTexture(1, 1, 1, 1)
	if CreateColor and pcall(tex.SetGradient, tex, "HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.9)) then return end
	if tex.SetGradientAlpha then tex:SetGradientAlpha("HORIZONTAL", r, g, b, 0, r, g, b, 0.9) return end
	tex:SetColorTexture(r, g, b, 0.5)
end

-- ---------------------------------------------------------------------------
-- Buttons (Core:MakeButton's look)
-- ---------------------------------------------------------------------------
local function paintButton(b, hover)
	local p = b.spPrimary
	b.bg:SetColorTexture(color("accent", hover and (p and 0.48 or 0.26) or (p and 0.30 or 0.12)))
end

local function buttonSetPrimary(b, primary)
	b.spPrimary = primary and true or false
	borderColor(b, primary and "accent" or "border")
	b.text:SetTextColor(color(primary and "accentHi" or "text"))
	paintButton(b, false)
end

local function buttonSetLabel(b, text)
	b.text:SetText(text or "")
	b:SetWidth(math.max(b.spMinWidth, math.ceil(b.text:GetStringWidth()) + 28))
end

function SP:CreateSPButton(parent, text, minWidth, primary)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(26)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints(b)
	makeBorder(b, "border")
	b.text = b:CreateFontString(nil, "OVERLAY")
	b.text:SetFontObject(FONTS.button)
	b.text:SetPoint("CENTER")
	b.spMinWidth = minWidth or 0
	b.SetPrimary, b.SetLabel = buttonSetPrimary, buttonSetLabel
	b:SetScript("OnEnter", function(self) paintButton(self, true) end)
	b:SetScript("OnLeave", function(self) paintButton(self, false) end)
	b:SetPrimary(primary)
	b:SetLabel(text)
	return b
end

function SP:CreateSPCloseButton(parent, size)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size or 22, size or 22)
	makeBorder(b, "border")
	local x = b:CreateFontString(nil, "OVERLAY")
	x:SetFontObject(FONTS.text)
	x:SetPoint("CENTER")
	x:SetText("X")
	x:SetTextColor(color("textDim"))
	b:SetScript("OnEnter", function(self) borderColor(self, "warn"); x:SetTextColor(color("warn")) end)
	b:SetScript("OnLeave", function(self) borderColor(self, "border"); x:SetTextColor(color("textDim")) end)
	return b
end

-- ---------------------------------------------------------------------------
-- The dialog
-- ---------------------------------------------------------------------------
-- Core:CreateDialog's measures: header 46, padding 14, body 10 under the
-- header's accent rule, a 52px footer with the buttons 12 up from the bottom
local PAD, HEADER_H, BODY_TOP, FOOTER, BTN_H, BTN_GAP = 14, 46, 10, 52, 26, 8
local MIN_W, LEVEL = 380, 200
local dialogs = {}   -- [key] = frame, made the first time that key is shown
local count = 0
local open = {}      -- dialogs on screen, the newest last (Escape closes that one)
local catcher        -- takes Escape for the dialogs out of combat, made on first use

-- Errors in a caller's handler go to the error handler (BugSack and the like)
-- without stopping the dialog from closing.
local function call(fn, f)
	return xpcall(function() return fn(f) end, geterrorhandler())
end

local function stopTimers(f)
	if f.spTimer then f.spTimer:Cancel(); f.spTimer = nil end
	if f.spTicker then f.spTicker:Cancel(); f.spTicker = nil end
end

local function unlist(f)
	for i = #open, 1, -1 do
		if open[i] == f then tremove(open, i) end
	end
end

local finish   -- forward

-- Escape reaches a keyboard frame before the game's own Escape handling
-- (ToggleGameMenu), which would otherwise close every open window along with
-- the dialog: the settings window, bags, the character panel. Out of combat a
-- frame above them takes Escape for the newest dialog and lets every other
-- key through. SetPropagateKeyboardInput may not be called in combat, so the
-- catcher is hidden before the lockdown starts (a hidden frame gets no keys),
-- its keyboard is switched on out of combat only, and Escape falls back to
-- UISpecialFrames until the fight ends.
local function catcherKey(self, key)
	if InCombatLockdown() then return end   -- hidden by then; never here
	if key == "ESCAPE" and open[#open] then
		self:SetPropagateKeyboardInput(false)
		finish(open[#open], "escape")
	else
		self:SetPropagateKeyboardInput(true)
	end
end

local function updateCatcher()
	if #open == 0 then
		if catcher then catcher:UnregisterAllEvents(); catcher:Hide() end
		return
	end
	if not catcher then
		catcher = CreateFrame("Frame", nil, UIParent)
		catcher:SetAllPoints(UIParent)
		catcher:SetFrameStrata("FULLSCREEN_DIALOG")
		catcher:SetFrameLevel(LEVEL + 50)
		catcher:EnableMouse(false)
		catcher:Hide()
		catcher:SetScript("OnEvent", function(self, event)
			if event == "PLAYER_REGEN_DISABLED" then self:Hide() else updateCatcher() end
		end)
	end
	catcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	catcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	if catcher:IsShown() or InCombatLockdown() then return end   -- shown when the fight ends
	if not catcher.spKeys then
		catcher.spKeys = true
		catcher:EnableKeyboard(true)
		catcher:SetScript("OnKeyDown", catcherKey)
	end
	catcher:SetPropagateKeyboardInput(true)   -- a key held from before passes through
	catcher:Show()
end

-- how: "escape" runs spec.onEscape; anything else closes without a callback
function finish(f, how)
	local spec = f.spec
	if not spec then return end
	f.spec, f.spEditText = nil, nil
	stopTimers(f)
	unlist(f)
	updateCatcher()
	f.box:ClearFocus()
	f:Hide()
	if how == "escape" and spec.onEscape then call(spec.onEscape, f) end
end

local function click(f, i)
	local spec = f.spec
	if not spec then return end
	local def = spec.buttons and spec.buttons[i]
	local keep = false
	if def and def.onClick then
		local ok, res = call(def.onClick, f)
		keep = ok and res == true
	end
	-- a handler may have shown this key again (a new dialog): leave that one up
	if not keep and f.spec == spec then finish(f, "button") end
end

local function countdownText(f)
	local left = math.max(0, math.ceil((f.spDeadline or 0) - GetTime()))
	f.timer:SetText("Closes by itself in " .. left .. (left == 1 and " second" or " seconds"))
end

local function build()
	count = count + 1
	local f = CreateFrame("Frame", "ShamanPowerDialog" .. count, UIParent)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetFrameLevel(LEVEL)
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	tinsert(UISpecialFrames, f:GetName())   -- Escape in combat (the catcher above is hidden then)

	-- Solid at any Background Opacity, on purpose: a popup never fades (the
	-- settings window's What's New and previews add an opaque copy for the same
	-- reason). A drag holds while it is up; it opens centred again next time,
	-- as the settings window's dialogs do, so no position is saved.
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(f)
	bg:SetColorTexture(color("windowBg"))
	makeBorder(f, "accent", 2)

	f.headerBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	f.headerBg:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
	f.headerBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
	f.headerBg:SetColorTexture(color("sidebarBg"))
	f.rule = f:CreateTexture(nil, "ARTWORK")
	f.rule:SetHeight(2)
	accentRule(f.rule)

	-- one line of title sits where CreateDialog puts it (6 above the header's
	-- middle); a title or subtitle that wraps makes the header taller instead
	f.title = f:CreateFontString(nil, "OVERLAY")
	f.title:SetFontObject(FONTS.title)
	f.title:SetJustifyH("LEFT"); f.title:SetWordWrap(true)
	f.title:SetText("X")
	f.titleLineH = f.title:GetStringHeight()
	f.title:SetPoint("TOPLEFT", f.headerBg, "TOPLEFT", PAD, -(HEADER_H / 2 - 6 - f.titleLineH / 2))
	f.subtitle = f:CreateFontString(nil, "OVERLAY")
	f.subtitle:SetFontObject(FONTS.tiny)
	f.subtitle:SetJustifyH("LEFT"); f.subtitle:SetWordWrap(true)
	f.subtitle:SetText("X")
	f.subLineH = f.subtitle:GetStringHeight()
	f.subtitle:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 1, -2)

	local close = SP:CreateSPCloseButton(f, 22)
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -12)
	close:SetScript("OnClick", function() finish(f, "escape") end)

	f.text = f:CreateFontString(nil, "OVERLAY")
	f.text:SetFontObject(FONTS.text)
	f.text:SetJustifyH("LEFT"); f.text:SetJustifyV("TOP"); f.text:SetWordWrap(true)

	-- the read-only copy box
	local box = CreateFrame("EditBox", nil, f)
	box:SetHeight(26)
	box:SetAutoFocus(false)
	box:SetFontObject(FONTS.text)
	box:SetTextInsets(8, 8, 0, 0)
	local boxBg = box:CreateTexture(nil, "BACKGROUND")
	boxBg:SetAllPoints(box)
	boxBg:SetColorTexture(color("sidebarBg"))
	makeBorder(box, "border")
	box:SetScript("OnEditFocusGained", function(self) borderColor(self, "accent"); self:HighlightText() end)
	box:SetScript("OnEditFocusLost", function(self) borderColor(self, "border"); self:HighlightText(0, 0) end)
	box:SetScript("OnMouseUp", function(self) self:HighlightText() end)   -- a click selects it all again
	box:SetScript("OnTextChanged", function(self)
		local want = f.spEditText
		if want and self:GetText() ~= want then self:SetText(want); self:HighlightText() end
	end)
	box:SetScript("OnEscapePressed", function() finish(f, "escape") end)
	box:SetScript("OnEnterPressed", function() finish(f, "escape") end)
	f.box = box
	f.measure = f:CreateFontString(nil, "OVERLAY")
	f.measure:SetFontObject(FONTS.text)
	f.measure:Hide()

	f.timer = f:CreateFontString(nil, "OVERLAY")
	f.timer:SetFontObject(FONTS.dim)
	f.timer:SetJustifyH("LEFT")

	f.buttons = {}
	for i = 1, 3 do
		local b = SP:CreateSPButton(f, "", 90, i == 1)
		b:SetScript("OnClick", function() click(f, i) end)
		b:Hide()
		f.buttons[i] = b
	end

	-- Escape in combat (UISpecialFrames) and anything else that hides the frame itself.
	-- A hidden parent (Alt+Z) also sends OnHide, but the frame stays "shown".
	f:SetScript("OnHide", function(self)
		if self.spec and not self:IsShown() then finish(self, "escape") end
	end)
	return f
end

local DEFAULT_BUTTONS = { { text = CLOSE or "Close" } }

local function layout(f, spec)
	local defs = spec.buttons and #spec.buttons > 0 and spec.buttons or DEFAULT_BUTTONS
	-- as wide as the button row and the whole copy text need, never narrower than asked
	local w = math.max(tonumber(spec.width) or 0, MIN_W)
	local rowW = 0
	for i, b in ipairs(f.buttons) do
		local def = defs[i]
		if def then
			b:SetPrimary(i == 1)
			b:SetLabel(def.text or "OK")
			rowW = rowW + b:GetWidth() + (i > 1 and BTN_GAP or 0)
			b:Show()
		else
			b:Hide()
		end
	end
	w = math.max(w, rowW + 2 * PAD)
	if f.spEditText then
		f.measure:SetText(f.spEditText)
		w = math.max(w, math.ceil(f.measure:GetStringWidth()) + 24 + 2 * PAD)
	end
	local screenW = UIParent:GetWidth()
	if screenW and screenW > 100 and w > screenW - 40 then w = math.floor(screenW - 40) end
	f:SetWidth(w)
	local inner = w - 2 * PAD

	f.title:SetWidth(inner - 30)   -- clear of the close X
	f.title:SetText(spec.title or "")
	local headerH = HEADER_H + math.max(0, math.ceil(f.title:GetStringHeight() - f.titleLineH))
	if spec.subtitle and spec.subtitle ~= "" then
		f.subtitle:SetWidth(inner - 31)
		f.subtitle:SetText(strupper(spec.subtitle))
		f.subtitle:Show()
		headerH = headerH + math.max(0, math.ceil(f.subtitle:GetStringHeight() - f.subLineH))
	else
		f.subtitle:Hide()
	end
	f.headerBg:SetHeight(headerH)
	f.rule:ClearAllPoints()
	f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -(headerH + 2))
	f.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -(headerH + 2))
	local y, gap = headerH + 4 + BODY_TOP, 0

	if spec.text and spec.text ~= "" then
		y = y + gap
		f.text:SetWidth(inner)
		f.text:SetText(spec.text)
		f.text:ClearAllPoints()
		f.text:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
		f.text:Show()
		y, gap = y + math.ceil(f.text:GetStringHeight()), 12
	else
		f.text:Hide()
	end
	if f.spEditText then
		y = y + gap
		f.box:ClearAllPoints()
		f.box:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
		f.box:SetWidth(inner)
		f.box:Show()
		y, gap = y + BTN_H, 12
	else
		f.box:Hide()
	end
	if spec.countdown and f.spDeadline then
		y = y + gap
		f.timer:SetWidth(inner)
		countdownText(f)
		f.timer:ClearAllPoints()
		f.timer:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
		f.timer:Show()
		y = y + math.ceil(f.timer:GetStringHeight())
	else
		f.timer:Hide()
	end

	-- the main button on the right, the others to its left
	local prev
	for _, b in ipairs(f.buttons) do
		if b:IsShown() then
			b:ClearAllPoints()
			if prev then b:SetPoint("RIGHT", prev, "LEFT", -BTN_GAP, 0)
			else b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 12) end
			prev = b
		end
	end
	f:SetHeight(y + PAD + FOOTER)
end

function SP:ShowSPDialog(spec)
	if type(spec) ~= "table" then return nil end
	local key = spec.key or "default"
	local f = dialogs[key]
	if not f then f = build(); f.spKey = key; dialogs[key] = f end
	local wasShown = f:IsShown() and f.spec ~= nil
	stopTimers(f)
	f.spec = spec
	f.spEditText = spec.editText ~= nil and tostring(spec.editText) or nil
	local timeout = tonumber(spec.timeout)
	f.spDeadline = (timeout and timeout > 0) and (GetTime() + timeout) or nil

	f:SetFrameStrata(spec.strata or "FULLSCREEN_DIALOG")
	f:SetFrameLevel(LEVEL)
	unlist(f)
	open[#open + 1] = f
	updateCatcher()
	layout(f, spec)
	if not wasShown then
		f:ClearAllPoints()
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	end
	f:Show()
	f:Raise()

	if f.spEditText then
		f.box:SetText(f.spEditText)
		f.box:SetCursorPosition(0)
		f.box:SetFocus()
		f.box:HighlightText()
	else
		f.box:ClearFocus()
	end

	if f.spDeadline then
		f.spTimer = C_Timer.NewTimer(timeout, function()
			if f.spec == spec then finish(f, "escape") end
		end)
		if spec.countdown then
			f.spTicker = C_Timer.NewTicker(1, function() countdownText(f) end)
		end
	end
	return f
end

function SP:HideSPDialog(key)
	local f = key and dialogs[key]
	if f then finish(f, "silent") end
end
