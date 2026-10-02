-- ============================================================================
-- ShamanPower's own dialog: the one small window every question, notice and
-- copy box in the addon uses (the setup code, the Discord link, Reset All
-- Positions, the raid-resistance prompt ...). It has the settings window's look
-- (ShamanPower_Config: the soft edge, the four elements along the top, the lit
-- header band, Fira Sans) and is drawn only from textures, font strings and
-- plain Buttons: no Blizzard dialog or template, so it looks the same on every
-- client and works without ShamanPower_Config.
--
--   ShamanPower:ShowSPDialog(spec) -> the dialog frame
--     spec.key       unique id; showing the same key again replaces that dialog
--     spec.title     heading; spec.text the body (both wrap, never cut off)
--     spec.subtitle  optional line under the heading, upper-cased, as in the
--                    settings window's dialogs
--     spec.editText  optional read-only box with this text, focused and fully
--                    selected, so Ctrl+C copies it; typing in it changes nothing
--     spec.editScroll  the box keeps the dialog's width and its text scrolls
--                    (a long code), instead of the dialog widening to fit it
--     spec.input     optional box the player TYPES in (a name, a pasted code):
--                    { text = "starting text", maxLetters = n }. A button's
--                    onClick(dialog) reads it with dialog:GetInput(); Enter
--                    clicks the first button. (editText is the read-only copy box.)
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
	windowBg   = { 0.055, 0.078, 0.118 },
	sidebarBg  = { 0.067, 0.094, 0.137 },
	contentBg  = { 0.078, 0.106, 0.149 },
	rowBg      = { 0.102, 0.133, 0.188 },
	rowHover   = { 0.137, 0.176, 0.239 },
	border     = { 0.169, 0.216, 0.290 },
	borderSoft = { 0.122, 0.157, 0.212 },
	white       = { 1, 1, 1 },
	accent     = { 0.000, 0.439, 0.867 },
	accentHi   = { 0.247, 0.663, 1.000 },
	text       = { 0.902, 0.918, 0.941 },
	textDim    = { 0.541, 0.580, 0.651 },
	textMute   = { 0.353, 0.392, 0.455 },
	on         = { 0.180, 0.800, 0.443 },
	off        = { 0.320, 0.350, 0.400 },
	warn       = { 0.900, 0.290, 0.290 },
	bandLight  = { 27 / 255, 36 / 255, 51 / 255 },   -- the header band's light (#1B2433), before its element
}
local function color(key, alpha)
	local c = C[key]
	if not c then return 1, 1, 1, alpha or 1 end
	return c[1], c[2], c[3], alpha or 1
end

-- Fira Sans from the brand kit (ShamanPowerBrand.lua, loaded before this file),
-- with the settings window's weights and sizes (Core.fonts): SemiBold for titles,
-- Medium for the small-caps labels, Regular for every other word. SP:BrandFontPath
-- gives the game's own font on Chinese and Korean clients; a font that fails to
-- load falls back to it too.
local GAME_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local function makeFont(name, size, key, weight)
	local f = CreateFont(name)
	local path = SP.BrandFontPath and SP:BrandFontPath(weight) or GAME_FONT
	if not (pcall(f.SetFont, f, path, size, "") and f:GetFont()) then f:SetFont(GAME_FONT, size, "") end
	f:SetShadowOffset(1, -1)
	f:SetShadowColor(0, 0, 0, 0.8)
	f:SetTextColor(color(key))
	return f
end
local FONTS = {
	title  = makeFont("ShamanPowerDialogFontTitle", 16, "text", "semibold"),
	text   = makeFont("ShamanPowerDialogFontText", 12, "text"),
	dim    = makeFont("ShamanPowerDialogFontDim", 11, "textDim"),
	button = makeFont("ShamanPowerDialogFontButton", 12, "text"),
	tiny   = makeFont("ShamanPowerDialogFontTiny", 10, "textMute", "medium"),   -- subtitles, captions
	group  = makeFont("ShamanPowerDialogFontGroup", 10, "accentHi", "medium"),  -- group headers (UPPERCASE)
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

-- ---------------------------------------------------------------------------
-- Buttons (Core:BevelButton's look: a flat blue base - stronger for the
-- primary - with a soft vertical shade, a lit top edge and a shadowed bottom
-- edge over it; the border lights up on hover and a press pushes it in)
-- ---------------------------------------------------------------------------
local function shadeV(tex)   -- bottom darker, top lighter
	tex:SetColorTexture(1, 1, 1, 1)
	if CreateColor and pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(0, 0, 0, 0.24), CreateColor(1, 1, 1, 0.06)) then return end
	if tex.SetGradientAlpha then tex:SetGradientAlpha("VERTICAL", 0, 0, 0, 0.24, 1, 1, 1, 0.06) return end
	tex:SetColorTexture(0, 0, 0, 0.1)
end

local function paintButton(b, hover)
	if b.spPrimary then
		b.bg:SetColorTexture(color("accent", hover and 0.62 or 0.46))
	else
		b.bg:SetColorTexture(color("accent", hover and 0.46 or 0.28))
	end
	borderColor(b, hover and "accentHi" or "accent")
end

local function buttonSetPrimary(b, primary)
	b.spPrimary = primary and true or false
	b.hi:SetColorTexture(color("accentHi", primary and 0.45 or 0.35))
	b.text:SetTextColor(color("white"))
	paintButton(b, false)
end

local function buttonSetLabel(b, text)
	b.text:SetText(text or "")
	b:SetWidth(math.max(b.spMinWidth, math.ceil(b.text:GetStringWidth()) + 28))
end

-- the press drops the caption a pixel from its own anchor and puts it back on release
local function buttonRelease(b)
	b.down:Hide(); b.hi:Show()
	local h = b.spHeld
	if h then
		b.text:SetPoint(h[1], h[2], h[3], h[4], h[5])
		b.spHeld = nil
	end
end

function SP:CreateSPButton(parent, text, minWidth, primary)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(26)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints(b)
	local shade = b:CreateTexture(nil, "BACKGROUND", nil, 1)
	shade:SetAllPoints(b)
	shadeV(shade)
	b.hi = b:CreateTexture(nil, "ARTWORK")
	b.hi:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
	b.hi:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
	b.hi:SetHeight(1)
	local lo = b:CreateTexture(nil, "ARTWORK")
	lo:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1)
	lo:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
	lo:SetHeight(1)
	lo:SetColorTexture(0, 0, 0, 0.35)
	b.down = b:CreateTexture(nil, "ARTWORK", nil, 1)
	b.down:SetAllPoints(b)
	b.down:SetColorTexture(0, 0, 0, 0.22)
	b.down:Hide()
	makeBorder(b, "accent")
	b.text = b:CreateFontString(nil, "OVERLAY")
	b.text:SetFontObject(FONTS.button)
	b.text:SetPoint("CENTER")
	b.spMinWidth = minWidth or 0
	b.SetPrimary, b.SetLabel = buttonSetPrimary, buttonSetLabel
	b:SetScript("OnEnter", function(self) paintButton(self, true) end)
	b:SetScript("OnLeave", function(self) paintButton(self, false) end)
	b:SetScript("OnMouseDown", function(self)
		if not self:IsEnabled() then return end
		self.down:Show(); self.hi:Hide()
		if not self.spHeld then
			local p, rel, rp, x, y = self.text:GetPoint(1)
			if p then
				self.spHeld = { p, rel, rp, x or 0, y or 0 }
				self.text:SetPoint(p, rel, rp, x or 0, (y or 0) - 1)
			end
		end
	end)
	b:SetScript("OnMouseUp", buttonRelease)
	b:HookScript("OnHide", buttonRelease)
	b:SetPrimary(primary)
	b:SetLabel(text)
	return b
end

-- The close X: a drawn X, no box; on hover a solid red square with a white X.
function SP:CreateSPCloseButton(parent, size)
	size = size or 22
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(b)
	bg:SetColorTexture(color("warn"))
	bg:SetAlpha(0)
	local r = math.floor(size * 0.24 + 0.5)
	local lines = {}
	for i, sign in ipairs({ 1, -1 }) do
		local l = b:CreateLine(nil, "OVERLAY")
		l:SetThickness(2)
		l:SetColorTexture(1, 1, 1, 1)
		l:SetStartPoint("CENTER", b, -r, sign * r)
		l:SetEndPoint("CENTER", b, r, -sign * r)
		lines[i] = l
	end
	local function paint(state)
		bg:SetAlpha(state == "down" and 1 or (state == "hover" and 0.92 or 0))
		if state == "down" then bg:SetColorTexture(0.62, 0.18, 0.18) else bg:SetColorTexture(color("warn")) end
		local cr, cg, cb = color(state == "normal" and "text" or "white")
		for _, l in ipairs(lines) do l:SetVertexColor(cr, cg, cb) end
	end
	paint("normal")
	b:SetScript("OnEnter", function() paint("hover") end)
	b:SetScript("OnLeave", function() paint("normal") end)
	b:SetScript("OnMouseDown", function() paint("down") end)
	b:SetScript("OnMouseUp", function(self) paint(self:IsMouseOver() and "hover" or "normal") end)
	b:HookScript("OnHide", function() paint("normal") end)
	return b
end

-- ---------------------------------------------------------------------------
-- The dialog
-- ---------------------------------------------------------------------------
-- Core:CreateDialog's measures: header 46, padding 14, a 52px footer with the
-- buttons 12 up from the bottom. The header band runs from the top edge to 2 + 46
-- (the header sat inside a 2px border); the body starts 12 under it, where it was
-- when a 2px accent rule sat there.
local PAD, HEADER_H, BODY_TOP, FOOTER, BTN_H, BTN_GAP = 14, 46, 10, 52, 26, 8
local MIN_W, LEVEL = 380, 200

-- The band's light, with the settings window's band numbers (Core:Light: the kit's
-- radial light centered 12% across the band's top, reach 1.2, drawn 1.16 times
-- larger and cut to the band by its texture coordinates), tinted 26% of the
-- element over bandLight. An SP dialog is a question, notice or copy box: its
-- element is spirit (logo blue).
local ELEMENT = "spirit"
local LIGHT_REACH, LIGHT_CX, LIGHT_CY, LIGHT_SIZE, LIGHT_MIX = 1.16, 0.12, 0, 1.2, 0.26
local function placeLight(tex, host, w, h)
	local hx, hy = (LIGHT_SIZE / 1.6) * w * LIGHT_REACH, LIGHT_SIZE * h * LIGHT_REACH
	local px, py = LIGHT_CX * w, LIGHT_CY * h
	local x0, x1 = math.max(0, px - hx), math.min(w, px + hx)
	local y0, y1 = math.max(0, py - hy), math.min(h, py + hy)
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", host, "TOPLEFT", x0, -y0)
	tex:SetSize(x1 - x0, y1 - y0)
	local left, top = px - hx, py - hy
	tex:SetTexCoord((x0 - left) / (2 * hx), (x1 - left) / (2 * hx), (y0 - top) / (2 * hy), (y1 - top) / (2 * hy))
end
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
	f.spec, f.spEditText, f.spInput = nil, nil, nil
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

	-- Solid at any Background Opacity, on purpose: a popup never fades (the
	-- settings window's What's New and previews add an opaque copy for the same
	-- reason). A drag holds while it is up; it opens centred again next time,
	-- as the settings window's dialogs do, so no position is saved.
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(f)
	bg:SetColorTexture(color("windowBg"))
	-- the settings window's edge: a soft 1.5px line in `border`, over the band
	makeBorder(f, "border", 1.5)

	-- The header band (the settings window's, D32b "lit by the element"): sidebarBg
	-- lit from its top left by the element, a 1px `border` line along its bottom,
	-- and the element's 44 x 3 underline on that line under the title (its height:
	-- layout). Without the brand file (an update the game has not loaded yet: new
	-- files need a restart) it falls back as Core:CreateDialog does: logo blue, no
	-- light, no stripe.
	f.headerBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	f.headerBg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.headerBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	f.headerBg:SetColorTexture(color("sidebarBg"))
	local er, eg, eb = 0.247, 0.663, 0.961   -- logo blue (#3FA9F5) without the brand kit
	if SP.BrandElementRGB then er, eg, eb = SP:BrandElementRGB(ELEMENT) end
	if SP.BrandRadialLight then
		local lr, lg, lb = color("bandLight")
		f.bandLight = SP:BrandRadialLight(f, "BACKGROUND", 2)
		f.bandLight:SetVertexColor(er * LIGHT_MIX + lr * (1 - LIGHT_MIX), eg * LIGHT_MIX + lg * (1 - LIGHT_MIX),
			eb * LIGHT_MIX + lb * (1 - LIGHT_MIX), 1)
	else
		f.bandLight = f:CreateTexture(nil, "BACKGROUND", nil, 2)
		f.bandLight:SetColorTexture(0, 0, 0, 0)   -- no light: the plain band stays
	end
	local bandEdge = f:CreateTexture(nil, "BORDER")
	bandEdge:SetHeight(1)
	bandEdge:SetPoint("BOTTOMLEFT", f.headerBg, "BOTTOMLEFT", 0, 0)
	bandEdge:SetPoint("BOTTOMRIGHT", f.headerBg, "BOTTOMRIGHT", 0, 0)
	bandEdge:SetColorTexture(color("border"))
	local underline = f:CreateTexture(nil, "ARTWORK")
	underline:SetSize(44, 3)
	underline:SetPoint("BOTTOMLEFT", f.headerBg, "BOTTOMLEFT", 2 + PAD, 0)
	underline:SetColorTexture(er, eg, eb, 1)
	-- the four elements along the top edge
	if SP.CreateElementStripe then
		local stripe = SP:CreateElementStripe(f)
		stripe:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		stripe:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	end

	-- one line of title sits where CreateDialog puts it (6 above the middle of the
	-- header, 2 in from the edge); a title or subtitle that wraps makes the header
	-- taller instead
	f.title = f:CreateFontString(nil, "OVERLAY")
	f.title:SetFontObject(FONTS.title)
	f.title:SetJustifyH("LEFT"); f.title:SetWordWrap(true)
	f.title:SetText("X")
	f.titleLineH = f.title:GetStringHeight()
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 2 + PAD, -(2 + HEADER_H / 2 - 6 - f.titleLineH / 2))
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
	box:SetMaxLetters(0)   -- no cap: a cut-off copy would fight the read-only guard below
	if box.SetMaxBytes then box:SetMaxBytes(0) end
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
	box:SetScript("OnEnterPressed", function()
		-- a box to type in: Enter is the main button; the copy box: Enter closes
		local b = f.spInput and f.spec and f.spec.buttons and f.spec.buttons[1]
		if b and f.buttons and f.buttons[1] and f.buttons[1]:IsShown() then f.buttons[1]:Click() return end
		finish(f, "escape")
	end)
	function f:GetInput() return self.box:GetText() or "" end
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
	-- listed for Escape in combat (the catcher above is hidden then) only once it is
	-- whole: a build that failed leaves nothing in the list
	tinsert(UISpecialFrames, f:GetName())
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
	if f.spEditText and not spec.editScroll and not f.spInput then
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
	f.headerBg:SetHeight(headerH + 2)
	placeLight(f.bandLight, f.headerBg, w, headerH + 2)
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
	if f.spEditText or f.spInput then
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
	f.spInput = type(spec.input) == "table" and spec.input or nil
	f.spEditText = (not f.spInput and spec.editText ~= nil) and tostring(spec.editText) or nil
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

	if f.spInput then
		f.box:SetMaxLetters(tonumber(f.spInput.maxLetters) or 0)
		f.box:SetText(tostring(f.spInput.text or ""))
		f.box:SetFocus()
		f.box:HighlightText()
	elseif f.spEditText then
		f.box:SetMaxLetters(0)
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
