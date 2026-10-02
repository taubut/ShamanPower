-- ShamanPower_Config :: Core
-- Design tokens, font objects, and drawing primitives.
-- Everything here is built from CreateFrame/CreateTexture only -- no Blizzard
-- templates are used anywhere in this module, which is what keeps the look
-- identical across every flavor from Vanilla through Retail.

local ADDON, ns = ...

local Core = {}
ns.Core = Core
-- rows a page draws with its own code (Window.lua's page packer): [key] = { Render, Release }
ns.CustomRows = ns.CustomRows or {}

-- ---------------------------------------------------------------------------
-- Palette
-- Accent is ShamanPower blue (|cff0070dd), already the brand color used
-- throughout the existing option text.
-- ---------------------------------------------------------------------------
local C = {
	windowBg   = { 0.055, 0.078, 0.118 },
	sidebarBg  = { 0.067, 0.094, 0.137 },
	contentBg  = { 0.078, 0.106, 0.149 },
	rowBg      = { 0.102, 0.133, 0.188 },
	rowHover   = { 0.137, 0.176, 0.239 },
	border     = { 0.169, 0.216, 0.290 },
	borderSoft = { 0.122, 0.157, 0.212 },
	white       = { 1, 1, 1 },   -- button captions, the close X on hover

	accent     = { 0.000, 0.439, 0.867 },
	accentHi   = { 0.247, 0.663, 1.000 },
	accentDim  = { 0.000, 0.439, 0.867, 0.25 },
	-- the help tone (Support Code buttons): WoW's "look here" gold, never an error
	help       = { 1.000, 0.722, 0.110 },
	helpHi     = { 1.000, 0.851, 0.400 },

	text       = { 0.902, 0.918, 0.941 },
	textDim    = { 0.541, 0.580, 0.651 },
	textMute   = { 0.353, 0.392, 0.455 },

	on         = { 0.180, 0.800, 0.443 },
	off        = { 0.320, 0.350, 0.400 },
	warn       = { 0.900, 0.290, 0.290 },

	-- the settings window's navy lights (D32b "Lit by the element"): the header
	-- band (#10141B, lit from #1B2433), the sidebar's light (#171C24) and the
	-- base of a section card's strip (#20252E), each tinted by the page's element
	bandBg       = { 16 / 255, 20 / 255, 27 / 255 },
	bandLight    = { 27 / 255, 36 / 255, 51 / 255 },
	sidebarLight = { 23 / 255, 28 / 255, 36 / 255 },
	stripBg      = { 32 / 255, 37 / 255, 46 / 255 },
}
Core.colors = C

-- t of color a over (1 - t) of color b, as the mockups mix them (a, b: palette
-- keys or {r, g, b}); returns r, g, b
function Core:Mix(a, b, t)
	if type(a) == "string" then a = C[a] end
	if type(b) == "string" then b = C[b] end
	return a[1] * t + b[1] * (1 - t), a[2] * t + b[2] * (1 - t), a[3] * t + b[3] * (1 - t)
end

-- Conditional colour. Core:Color returns four values, and Lua truncates a
-- multi-return call to one value when it sits inside an and/or chain -- so
-- `cond and Core:Color("a") or Core:Color("b")` silently passes a single
-- number to SetColorTexture. Branch on the key instead of the call.
function Core:ColorIf(cond, keyTrue, keyFalse, alphaOverride)
	return self:Color(cond and keyTrue or keyFalse, alphaOverride)
end

function Core:Color(key, alphaOverride)
	local c = C[key]
	if not c then return 1, 1, 1, 1 end
	return c[1], c[2], c[3], alphaOverride or c[4] or 1
end

-- ---------------------------------------------------------------------------
-- Compat shims
-- SetGradient took (orientation, r,g,b,a, r,g,b,a) before 10.0 and
-- (orientation, colorObj, colorObj) after. 2.5.6 predates the change, so probe
-- once at load and route accordingly.
-- ---------------------------------------------------------------------------
-- The probe lives on a throwaway frame of ours, NOT on UIParent. An addon
-- region parented to UIParent sits in Blizzard's own frame for the whole
-- session, and UIParent:Show() is on the path that rebuilds the party frames.
-- There is no reason to put it there for a one-off capability check.
local probeHost = CreateFrame("Frame")
probeHost:Hide()
local probe = probeHost:CreateTexture(nil, "BACKGROUND")
local hasColorObjectGradient = false
if probe.SetGradient and CreateColor then
	hasColorObjectGradient = pcall(function()
		probe:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 1), CreateColor(0, 0, 0, 0))
	end)
end
probe:Hide()

function Core:Gradient(tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
	if hasColorObjectGradient then
		tex:SetGradient(orientation, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
	elseif tex.SetGradientAlpha then
		tex:SetGradientAlpha(orientation, r1, g1, b1, a1, r2, g2, b2, a2)
	end
end

-- ---------------------------------------------------------------------------
-- Fonts
-- Fira Sans from the brand kit (ShamanPowerBrand.lua): SemiBold for the wordmark
-- and titles, Medium for the small-caps labels, Regular for every other word.
-- SP:BrandFontPath gives the game's own font on Chinese and Korean clients
-- (Fira has no letters for them); a font that fails to load falls back to it too.
-- ---------------------------------------------------------------------------
local GAME_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local function FontPath(weight)
	local sp = ShamanPower
	if sp and sp.BrandFontPath then return sp:BrandFontPath(weight) end
	return GAME_FONT
end
local REGULAR, MEDIUM, SEMIBOLD = FontPath("regular"), FontPath("medium"), FontPath("semibold")

local function MakeFont(suffix, path, size, flags, colorKey)
	local f = CreateFont("ShamanPowerConfigFont" .. suffix)
	f:SetFont(path, size, flags)
	if not f:GetFont() then f:SetFont(GAME_FONT, size, flags) end
	f:SetShadowOffset(1, -1)
	f:SetShadowColor(0, 0, 0, 0.8)
	if colorKey then
		f:SetTextColor(Core:Color(colorKey))
	end
	return f
end

Core.fonts = {
	title     = MakeFont("Title",     SEMIBOLD, 22, "", "text"),
	pageTitle = MakeFont("PageTitle", SEMIBOLD, 27, "", "text"),       -- the settings page title in its header band
	wordmark  = MakeFont("Wordmark",  SEMIBOLD, 19, "", "text"),       -- "ShamanPower" beside the sidebar's logo
	tagline   = MakeFont("Tagline",   MEDIUM,    8, "", "textMute"),   -- "TOTEMS, DONE RIGHT" under it
	subtitle  = MakeFont("Sub",       REGULAR,  11, "", "textDim"),
	brand     = MakeFont("Brand",     SEMIBOLD, 16, "", "text"),
	row       = MakeFont("Row",       REGULAR,  12, "", "text"),
	rowDim    = MakeFont("RowDim",    REGULAR,  12, "", "textDim"),
	section   = MakeFont("Section",   MEDIUM,   12, "", "textDim"),
	strip     = MakeFont("Strip",     MEDIUM,   10, "", "textDim"),    -- a section card's name (and its tag)
	nav       = MakeFont("Nav",       REGULAR,  12, "", "textDim"),
	navOn     = MakeFont("NavOn",     REGULAR,  12, "", "text"),
	group     = MakeFont("Group",     MEDIUM,   10, "", "accentHi"),
	tiny      = MakeFont("Tiny",      MEDIUM,   10, "", "textMute"),
	small     = MakeFont("Small",     REGULAR,  10, "", "textDim"),    -- small readouts (the CPU line)
	link      = MakeFont("Link",      REGULAR,  11, "", "text"),       -- the footer's link buttons
	button    = MakeFont("Button",    REGULAR,  12, "", "text"),
}

-- ---------------------------------------------------------------------------
-- Drawing primitives
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Background opacity
-- Panel backgrounds and row cards register here so one profile setting can
-- fade them together. Borders, inputs, popups, icons and text never register,
-- which keeps edges and labels crisp at low opacity.
-- ---------------------------------------------------------------------------
Core.opacity = 1
local fadeRegistry = setmetatable({}, { __mode = "k" })

-- One registered background at the current opacity. An entry is a palette key
-- (info.key), a color of its own (info.r/g/b: an element's tint), a light (a
-- texture file tinted by vertex color, info.light) or a whole region's alpha
-- (info.whole: the faint totem graphic).
local function PaintFade(tex, info, o)
	if info.whole then
		tex:SetAlpha(info.alpha * o)
		return
	end
	local r, g, b
	if info.key then r, g, b = Core:Color(info.key) else r, g, b = info.r, info.g, info.b end
	if info.light then
		tex:SetVertexColor(r, g, b, info.alpha * o)
	else
		tex:SetColorTexture(r, g, b, info.alpha * o)
	end
end

function Core:RegisterFade(tex, colorKey, baseAlpha)
	local info = { key = colorKey, alpha = baseAlpha or 1 }
	fadeRegistry[tex] = info
	PaintFade(tex, info, self.opacity)
end

-- a background in a color of its own (r, g, b 0-1); Core:SetFadeColor repaints it
function Core:RegisterFadeRGB(tex, r, g, b, baseAlpha)
	local info = { r = r, g = g, b = b, alpha = baseAlpha or 1 }
	fadeRegistry[tex] = info
	PaintFade(tex, info, self.opacity)
end

-- a light (a texture file such as the radial light): its vertex color and alpha fade
function Core:RegisterFadeLight(tex, r, g, b, baseAlpha)
	local info = { r = r, g = g, b = b, alpha = baseAlpha or 1, light = true }
	fadeRegistry[tex] = info
	PaintFade(tex, info, self.opacity)
end

-- a whole region or frame (SetAlpha), e.g. a faint picture behind a header
function Core:RegisterFadeAlpha(region, baseAlpha)
	local info = { alpha = baseAlpha or 1, whole = true }
	fadeRegistry[region] = info
	PaintFade(region, info, self.opacity)
end

-- Change a registered background: a new color (r, g, b) and/or base alpha.
function Core:SetFadeColor(tex, r, g, b, baseAlpha)
	local info = fadeRegistry[tex]
	if not info then return end
	if r then info.key, info.r, info.g, info.b = nil, r, g, b end
	if baseAlpha then info.alpha = baseAlpha end
	PaintFade(tex, info, self.opacity)
end

-- Only the base alpha (0 hides a row card inside a section card).
function Core:SetFadeAlpha(tex, baseAlpha)
	local info = fadeRegistry[tex]
	if not info then return end
	info.alpha = baseAlpha
	PaintFade(tex, info, self.opacity)
end

-- Repaint one registered background as registered (a row's hover ending).
function Core:RepaintFade(tex)
	local info = fadeRegistry[tex]
	if info then PaintFade(tex, info, self.opacity) return true end
	return false
end

function Core:ApplyOpacity(o)
	o = tonumber(o) or 1
	if o < 0.1 then o = 0.1 elseif o > 1 then o = 1 end
	self.opacity = o
	for tex, info in pairs(fadeRegistry) do
		PaintFade(tex, info, o)
	end
end

-- Pull the profile value and repaint only if it differs from what is drawn.
function Core:SyncOpacity()
	local opt = ShamanPower and ShamanPower.opt
	local o = opt and opt.uiOpacity or 1
	if math.abs(o - self.opacity) > 0.001 then
		self:ApplyOpacity(o)
	end
end

-- ---------------------------------------------------------------------------
-- No color (D42): a module that is off shows its settings page in plain grays.
-- Core:MonoWatch(root) makes every region under root remember the colors it is
-- painted with: its paint calls (SetColorTexture, SetVertexColor, the gradients,
-- SetDesaturated, SetTexture, SetTextColor, SetFontObject, SetText) go through
-- a small wrapper set once per region. Core:MonoSet(root) repaints them all in a
-- gray of the same lightness, and every later paint (a hover, a refresh) stays
-- gray; Core:MonoClear() gives every region its own colors back. Pictures
-- (texture files) are desaturated; color codes in text turn gray too. A frame in
-- Core.monoSkip keeps its colors (the footer, Turn On). Nothing runs unless a
-- page is drawn while its module is off.
-- ---------------------------------------------------------------------------
local monoOn = setmetatable({}, { __mode = "k" })     -- [region] = true while it is gray
Core.monoSkip = setmetatable({}, { __mode = "k" })    -- [frame] = true: never grayed
local monoOrig = {}                                   -- [object type] = { method = the game's own }
local MONO_TEX = { "SetColorTexture", "SetTexture", "SetVertexColor", "SetDesaturated", "SetGradient", "SetGradientAlpha" }
local MONO_FS = { "SetTextColor", "SetFontObject", "SetText" }

local function Lum(r, g, b) return (r or 0) * 0.299 + (g or 0) * 0.587 + (b or 0) * 0.114 end
local function O(self, name) return monoOrig[self.spMonoType][name] end

-- a color code |cAARRGGBB in the same lightness of gray
local function GrayCode(a, r, g, b)
	local l = math.floor(Lum(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)) + 0.5)
	return string.format("|c%s%02x%02x%02x", a, l, l, l)
end
local function GrayText(s)
	if type(s) ~= "string" or not s:find("|c", 1, true) then return s end
	return (s:gsub("|c(%x%x)(%x%x)(%x%x)(%x%x)", GrayCode))
end

local function GrayGradient(self, method, orient, ...)
	local n = select("#", ...)
	if method == "SetGradient" and type((...)) == "table" then   -- (orientation, color, color)
		local c1, c2 = ...
		local r1, g1, b1, a1 = c1:GetRGBA()
		local r2, g2, b2, a2 = c2:GetRGBA()
		local l1, l2 = Lum(r1, g1, b1), Lum(r2, g2, b2)
		return O(self, method)(self, orient, CreateColor(l1, l1, l1, a1), CreateColor(l2, l2, l2, a2))
	end
	if method == "SetGradientAlpha" or n == 8 then   -- (orientation, r, g, b, a, r, g, b, a)
		local r1, g1, b1, a1, r2, g2, b2, a2 = ...
		local l1, l2 = Lum(r1, g1, b1), Lum(r2, g2, b2)
		return O(self, method)(self, orient, l1, l1, l1, a1, l2, l2, l2, a2)
	end
	local r1, g1, b1, r2, g2, b2 = ...   -- (orientation, r, g, b, r, g, b)
	local l1, l2 = Lum(r1, g1, b1), Lum(r2, g2, b2)
	return O(self, method)(self, orient, l1, l1, l1, l2, l2, l2)
end

local W = {}
function W.SetColorTexture(self, r, g, b, a)
	local q = self.spMonoQ
	q.kind, q.r, q.g, q.b, q.a = "color", r, g, b, a
	if monoOn[self] then local l = Lum(r, g, b) return O(self, "SetColorTexture")(self, l, l, l, a) end
	return O(self, "SetColorTexture")(self, r, g, b, a)
end
function W.SetTexture(self, ...)
	self.spMonoQ.kind = "file"
	local res = O(self, "SetTexture")(self, ...)
	if monoOn[self] then O(self, "SetDesaturated")(self, true) end
	return res
end
function W.SetVertexColor(self, r, g, b, a)
	local q = self.spMonoQ
	q.vr, q.vg, q.vb, q.va, q.grad = r, g, b, a, nil   -- (a tint replaces a gradient)
	if monoOn[self] then
		q.vtouched = true
		local l = Lum(r, g, b)
		return O(self, "SetVertexColor")(self, l, l, l, a)
	end
	return O(self, "SetVertexColor")(self, r, g, b, a)
end
function W.SetDesaturated(self, on)
	self.spMonoQ.desat = on and true or false
	if monoOn[self] then on = true end
	return O(self, "SetDesaturated")(self, on)
end
function W.SetGradient(self, orient, ...)
	local q = self.spMonoQ
	q.grad, q.vr, q.vtouched = { "SetGradient", orient, ... }, nil, nil   -- (a gradient replaces a tint)
	if monoOn[self] then return GrayGradient(self, "SetGradient", orient, ...) end
	return O(self, "SetGradient")(self, orient, ...)
end
function W.SetGradientAlpha(self, orient, ...)
	local q = self.spMonoQ
	q.grad, q.vr, q.vtouched = { "SetGradientAlpha", orient, ... }, nil, nil
	if monoOn[self] then return GrayGradient(self, "SetGradientAlpha", orient, ...) end
	return O(self, "SetGradientAlpha")(self, orient, ...)
end
function W.SetTextColor(self, r, g, b, a)
	local q = self.spMonoQ
	q.tr, q.tg, q.tb, q.ta, q.tset = r, g, b, a, true
	if monoOn[self] then local l = Lum(r, g, b) return O(self, "SetTextColor")(self, l, l, l, a) end
	return O(self, "SetTextColor")(self, r, g, b, a)
end
function W.SetFontObject(self, font)
	local res = O(self, "SetFontObject")(self, font)
	self.spMonoQ.tset = nil   -- the font's own color now
	if monoOn[self] then
		local r, g, b, a = self:GetTextColor()
		local l = Lum(r, g, b)
		O(self, "SetTextColor")(self, l, l, l, a)
	end
	return res
end
function W.SetText(self, text)
	self.spMonoQ.str = text
	if monoOn[self] then return O(self, "SetText")(self, GrayText(text)) end
	return O(self, "SetText")(self, text)
end

-- the first paint, made before the wrapper (Core's own drawing notes it)
local function Note(tex, r, g, b, a)
	local q = tex.spMonoQ
	if q then q.kind, q.r, q.g, q.b, q.a = "color", r, g, b, a else tex.spMonoNote = { r, g, b, a } end
end
Core.MonoNote = function(_, tex, r, g, b, a) Note(tex, r, g, b, a) end

local function Watch(region)
	if region.spMonoQ then return end
	local ot = region.GetObjectType and region:GetObjectType()
	local names = (ot == "Texture" or ot == "Line") and MONO_TEX or (ot == "FontString" and MONO_FS) or nil
	if not names then return end
	local orig = monoOrig[ot]
	if not orig then
		orig = {}
		for _, name in ipairs(names) do orig[name] = region[name] end   -- the game's own, before any wrapper
		monoOrig[ot] = orig
	end
	region.spMonoType = ot
	local q = {}
	local note = region.spMonoNote
	if note then q.kind, q.r, q.g, q.b, q.a = "color", note[1], note[2], note[3], note[4]; region.spMonoNote = nil end
	region.spMonoQ = q
	for _, name in ipairs(names) do
		if orig[name] then region[name] = W[name] end
	end
end

-- Every region under root (frames in Core.monoSkip and theirs left out).
local function Walk(frame, fn)
	if Core.monoSkip[frame] then return end
	local regions = { frame:GetRegions() }
	for i = 1, #regions do fn(regions[i]) end
	local children = { frame:GetChildren() }
	for i = 1, #children do Walk(children[i], fn) end
end

function Core:MonoWatch(root)
	if root then Walk(root, Watch) end
end

-- one region in gray (on) or its own colors again
local function Call(region, name, ...)
	local f = O(region, name)
	if f then return f(region, ...) end
end
local function MonoPaint(region, on)
	local q = region.spMonoQ
	if not q then return end
	if region.spMonoType == "FontString" then
		if not q.tset and on then q.tr, q.tg, q.tb, q.ta = region:GetTextColor(); q.tset = true end
		if q.str == nil then q.str = region:GetText() end
		local coded = type(q.str) == "string" and q.str:find("|c", 1, true)
		if on then
			local l = Lum(q.tr, q.tg, q.tb)
			Call(region, "SetTextColor", l, l, l, q.ta)
			if coded then Call(region, "SetText", GrayText(q.str)) end
		else
			if q.tset then Call(region, "SetTextColor", q.tr, q.tg, q.tb, q.ta) end
			if coded then Call(region, "SetText", q.str) end
		end
		return
	end
	-- a texture or a line
	if q.kind == nil then q.kind = (region.GetTexture and region:GetTexture() ~= nil) and "file" or "unknown" end
	if q.desat == nil then q.desat = (region.IsDesaturated and region:IsDesaturated()) and true or false end
	-- (only a tint painted through the wrapper is known: one read back off a gradient
	-- would flatten the gradient when it is put back)
	if on then
		if q.kind == "color" then
			local l = Lum(q.r, q.g, q.b)
			Call(region, "SetColorTexture", l, l, l, q.a)
		else
			Call(region, "SetDesaturated", true)   -- a picture (or a color painted before the wrapper)
		end
		if q.vr and not (q.vr == q.vg and q.vg == q.vb) and not q.grad then
			local l = Lum(q.vr, q.vg, q.vb)
			Call(region, "SetVertexColor", l, l, l, q.va)
			q.vtouched = true
		end
		if q.grad and O(region, q.grad[1]) then GrayGradient(region, q.grad[1], unpack(q.grad, 2)) end
	else
		if q.kind == "color" then Call(region, "SetColorTexture", q.r, q.g, q.b, q.a) end
		Call(region, "SetDesaturated", q.desat)
		if q.vtouched and q.vr then Call(region, "SetVertexColor", q.vr, q.vg, q.vb, q.va) end
		q.vtouched = nil
		if q.grad then Call(region, q.grad[1], unpack(q.grad, 2)) end
	end
end

-- every watched region under root in gray (it stays gray until Core:MonoClear)
function Core:MonoSet(root)
	if not root then return end
	Walk(root, function(region)
		Watch(region)
		if region.spMonoQ and not monoOn[region] then
			monoOn[region] = true
			MonoPaint(region, true)
		end
	end)
end

-- every gray region gets its own colors back
function Core:MonoClear()
	if next(monoOn) == nil then return end
	local list = {}
	for region in pairs(monoOn) do list[#list + 1] = region end
	for i = 1, #list do
		monoOn[list[i]] = nil
		MonoPaint(list[i], false)
	end
end

function Core:MonoActive() return next(monoOn) ~= nil end

-- Flat filled texture pinned to a region. Pass fade=true for panel
-- backgrounds that should follow the opacity setting.
function Core:SolidTex(parent, colorKey, layer, alpha, fade)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetAllPoints(parent)
	if fade then
		self:RegisterFade(t, colorKey, alpha or 1)
	else
		t:SetColorTexture(self:Color(colorKey, alpha))
		Note(t, self:Color(colorKey, alpha))
	end
	return t
end

-- 1px border drawn as four edge textures. Cheaper and sharper than a backdrop,
-- and sidesteps BackdropTemplate differences between flavors entirely.
function Core:MakeBorder(frame, colorKey, thickness, inset)
	thickness = thickness or 1
	inset = inset or 0
	local r, g, b, a = self:Color(colorKey or "border")
	local edges = {}
	local sides = {
		top    = { "TOPLEFT",    inset, -inset, "TOPRIGHT",     -inset, -inset, nil, thickness },
		bottom = { "BOTTOMLEFT", inset,  inset, "BOTTOMRIGHT",  -inset,  inset, nil, thickness },
		left   = { "TOPLEFT",    inset, -inset, "BOTTOMLEFT",    inset,  inset, thickness, nil },
		right  = { "TOPRIGHT",  -inset, -inset, "BOTTOMRIGHT",  -inset,  inset, thickness, nil },
	}
	for name, s in pairs(sides) do
		local t = frame:CreateTexture(nil, "BORDER")
		t:SetColorTexture(r, g, b, a)
		Note(t, r, g, b, a)
		t:SetPoint(s[1], frame, s[1], s[2], s[3])
		t:SetPoint(s[4], frame, s[4], s[5], s[6])
		if s[7] then t:SetWidth(s[7]) end
		if s[8] then t:SetHeight(s[8]) end
		edges[name] = t
	end
	frame.spBorder = edges
	return edges
end

function Core:SetBorderColor(frame, colorKey, alpha)
	if not frame.spBorder then return end
	local r, g, b, a = self:Color(colorKey, alpha)
	for _, t in pairs(frame.spBorder) do
		t:SetColorTexture(r, g, b, a)
		if not t.spMonoQ then Note(t, r, g, b, a) end
	end
end

-- Card background used by every settings row.
function Core:RowBg(frame)
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(frame)
	self:RegisterFade(bg, "rowBg", 1)
	frame.spBg = bg
	self:MakeBorder(frame, "borderSoft")
	return bg
end

function Core:HoverHighlight(frame)
	frame:SetScript("OnEnter", function(self)
		if self.spBg then self.spBg:SetColorTexture(Core:Color("rowHover", Core.opacity)) end
		if self.spOnEnter then self:spOnEnter() end
	end)
	frame:SetScript("OnLeave", function(self)
		-- back to the card as registered (see-through inside a section card)
		if self.spBg and not Core:RepaintFade(self.spBg) then self.spBg:SetColorTexture(Core:Color("rowBg", Core.opacity)) end
		if self.spOnLeave then self:spOnLeave() end
	end)
end

-- Horizontal accent glow used under the page header.
function Core:AccentGlow(parent, height)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetHeight(height or 2)
	t:SetColorTexture(1, 1, 1, 1)
	local r, g, b = self:Color("accentHi")
	self:Gradient(t, "HORIZONTAL", r, g, b, 0, r, g, b, 0.9)
	return t
end

-- ---------------------------------------------------------------------------
-- The "lit" look's soft lights (D32b): the brand kit's white radial light
-- (SP:BrandRadialLight), placed like the mockups' radial(): over a host area
-- w x h it is centered at (cx * w, cy * h) from the host's top-left and has faded
-- out r / 1.6 of the width across and r of the height down. The texture falls
-- off a little faster than the mock's curve, so it is drawn LIGHT_REACH times
-- larger (fitted to the mock's 1 - d^1.3). Only the part inside the host is
-- drawn (its texture coordinates are cut to it), so nothing spills past the
-- host. Tint it with Core:RegisterFadeLight (the color at its center).
-- ---------------------------------------------------------------------------
local LIGHT_REACH = 1.16
function Core:PlaceLight(tex, host, w, h, cx, cy, r)
	local hx, hy = (r / 1.6) * w * LIGHT_REACH, r * h * LIGHT_REACH
	local px, py = cx * w, cy * h
	local x0, x1 = math.max(0, px - hx), math.min(w, px + hx)
	local y0, y1 = math.max(0, py - hy), math.min(h, py + hy)
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", host, "TOPLEFT", x0, -y0)
	tex:SetSize(x1 - x0, y1 - y0)
	local left, top = px - hx, py - hy
	tex:SetTexCoord((x0 - left) / (2 * hx), (x1 - left) / (2 * hx), (y0 - top) / (2 * hy), (y1 - top) / (2 * hy))
end

function Core:Light(host, w, h, cx, cy, r, sublevel)
	local sp = ShamanPower
	local tex
	if sp and sp.BrandRadialLight then
		tex = sp:BrandRadialLight(host, "BACKGROUND", sublevel or 1)
	else
		tex = host:CreateTexture(nil, "BACKGROUND", nil, sublevel or 1)
		tex:SetColorTexture(0, 0, 0, 0)   -- no brand file: no light, the plain background stays
	end
	self:PlaceLight(tex, host, w, h, cx, cy, r)
	return tex
end

-- ---------------------------------------------------------------------------
-- Tooltips (D34): ShamanPower's own tooltip (SP.Tooltip, ShamanPowerTooltip.lua)
-- in every window of ours, lit by the page's or window's element.
-- ---------------------------------------------------------------------------
-- WoW's own box when the core's tooltip is missing (a new file: an update before
-- a full restart): the same calls, the click and path lines as plain lines
local plainTip = {}
for _, method in ipairs({ "SetOwner", "SetText", "AddLine", "AddDoubleLine", "ClearLines", "Show", "Hide",
	"IsShown", "IsOwned", "GetOwner", "NumLines" }) do
	plainTip[method] = function(_, ...) return GameTooltip[method](GameTooltip, ...) end
end
-- as these windows always drew it: a white title, wrapped light gray lines
function plainTip.SetText(_, t, r, g, b) GameTooltip:SetText(t, r or 1, g or 1, b or 1, 1, true) end
function plainTip.AddLine(_, t, r, g, b)
	if GameTooltip:NumLines() == 0 then GameTooltip:AddLine(t, r or 1, g or 1, b or 1, true)
	else GameTooltip:AddLine(t, r or 0.8, g or 0.8, b or 0.8, true) end
end
function plainTip.AddHint(_, text) GameTooltip:AddLine(text, 0.7, 0.7, 0.7, true) end
function plainTip.AddPath(_, text) GameTooltip:AddLine(text, 0.247, 0.663, 0.961, true) end
function plainTip.SetElement() end

function Core:Tooltip()
	local sp = ShamanPower
	return (sp and sp.Tooltip) or plainTip
end

-- Safe to call repeatedly on the same frame: the hooks are installed exactly
-- once and read spTipTitle/spTipBody at hover time, so a pooled frame that is
-- reconfigured for a different option just gets its fields overwritten.
-- (HookScript accumulates handlers, so hooking on every call would stack one
-- tooltip per reuse.) Passing nil for both clears the tooltip.
-- spTipHint: what a click does (small gray caps; "\n" between lines);
-- spTipPath: where the setting lives, only on a row reached through search.
local function TipOnEnter(self)
	local title = self.spTipTitle
	local body  = self.spTipBody
	if title == "" then title = nil end
	if body == "" then body = nil end
	if not title and not body then return end
	local tip = Core:Tooltip()
	-- at the mouse: a row runs the page's full width, so beside it would open by the
	-- window's edge, far from what the pointer is on
	tip:SetOwner(self, "ANCHOR_CURSOR")
	if title then tip:AddLine(title) end
	if body then tip:AddLine(body) end
	if self.spTipHint then tip:AddHint(self.spTipHint) end
	if self.spTipPath then tip:AddPath(self.spTipPath) end
	tip:Show()
end

local function TipOnLeave(self)
	local tip = Core:Tooltip()
	if tip:IsOwned(self) then tip:Hide() end
end

function Core:AttachTooltip(frame, titleText, bodyText, hintText, pathText)
	frame.spTipTitle = titleText
	frame.spTipBody = bodyText
	frame.spTipHint = hintText
	frame.spTipPath = pathText
	if frame.spTipHooked then return end
	if not titleText and not bodyText then return end
	frame.spTipHooked = true
	frame:HookScript("OnEnter", TipOnEnter)
	frame:HookScript("OnLeave", TipOnLeave)
end

-- A control inside a row (a button, switch, slider, swatch or text box) takes
-- the mouse from the row, so the row's tooltip showed only on the row's edges.
-- Hooked once when the pooled control is made; the row's text is read on hover.
function Core:ForwardTooltip(child, row)
	if child.spTipForwarded then return end
	child.spTipForwarded = true
	child:HookScript("OnEnter", function() TipOnEnter(row) end)
	child:HookScript("OnLeave", function() TipOnLeave(row) end)
end

-- Drop the tooltip if it is currently showing for this frame (a hovered row
-- that gets released back to its pool never receives OnLeave).
function Core:HideTooltipFor(frame)
	local tip = self:Tooltip()
	if tip:IsOwned(frame) then tip:Hide() end
end

-- ---------------------------------------------------------------------------
-- Label clamping
-- Long localized labels must not run under the control cluster on the right.
-- Truncate with an ellipsis and expose the full string on hover.
-- ---------------------------------------------------------------------------
function Core:ClampLabel(fontString, maxWidth, fullText)
	if not fontString or not maxWidth or maxWidth <= 0 then return end
	fontString:SetText(fullText)
	if fontString:GetStringWidth() <= maxWidth then
		fontString.spTruncated = false
		return
	end
	local lo, hi = 1, #fullText
	while lo < hi do
		local mid = math.floor((lo + hi) / 2) + 1
		fontString:SetText(string.sub(fullText, 1, mid) .. "...")
		if fontString:GetStringWidth() <= maxWidth then lo = mid else hi = mid - 1 end
	end
	fontString:SetText(string.sub(fullText, 1, lo) .. "...")
	fontString.spTruncated = true
end

-- ---------------------------------------------------------------------------
-- Scrollbar
-- A thin track + thumb for a ScrollFrame, drawn from primitives. Shows only
-- when the scroll child is taller than the viewport; the thumb is draggable
-- and clicking the track pages toward the click. Follows wheel scrolling
-- through the ScrollFrame's own OnVerticalScroll / OnScrollRangeChanged.
-- ---------------------------------------------------------------------------
function Core:AttachScrollbar(scroll, child, opts)
	opts = opts or {}
	local width  = opts.width or 4
	local offset = opts.offset or 6      -- gap between viewport edge and track
	local minThumb = 24

	local track = CreateFrame("Button", nil, scroll:GetParent())
	track:SetWidth(width)
	track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", offset + width, -2)
	track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", offset + width, 2)
	track:SetFrameLevel(scroll:GetFrameLevel() + 5)
	track.bg = track:CreateTexture(nil, "BACKGROUND")
	track.bg:SetAllPoints(track)
	track.bg:SetColorTexture(self:Color("border", 0.5))
	track:Hide()

	local thumb = CreateFrame("Button", nil, track)
	thumb:SetWidth(width)
	thumb:SetPoint("TOP", track, "TOP", 0, 0)
	thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
	thumb.tex:SetAllPoints(thumb)
	thumb.tex:SetColorTexture(self:Color("textMute"))
	-- Wider hit area than the 4px visual so it is easy to grab.
	thumb:SetHitRectInsets(-6, -6, 0, 0)
	track:SetHitRectInsets(-6, -6, 0, 0)

	local function Range()
		local viewH = scroll:GetHeight()
		local contentH = child:GetHeight()
		return viewH, contentH, math.max(0, contentH - viewH)
	end

	local function Update()
		local viewH, contentH, maxScroll = Range()
		if maxScroll <= 1 or viewH <= 0 then track:Hide() return end
		track:Show()
		local trackH = track:GetHeight()
		local thumbH = math.max(minThumb, math.floor(trackH * (viewH / contentH)))
		if thumbH > trackH then thumbH = trackH end
		thumb:SetHeight(thumbH)
		local frac = scroll:GetVerticalScroll() / maxScroll
		if frac > 1 then frac = 1 elseif frac < 0 then frac = 0 end
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", track, "TOP", 0, -math.floor((trackH - thumbH) * frac))
	end

	local function ScrollToFraction(frac)
		local _, _, maxScroll = Range()
		if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
		scroll:SetVerticalScroll(maxScroll * frac)
	end

	-- Follow the scroll frame itself, whatever moved it (wheel, code, drag).
	scroll:HookScript("OnVerticalScroll", Update)
	scroll:HookScript("OnScrollRangeChanged", Update)
	scroll:HookScript("OnSizeChanged", Update)
	scroll:HookScript("OnShow", Update)

	-- Thumb drag: keep the grab point under the cursor.
	local dragging, grabOffset = false, 0
	local function CursorY()
		local _, y = GetCursorPosition()
		return y / track:GetEffectiveScale()
	end
	thumb:SetScript("OnMouseDown", function(self)
		dragging = true
		grabOffset = self:GetTop() - CursorY()
		self.tex:SetColorTexture(Core:Color("accentHi"))
	end)
	thumb:SetScript("OnMouseUp", function(self)
		dragging = false
		self.tex:SetColorTexture(Core:Color(self:IsMouseOver() and "accent" or "textMute"))
	end)
	thumb:SetScript("OnEnter", function(self) if not dragging then self.tex:SetColorTexture(Core:Color("accent")) end end)
	thumb:SetScript("OnLeave", function(self) if not dragging then self.tex:SetColorTexture(Core:Color("textMute")) end end)
	thumb:SetScript("OnUpdate", function(self)
		if not dragging then return end
		if not IsMouseButtonDown("LeftButton") then
			dragging = false
			self.tex:SetColorTexture(Core:Color("textMute"))
			return
		end
		local trackH, thumbH = track:GetHeight(), self:GetHeight()
		local travel = trackH - thumbH
		if travel <= 0 then return end
		local topWanted = CursorY() + grabOffset
		local frac = (track:GetTop() - topWanted) / travel
		ScrollToFraction(frac)
	end)

	-- Click on the track (outside the thumb): page toward the click.
	track:SetScript("OnClick", function(self)
		local y = CursorY()
		local viewH, _, maxScroll = Range()
		if maxScroll <= 0 then return end
		local cur = scroll:GetVerticalScroll()
		if y > thumb:GetTop() then
			scroll:SetVerticalScroll(math.max(0, cur - viewH))
		elseif y < thumb:GetBottom() then
			scroll:SetVerticalScroll(math.min(maxScroll, cur + viewH))
		end
	end)
	-- Wheel over the bar behaves like wheel over the content.
	track:EnableMouseWheel(true)
	track:SetScript("OnMouseWheel", function(_, delta)
		local h = scroll:GetScript("OnMouseWheel")
		if h then h(scroll, delta) end
	end)

	scroll.spScrollbar = track
	scroll.spScrollbarUpdate = Update
	return track
end

-- ---------------------------------------------------------------------------
-- Buttons and dialog chrome
-- Shared by every window in the module so they all look like one product.
-- ---------------------------------------------------------------------------
-- The button look (every button in the settings, the tour and the dialogs):
-- a flat blue base (b.bg - stronger for the primary / main action; callers
-- may recolour it) with depth drawn over it: a soft vertical shade, a lit top
-- edge and a shadowed bottom edge. The border lights up on hover and a press
-- pushes it in (the top edge goes dark and the caption drops a pixel). Hover
-- and leave are SetScript, so a caller's own OnEnter/OnLeave replaces them;
-- the press uses OnMouseDown/Up and is kept. caption: the button's text, if
-- any (it takes the text color for the style). tone "help": the same button
-- in gold (the Support Code buttons); b.spTone can change it later (pooled rows
-- set it, then call b.spPaint).
function Core:BevelButton(b, primary, caption, tone)
	local bg = b.bg or b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(b)
	local shade = b:CreateTexture(nil, "BACKGROUND", nil, 1)
	shade:SetAllPoints(b)
	shade:SetColorTexture(1, 1, 1, 1)
	self:Gradient(shade, "VERTICAL", 0, 0, 0, 0.24, 1, 1, 1, 0.06)   -- bottom darker, top lighter
	local hi = b:CreateTexture(nil, "ARTWORK")
	hi:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
	hi:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
	hi:SetHeight(1)
	local lo = b:CreateTexture(nil, "ARTWORK")
	lo:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1)
	lo:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
	lo:SetHeight(1)
	lo:SetColorTexture(0, 0, 0, 0.35)
	local down = b:CreateTexture(nil, "ARTWORK", nil, 1)
	down:SetAllPoints(b)
	down:SetColorTexture(0, 0, 0, 0.22)
	down:Hide()
	if not b.spBorder then self:MakeBorder(b, "accent") end
	if caption then caption:SetTextColor(self:Color("white")) end
	-- blue for every button; the primary (main action) a stronger blue; the help tone gold
	b.spTone = tone
	local function paint(hover)
		if b.spTone == "help" then
			bg:SetColorTexture(Core:Color("help", hover and 0.56 or 0.40))
			hi:SetColorTexture(Core:Color("helpHi", 0.45))
			Core:SetBorderColor(b, hover and "helpHi" or "help")
			return
		end
		if primary then
			bg:SetColorTexture(Core:Color("accent", hover and 0.62 or 0.46))
		else
			bg:SetColorTexture(Core:Color("accent", hover and 0.46 or 0.28))
		end
		hi:SetColorTexture(Core:Color("accentHi", primary and 0.45 or 0.35))
		Core:SetBorderColor(b, hover and "accentHi" or "accent")
	end
	paint(false)
	-- the press drops the caption a pixel from wherever its caller anchored it (its
	-- first point, read at the press), and puts it back exactly on release
	local held
	local function release()
		down:Hide(); hi:Show()
		if held then
			caption:SetPoint(held[1], held[2], held[3], held[4], held[5])
			held = nil
		end
	end
	b:SetScript("OnEnter", function() paint(true) end)
	b:SetScript("OnLeave", function() paint(false) end)
	b:SetScript("OnMouseDown", function(self)
		if self.IsEnabled and not self:IsEnabled() then return end
		down:Show(); hi:Hide()
		if caption and not held then
			local p, rel, rp, x, y = caption:GetPoint(1)
			if p then
				held = { p, rel, rp, x or 0, y or 0 }
				caption:SetPoint(p, rel, rp, x or 0, (y or 0) - 1)
			end
		end
	end)
	b:SetScript("OnMouseUp", release)
	b:HookScript("OnHide", release)
	b.bg, b.spPaint = bg, paint
	return b
end

function Core:MakeButton(parent, text, width, primary, tone)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(26)
	local t = b:CreateFontString(nil, "OVERLAY")
	t:SetFontObject(self.fonts.button)
	t:SetPoint("CENTER")
	t:SetText(text)
	b:SetWidth(math.max(width or 0, t:GetStringWidth() + 28))
	self:BevelButton(b, primary, t, tone)
	b.text = t
	return b
end

-- The close X of every window: a drawn X (two 2px lines, text colour), no box; on hover it
-- becomes a solid red square with a white X, darker while pressed.
function Core:CloseButton(parent, size)
	size = size or 22
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(b)
	bg:SetColorTexture(self:Color("warn"))
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
		if state == "down" then bg:SetColorTexture(0.62, 0.18, 0.18) else bg:SetColorTexture(Core:Color("warn")) end
		local cr, cg, cb = Core:Color(state == "normal" and "text" or "white")
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

-- Ask for a UI reload.
--
-- On the Mainline/Forever line C_UI.Reload is PROTECTED: an addon calling it
-- from its own OnClick is refused outright with "Interface action failed
-- because of an AddOn" and no Lua error at all, so the button silently does
-- nothing. The client's own API docs do not flag it as protected; we found it
-- because ADDON_ACTION_BLOCKED names the function.
--
-- A SecureActionButtonTemplate running the /reload macro does work, because
-- the player's own click supplies the hardware event and the macro runs
-- untainted. So on that client we put up a small dialog whose single button is
-- exactly that, instead of reloading for them.
--
-- One mechanism for every reload path in the addon, so nothing calls ReloadUI
-- directly any more.
local reloadDlg

function Core:RequestReload(reason)
	-- Classic line: the direct call has always worked, keep it instant.
	if not SPCompat.FOREVER then
		ReloadUI()
		return
	end

	if not reloadDlg then
		local f = self:CreateDialog({
			name = "ShamanPowerReloadPrompt", width = 430, height = 168,
			title = "One more click", footer = 46, special = true, strata = "FULLSCREEN_DIALOG",
		})
		local t = f.body:CreateFontString(nil, "OVERLAY")
		t:SetFontObject(self.fonts.row)
		t:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -2)
		t:SetWidth(390); t:SetJustifyH("LEFT"); t:SetWordWrap(true)
		f.text = t

		-- The secure button IS the reload. It cannot be created in combat, and
		-- its attributes cannot be changed in combat either, so build it once
		-- here and never touch the attributes again.
		local okSecure, s = pcall(CreateFrame, "Button", nil, f, "SecureActionButtonTemplate")
		if okSecure and s then
			s:SetSize(150, 26)
			s:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
			s:RegisterForClicks("AnyUp", "AnyDown")   -- ActionButtonUseKeyDown gates one edge
			s:SetAttribute("type", "macro")
			s:SetAttribute("macrotext", "/reload")
			local st = s:CreateFontString(nil, "OVERLAY")
			st:SetFontObject(self.fonts.button)
			st:SetPoint("CENTER")
			st:SetText("Reload now")
			self:BevelButton(s, true, st)
			f.secureBtn = s
		end

		local later = self:MakeButton(f, "Later", 100, false)
		later:SetPoint("RIGHT", f.secureBtn or f, "LEFT", -8, 0)
		later:SetScript("OnClick", function() f:Hide() end)
		reloadDlg = f
	end

	reloadDlg.text:SetText((reason and (reason .. "\n\n") or "")
		.. "Click Reload now to finish. "
		.. "|cff808080You can also type |cffFFD100/reload|r|cff808080.|r")
	reloadDlg:Show()
end

-- The wordmark lockup (D32; the graphic comes only from ShamanPowerBrand.lua): the
-- totem graphic beside the name, "Shaman" in logo blue and "Power" in white, as in
-- the settings sidebar (a 46 px wide graphic beside a 19 pt wordmark, its top 14
-- above the name's middle, 8 between them), scaled to a title's font size.
--   Core:Lockup(parent, size, text) -> graphic, width, gap, name
--   graphic: a sized Frame on parent for the caller to place (nil without the brand
--   kit, which loads only after a full restart: the name then stands alone); width
--   and gap: 0 without it; name: text with every "ShamanPower" in the wordmark's colors.
Core.wordmark = "|cff3FA9F5Shaman|r|cffFFFFFFPower|r"
function Core:Lockup(parent, size, text)
	local name = text and (text:gsub("ShamanPower", self.wordmark)) or nil
	local sp = ShamanPower
	if not (parent and sp and sp.CreateTotemGraphic) then return nil, 0, 0, name end
	local k = (size or 16) / 19
	local graphic = sp:CreateTotemGraphic(parent)
	graphic:SetGraphicHeight(46 * k * 682 / 650)   -- 46 * k wide
	return graphic, 46 * k, 8 * k, name
end

-- A window shell in the settings window's look (D32b "lit by the element"): a dark
-- panel with the soft 1.5px edge and the four elements along its top, a header band
-- (sidebarBg lit from its top left by the window's element, a 1px line along its
-- bottom) holding the title, the subtitle and the element's 44 x 3 underline, a
-- close button, drag-anywhere, toplevel, optional Escape-to-close. Returns the
-- frame; content goes in frame.body, which spans from under the header to
-- opts.footer pixels above the bottom.
--   opts = { name, width, height, title, subtitle, footer, special, strata, element, logo }
--   element: the brand element of the settings group the window belongs to ("earth",
--     "fire", "water", "air"); default "spirit" (logo blue: pickers, copy boxes,
--     confirms, What's New). It colors the band's light and the underline; f.spElement
--     keeps it for Widgets:SetElement while the window draws its rows, and
--     f:SetElement(key) changes it.
--   logo: true for a title that shows "ShamanPower": the wordmark lockup (Core:Lockup).
function Core:CreateDialog(opts)
	local HEADER_H, PAD = opts.headerHeight or 46, opts.pad or 14
	local BAND_H = HEADER_H + 2   -- the band runs from the top edge to where the header (2 in) ended
	local W = opts.width or 320
	local f = CreateFrame("Frame", opts.name, UIParent)
	f:SetSize(W, opts.height or 200)
	-- A frame with no anchor never renders; callers may re-anchor later.
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:SetFrameStrata(opts.strata or "HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); if self.spOnMoved then self:spOnMoved() end end)
	f:Hide()
	if opts.special and opts.name then tinsert(UISpecialFrames, opts.name) end
	local sp, level = ShamanPower, f:GetFrameLevel()

	self:SolidTex(f, "windowBg", "BACKGROUND", nil, true)

	local header = CreateFrame("Frame", nil, f)
	header:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	header:SetHeight(BAND_H)
	self:SolidTex(header, "sidebarBg", "BACKGROUND", nil, true)
	f.header = header
	-- the settings band's light (centered 12% across its top, reach 1.2), over a
	-- caller's opaque copy of the band; placed again when the window changes width
	-- (the color picker widens for a long title)
	local light = self:Light(header, W, BAND_H, 0.12, 0, 1.2, 2)
	self:RegisterFadeLight(light, self:Color("bandLight"))
	header:SetScript("OnSizeChanged", function(_, hw, hh)
		if hw and hh and hw > 0 and hh > 0 then Core:PlaceLight(light, header, hw, hh, 0.12, 0, 1.2) end
	end)
	f.bandLight = light
	local bandEdge = header:CreateTexture(nil, "BORDER")
	bandEdge:SetHeight(1)
	bandEdge:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
	bandEdge:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
	bandEdge:SetColorTexture(self:Color("border"))

	-- The title sits where it always did (2 + PAD in, its middle 4 under half the
	-- header's height). With a logo it moves right of the totem graphic, whose top is
	-- 14 / 19 of the font size above the title's middle (the sidebar's lockup), kept
	-- 1px clear of the band's line.
	local titleX, text = PAD + 2, opts.title or ""
	if opts.logo then
		local _, size = self.fonts.brand:GetFont()
		size = size or 16
		local graphic, gw, gap, name = self:Lockup(header, size, text)
		text = name
		if graphic then
			local top = math.min(HEADER_H / 2 - 4 - 14 * size / 19, HEADER_H - gw * 682 / 650)
			graphic:SetPoint("TOPLEFT", header, "TOPLEFT", titleX, -top)
			titleX = titleX + gw + gap
		end
		f.spLogo = true
	end
	local title = header:CreateFontString(nil, "OVERLAY")
	title:SetFontObject(self.fonts.brand)
	title:SetPoint("LEFT", header, "LEFT", titleX, 5)
	title:SetText(text)
	f.title = title

	local sub = header:CreateFontString(nil, "OVERLAY")
	sub:SetFontObject(self.fonts.tiny)
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -2)
	sub:SetText(opts.subtitle and strupper(opts.subtitle) or "")
	f.subtitle = sub

	-- the element's underline under the title, on the band's line (a header too short
	-- to hold it under the subtitle goes without)
	local underline
	if HEADER_H >= 40 then
		underline = header:CreateTexture(nil, "ARTWORK")
		underline:SetSize(44, 3)
		underline:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", titleX, 0)
	end
	f.underline = underline

	-- the band's light takes 26% of the element over its navy (the settings band's)
	function f.SetElement(dialog, key)
		dialog.spElement = key or "spirit"
		local er, eg, eb = 0.247, 0.663, 0.961   -- logo blue (#3FA9F5) without the brand kit
		if sp and sp.BrandElementRGB then er, eg, eb = sp:BrandElementRGB(dialog.spElement) end
		local lr, lg, lb = Core:Color("bandLight")
		Core:SetFadeColor(light, er * 0.26 + lr * 0.74, eg * 0.26 + lg * 0.74, eb * 0.26 + lb * 0.74)
		if underline then underline:SetColorTexture(er, eg, eb, 1) end
	end
	f:SetElement(opts.element)

	local close = self:CloseButton(f, 22)
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -12)
	close:SetScript("OnClick", function() f:Hide() end)
	f.close = close

	local body = CreateFrame("Frame", nil, f)
	body:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(HEADER_H + 4 + (opts.bodyTop or 10)))
	body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, (opts.footer or 0) + PAD)
	f.body = body
	f.pad = PAD

	-- the settings window's edge (a soft 1.5px `border` line) and the four elements
	-- along the top, over the band and everything else in the window
	local edge = CreateFrame("Frame", nil, f)
	edge:SetAllPoints(f)
	edge:SetFrameLevel(level + 10)
	self:MakeBorder(edge, "border", 1.5)
	f.spEdge = edge
	if sp and sp.CreateElementStripe then
		local stripe = sp:CreateElementStripe(f)
		stripe:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		stripe:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
		stripe:SetFrameLevel(level + 11)
	end

	f:SetScript("OnShow", function(self)
		Core:SyncOpacity()
		self:Raise()
		if self.spOnShow then self:spOnShow() end
	end)
	f:SetScript("OnHide", function(self)
		if ns and ns.Widgets and ns.Widgets.HidePopup then ns.Widgets:HidePopup() end
		if self.spOnHide then self:spOnHide() end
	end)

	function f:SetTitles(t, st)
		t = t or ""
		if self.spLogo then t = t:gsub("ShamanPower", Core.wordmark) end
		self.title:SetText(t)
		self.subtitle:SetText(st and strupper(st) or "")
	end
	return f
end

return Core
