-- ============================================================================
-- ShamanPower's own tooltip (D34 "Lit", tooltips_glowup_mock.py style C): the
-- one hover box of ShamanPower's windows (the settings window, the setup tour,
-- Totem Assignments, Totem Range, Unlock UI, the pickers ...). The menus' navy,
-- the settings window's soft 1.5 px edge, a thin stripe of the four elements on
-- top, the element of the page or window it opens from lighting it from the top
-- left (the settings header band's light), Fira Sans. No underline under the title (owner, 2026-10-02).
-- The in-game bars and frames keep WoW's own GameTooltip: never use this there.
--
--   SP.Tooltip   the GameTooltip calls our windows use, same meaning:
--     :SetOwner(owner, anchor, x, y)   ANCHOR_CURSOR (the windows' choice: at the mouse
--                       where it entered the owner, below and right of the pointer, flipped
--                       where the screen runs out; it does not trail the pointer), or
--                       ANCHOR_RIGHT / LEFT / TOP / BOTTOM / TOPLEFT / TOPRIGHT /
--                       BOTTOMLEFT / BOTTOMRIGHT, owner-relative
--     :SetText(text, r, g, b)          clears it, text is the title
--     :AddLine(text, r, g, b)          the first line is the title (SemiBold 13,
--                       white), the rest the words (Regular 12, the text color); a
--                       color keeps its meaning (red warnings ...); " " is a small
--                       gap; "\n" starts a new line. Every line wraps at 250 (a line
--                       without a space, a link, stays on one line and the box grows)
--     :AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
--     :AddHint(text)    what a click does: small caps in Medium 10, gray
--     :AddPath(text)    where a setting lives ("Settings > ..."), in the path blue
--     :SetElement(key)  after SetOwner: another element than the owner's
--     :ClearLines() :Show() :Hide() :IsShown() :IsOwned(frame) :GetOwner() :NumLines()
--   The element: the first of the owner and its parents with _element / spElement
--   (as Widgets:MenuElement); logo blue outside a page or window.
--
-- Built on first use. Nothing runs while it is hidden (no OnUpdate); its lines are
-- pooled, so a show allocates nothing but its strings. It hides with its owner, as
-- WoW's does. TOOLTIP strata, clamped to the screen. Without the brand file (an
-- update before a full restart) it is the plain navy box with its edge.
-- ============================================================================

local SP = ShamanPower
if not SP then return end

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local strfind, strsub, strupper = string.find, string.sub, string.upper

-- the mock's numbers (UI units)
local EDGE, STRIPE_H = 1.5, 2
local PAD_X, PAD_T, PAD_B = 10, 8, 9
local WRAP = 250
local GAP = 6                                 -- a blank line; before the click lines and the path
local TITLE_GAP = 4   -- between the title and the words (no underline under the title: owner, 2026-10-02)
local DOUBLE_GAP = 20                         -- between the two halves of a double line
-- ANCHOR_CURSOR: the box's corner from the pointer's tip (UI units): right and below it
-- clears the arrow; flipped, it sits left of or above the tip
local CURSOR_RIGHT, CURSOR_BELOW, CURSOR_FLIP = 16, 20, 6
-- [kind] = { font size, line height }
local SIZE = { title = 13, body = 12, hint = 10, path = 11 }
local LINE_H = { title = 15, body = 15, hint = 13, path = 15 }
local PATH_BLUE = { 0x3F / 255, 0xA9 / 255, 0xF5 / 255 }   -- |cff3FA9F5, the settings paths' blue
local LOGO_BLUE = { 0.247, 0.663, 0.961 }                   -- without the brand file
-- the band's light (Core:Light(host, w, h, .12, 0, 1.2) as the settings header has it)
local LIGHT_CX, LIGHT_CY, LIGHT_R, LIGHT_REACH = 0.12, 0, 1.2, 1.16
local LIGHT_MIX = 0.26                        -- 26% of the element over the band's light navy

-- where the tooltip goes for each anchor: its point, the owner's point (as GameTooltip)
local ANCHORS = {
	ANCHOR_RIGHT = { "BOTTOMLEFT", "TOPRIGHT" }, ANCHOR_LEFT = { "BOTTOMRIGHT", "TOPLEFT" },
	ANCHOR_TOP = { "BOTTOM", "TOP" }, ANCHOR_BOTTOM = { "TOP", "BOTTOM" },
	ANCHOR_TOPLEFT = { "BOTTOMLEFT", "TOPLEFT" }, ANCHOR_TOPRIGHT = { "BOTTOMRIGHT", "TOPRIGHT" },
	ANCHOR_BOTTOMLEFT = { "TOPRIGHT", "BOTTOMLEFT" }, ANCHOR_BOTTOMRIGHT = { "TOPLEFT", "BOTTOMRIGHT" },
}

local Tip = {}
SP.Tooltip = Tip

local frame, light
local fonts, defaultColor = {}, {}
local fsPool, rightPool = {}, {}
-- the lines, as parallel arrays (no table per line): kind, text, color, the right half's
local kinds, texts, rs, gs, bs = {}, {}, {}, {}, {}
local rTexts, rRs, rGs, rBs = {}, {}, {}, {}
local n = 0
local owner, anchor, anchorX, anchorY
local cursorX, cursorY   -- ANCHOR_CURSOR: where the pointer was when the owner was entered (screen pixels)
local elementKey, paintedKey
local hookedOwners = setmetatable({}, { __mode = "k" })

local function color(key)
	if SP.SPColor then return SP:SPColor(key) end
	return 1, 1, 1, 1
end

local function makeFont(name, kind, weight, r, g, b)
	defaultColor[kind] = { r, g, b }
	local f = CreateFont(name)
	local game = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
	local path = SP.BrandFontPath and SP:BrandFontPath(weight) or game
	if not (pcall(f.SetFont, f, path, SIZE[kind], "") and f:GetFont()) then f:SetFont(game, SIZE[kind], "") end
	f:SetShadowOffset(1, -1)
	f:SetShadowColor(0, 0, 0, 0.8)
	f:SetTextColor(r, g, b)
	-- each wrapped line takes the line height (the font size plus this)
	f:SetSpacing(LINE_H[kind] - SIZE[kind])
	return f
end

local function build()
	frame = CreateFrame("Frame", "ShamanPowerTooltip", UIParent)
	frame:SetFrameStrata("TOOLTIP")
	frame:SetFrameLevel(200)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(false)
	frame:Hide()
	-- only a real Hide forgets the owner (a hidden parent, e.g. Alt+Z, keeps it, so the
	-- owner's OnLeave can still hide it when the UI comes back)
	frame:SetScript("OnHide", function(self) if not self:IsShown() then owner = nil end end)

	-- the menus' navy, the element's light over it from the top left
	local fill = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
	fill:SetAllPoints(frame)
	fill:SetColorTexture(color("sidebarBg"))
	if SP.BrandRadialLight then light = SP:BrandRadialLight(frame, "BACKGROUND", 1) end
	-- the soft edge, and the four elements along the top over it
	if SP.SPMakeBorder then SP:SPMakeBorder(frame, "border", EDGE) end
	if SP.CreateElementStripe then
		local stripe = SP:CreateElementStripe(frame)
		stripe:SetStripeHeight(STRIPE_H)
		stripe:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
		stripe:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	end

	fonts.title = makeFont("ShamanPowerTooltipFontTitle", "title", "semibold", color("white"))
	fonts.body = makeFont("ShamanPowerTooltipFontText", "body", "regular", color("text"))
	fonts.hint = makeFont("ShamanPowerTooltipFontHint", "hint", "medium", color("textMute"))
	fonts.path = makeFont("ShamanPowerTooltipFontPath", "path", "regular", PATH_BLUE[1], PATH_BLUE[2], PATH_BLUE[3])
end

local function fontString(pool, i)
	local fs = pool[i]
	if fs then return fs end
	fs = frame:CreateFontString(nil, "OVERLAY")
	fs:SetJustifyH(pool == rightPool and "RIGHT" or "LEFT")
	fs:SetJustifyV("TOP")
	fs:SetWordWrap(true)
	fs:SetNonSpaceWrap(true)   -- a word longer than the line breaks rather than runs out
	pool[i] = fs
	return fs
end

-- ---------------------------------------------------------------------------
-- The lines
-- ---------------------------------------------------------------------------
local function push(kind, text, r, g, b)
	n = n + 1
	kinds[n], texts[n], rs[n], gs[n], bs[n] = kind, text, r, g, b
	rTexts[n] = nil
end

-- one call's text, a line per "\n"; the first line of the tooltip is its title
local function add(kind, text, r, g, b)
	text = text ~= nil and tostring(text) or ""
	local start = 1
	repeat
		local nl = strfind(text, "\n", start, true)
		local line = nl and strsub(text, start, nl - 1) or (start == 1 and text or strsub(text, start))
		local k = kind
		if k == "body" and n == 0 then k = "title" end
		if (k == "body" or k == "title") and not strfind(line, "%S") then
			if n > 0 then push("gap") end
		else
			if k == "hint" then line = strupper(line) end
			push(k, line, r, g, b)
		end
		start = nl and nl + 1 or nil
	until not start
end

function Tip.ClearLines(_)
	n = 0
end

function Tip.NumLines(_)
	return n
end

local function ownerHidden(f)
	if owner == f and frame then frame:Hide() end
end

function Tip.SetOwner(_, f, anchorType, x, y)
	if not frame then build() end
	frame:Hide()   -- (as WoW's: a new owner starts empty, until Show)
	owner, anchor, anchorX, anchorY = f, anchorType or "ANCHOR_RIGHT", x or 0, y or 0
	if anchor == "ANCHOR_CURSOR" then cursorX, cursorY = GetCursorPosition() end
	elementKey = nil
	n = 0
	-- it hides with its owner, as WoW's tooltip does (hooked once per frame)
	if f and f.HookScript and not hookedOwners[f] then
		hookedOwners[f] = true
		f:HookScript("OnHide", ownerHidden)
	end
end

function Tip.SetElement(_, key)
	elementKey = key
end

function Tip.SetText(_, text, r, g, b)
	n = 0
	add("body", text, r, g, b)
end

function Tip.AddLine(_, text, r, g, b)
	add("body", text, r, g, b)
end

function Tip.AddDoubleLine(_, left, right, lr, lg, lb, rr, rg, rb)
	if n == 0 then
		push("title", left ~= nil and tostring(left) or "", lr, lg, lb)
	else
		push("body", left ~= nil and tostring(left) or "", lr, lg, lb)
	end
	rTexts[n], rRs[n], rGs[n], rBs[n] = right ~= nil and tostring(right) or "", rr, rg, rb
end

function Tip.AddHint(_, text)
	add("hint", text)
end

function Tip.AddPath(_, text)
	add("path", text)
end

function Tip.GetOwner(_)
	return owner
end

function Tip.IsOwned(_, f)
	return owner ~= nil and owner == f
end

function Tip.IsShown(_)
	return frame ~= nil and frame:IsShown()
end

function Tip.Hide(_)
	if frame then frame:Hide() end
end

function Tip.SetClampedToScreen(_) end   -- (always clamped)

-- ---------------------------------------------------------------------------
-- Show: lay the lines out, size the box, light it, put it by its owner
-- ---------------------------------------------------------------------------
-- the element of the page or window the owner sits in (Widgets:MenuElement's walk)
local function ownerElement(f)
	local depth = 0
	while f and depth < 24 do
		local el = f._element or f.spElement
		if type(el) == "string" then return el end
		if not f.GetParent then return nil end
		f = f:GetParent()
		depth = depth + 1
	end
	return nil
end

local function paintElement(key)
	if paintedKey == key then return end
	paintedKey = key
	local er, eg, eb = LOGO_BLUE[1], LOGO_BLUE[2], LOGO_BLUE[3]
	if SP.BrandElementRGB then er, eg, eb = SP:BrandElementRGB(key) end
	if light then
		local lr, lg, lb = 27 / 255, 36 / 255, 51 / 255   -- the band's light navy (#1B2433)
		light:SetVertexColor(er * LIGHT_MIX + lr * (1 - LIGHT_MIX), eg * LIGHT_MIX + lg * (1 - LIGHT_MIX),
			eb * LIGHT_MIX + lb * (1 - LIGHT_MIX), 1)
	end
end

-- Core:PlaceLight: the light's part inside the box (its texture cut to it)
local function placeLight(w, h)
	local hx, hy = (LIGHT_R / 1.6) * w * LIGHT_REACH, LIGHT_R * h * LIGHT_REACH
	local px, py = LIGHT_CX * w, LIGHT_CY * h
	local x0, x1 = max(0, px - hx), min(w, px + hx)
	local y0, y1 = max(0, py - hy), min(h, py + hy)
	light:ClearAllPoints()
	light:SetPoint("TOPLEFT", frame, "TOPLEFT", x0, -y0)
	light:SetSize(x1 - x0, y1 - y0)
	local left, top = px - hx, py - hy
	light:SetTexCoord((x0 - left) / (2 * hx), (x1 - left) / (2 * hx), (y0 - top) / (2 * hy), (y1 - top) / (2 * hy))
end

local function width(fs)
	return (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth()
end

function Tip.Show(_)
	if not frame then build() end
	-- (trailing blank lines draw nothing)
	while n > 0 and kinds[n] == "gap" do n = n - 1 end
	for i = n + 1, #fsPool do fsPool[i]:Hide() end
	for _, rfs in pairs(rightPool) do rfs:Hide() end   -- (pairs: its slots follow the line numbers, with holes)
	if n == 0 then frame:Hide() return end

	local y, widest, prev = STRIPE_H + PAD_T, 0, nil
	local titled = false
	for i = 1, n do
		local kind = kinds[i]
		local fs = fontString(fsPool, i)
		if kind == "gap" then
			fs:Hide()
			if prev ~= "gap" then y = y + GAP end
		else
			if (kind == "hint" and prev ~= "hint" and prev ~= "gap" and prev ~= nil)
				or (kind == "path" and prev ~= "path" and prev ~= "gap" and prev ~= nil) then
				y = y + GAP
			end
			local size, lh = SIZE[kind], LINE_H[kind]
			fs:SetFontObject(fonts[kind])
			-- (a font object leaves a color set on the string before: set it every time)
			local c = defaultColor[kind]
			if rs[i] then fs:SetTextColor(rs[i], gs[i], bs[i]) else fs:SetTextColor(c[1], c[2], c[3]) end
			fs:SetWidth(0)
			fs:SetText(texts[i])
			local w = width(fs)
			local lines = 1
			local right = rTexts[i]
			if right then
				local rfs = fontString(rightPool, i)
				rfs:SetFontObject(fonts.body)
				local rc = defaultColor.body
				if rRs[i] then rfs:SetTextColor(rRs[i], rGs[i], rBs[i]) else rfs:SetTextColor(rc[1], rc[2], rc[3]) end
				rfs:SetText(right)
				rfs:ClearAllPoints()
				rfs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD_X, -(y + (lh - size) / 2))
				rfs:Show()
				w = w + DOUBLE_GAP + width(rfs)
			elseif w > WRAP and strfind(texts[i], " ", 1, true) then
				-- a long line wraps at 250; the box is as wide as its widest line
				fs:SetWidth(WRAP)
				w = (fs.GetWrappedWidth and fs:GetWrappedWidth()) or WRAP
				if not w or w <= 0 or w > WRAP then w = WRAP end
				-- the larger of the two counts: GetNumLines is new to the addon and may under-report
				-- while hidden; the height count is what the settings window already relies on
				local byHeight = max(1, floor((fs:GetStringHeight() + lh - size) / lh + 0.5))
				lines = (fs.GetNumLines and fs:GetNumLines()) or 0
				if lines < byHeight then lines = byHeight end
			end
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD_X, -(y + (lh - size) / 2))
			fs:Show()
			if w > widest then widest = w end
			y = y + lines * lh
			if kind == "title" and not titled then
				titled = true
				y = y + TITLE_GAP
			end
		end
		prev = kind
	end

	local w, h = ceil(PAD_X + widest + PAD_X), ceil(y + PAD_B)
	frame:SetSize(w, h)
	paintElement(elementKey or ownerElement(owner) or "spirit")
	if light then placeLight(w, h) end

	frame:ClearAllPoints()
	local a = ANCHORS[anchor] or ANCHORS.ANCHOR_RIGHT
	if anchor == "ANCHOR_CURSOR" and cursorX then
		-- in the box's own units, from the screen's bottom left; flipped where it would
		-- run off the right or the bottom (the clamp would push it under the pointer)
		local s = frame:GetEffectiveScale()
		local cx, cy = cursorX / s, cursorY / s
		local sw = UIParent:GetWidth() * UIParent:GetEffectiveScale() / s
		local left = cx + CURSOR_RIGHT + w > sw
		local up = cy - CURSOR_BELOW - h < 0
		local px = left and (cx - CURSOR_FLIP - w) or (cx + CURSOR_RIGHT)
		local py = up and (cy + CURSOR_FLIP + h) or (cy - CURSOR_BELOW)
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", px, py)
	elseif owner then
		frame:SetPoint(a[1], owner, a[2], anchorX or 0, anchorY or 0)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
	frame:Show()
end
