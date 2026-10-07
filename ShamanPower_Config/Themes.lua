-- ShamanPower_Config :: Themes
-- General > Themes: every theme setting of ShamanPower on one page, and nowhere
-- else. Top to bottom:
--   1. one intro line
--   2. the theme picker: three cards, each with a live mini totem bar, then the
--      Custom line
--   3. Show Icons As (a picture per choice), only while ShamanPower Minimal is
--      picked. No effects here: themes are not effects (the bars' Effects tabs)
--   4. Element Colors: four palette cards (they ARE the Appearance palette
--      setting, spot pal.element); a Custom swatch opens our colour picker
--   5. Shield Colors: three cards
--   6. WoW's own colours
--   7. Reset Colors for Current Theme
--   8. one section per module (SP.THEME_MODULES order): a live mini drawing of
--      the module in its current look, then a row per themable spot: its Theme
--      dropdown, Colors / Shield Colors / Show Icons As / its choice / its switch
--      where it has them, and a swatch per colour.
--
-- Reads and writes only through the theme engine (ShamanPowerTheme.lua). Drawn
-- only with the Core / Widgets primitives and the ui-style-guide tokens. The
-- page's own frames are made once and reused on every render (Widgets rows come
-- from their pools), so opening the tab again creates nothing new. Nothing here
-- runs while the tab is not on screen; opening it writes nothing.
local _, ns = ...
local Core, Widgets = ns.Core, ns.Widgets
local SP = ShamanPower
if not (SP and Core and Widgets and SP.THEME_MODULES and SP.ThemeDisplayColor) then return end

local Page = {}
ns.ThemesPage = Page

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local pairs, ipairs, pcall, tostring = pairs, ipairs, pcall, tostring

local IS_MAINLINE = (SPCompat.FOREVER)
local PLAYER_IS_SHAMAN = select(2, UnitClass("player")) == "SHAMAN"
local BEBAS = "Interface\\AddOns\\ShamanPower\\Media\\Fonts\\BebasNeue-Regular.ttf"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local CLASS_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local DEFAULT = "__default"   -- the dropdowns' "Use General Theme" / "Use Theme's" (nil in the engine)

local INTRO = "Themes change how ShamanPower looks and nothing else. Pick one, then change any part below."
local EL = { "Earth", "Fire", "Water", "Air" }
local CODES = { "SE", "SR", "MS", "WF" }
local FILL = { 0.72, 0.45, 0.8, 0.25 }                 -- sample time left per element
local CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local CLASS_SAMPLE = { "WARRIOR", "PRIEST", "MAGE" }   -- party members with the buff
local CREAM = { 0.957, 0.937, 0.902 }                  -- letters on a dark box
local INK = { 0.102, 0.133, 0.188 }                    -- letters on a light box
local GOLD_TEXT = "|cffFFD100"

-- ---------------------------------------------------------------------------
-- The tab itself: an option group under General (like Interface), so the tab
-- strip, the sidebar search and SPConfig:Open({ "settings", "settings_themes" })
-- all find it. Window.lua draws this page in place of the group's rows.
-- ---------------------------------------------------------------------------
do
	local settings = SP.options and SP.options.args and SP.options.args.settings
	if settings and settings.args and not settings.args.settings_themes then
		local show = settings.args.settings_show
		local base = (show and type(show.order) == "number") and show.order or 1
		settings.args.settings_themes = {
			order = base + 0.25, type = "group", inline = true, name = "Themes",
			args = {
				intro = { order = 1, type = "description", name = INTRO,
					desc = "theme themes look colors palette element shield minimal flat boxes letters icons" },
			},
		}
	end
end

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
local function Hex(r, g, b)
	return string.format("#%02X%02X%02X", floor((r or 0) * 255 + 0.5), floor((g or 0) * 255 + 0.5), floor((b or 0) * 255 + 0.5))
end

-- letters in ink or cream, whichever reads better on the box (the same rule as
-- the real boxes, ShamanPowerThemeBoxes.lua)
local function lin(v) if v <= 0.03928 then return v / 12.92 end return ((v + 0.055) / 1.055) ^ 2.4 end
local function Lum(r, g, b) return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) end
local L_INK, L_CREAM
local function InkOn(r, g, b)
	if not L_INK then L_INK, L_CREAM = Lum(INK[1], INK[2], INK[3]), Lum(CREAM[1], CREAM[2], CREAM[3]) end
	local L = Lum(r, g, b)
	return (L + 0.05) / (L_INK + 0.05) >= (L_CREAM + 0.05) / (L + 0.05)
end
local MIN_FONT = 6   -- letters smaller than this would not read: the one-colour icon says it

local function ClassRGB(class)
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function HasEarthShield()
	return not (SPCompat and SPCompat.SpellExists) or SPCompat.SpellExists(974) and true or false
end

local function SpellIcon(id, fallback)
	local f
	if C_Spell and C_Spell.GetSpellTexture then f = C_Spell.GetSpellTexture(id) end
	if not f and GetSpellTexture then f = GetSpellTexture(id) end
	return f or fallback or QUESTION
end

-- the sample icons, looked up once (the first time the tab is drawn)
local ICON
local function Icons()
	if ICON then return ICON end
	local alliance = UnitFactionGroup and UnitFactionGroup("player") == "Alliance"
	local fire = SP.Wizard and SP.Wizard.FireMockIcon and SP.Wizard.FireMockIcon()
	ICON = {
		soe = SpellIcon(8075, "Interface\\Icons\\Spell_Nature_EarthBindTotem"),
		searing = fire or SpellIcon(3599, "Interface\\Icons\\Spell_Fire_SearingTotem"),
		manaSpring = SpellIcon(5675, "Interface\\Icons\\Spell_Nature_ManaRegenTotem"),
		windfury = SpellIcon(8512, "Interface\\Icons\\Spell_Nature_Windfury"),
		tremor = SpellIcon(8143, "Interface\\Icons\\Spell_Nature_TremorTotem"),
		healing = SpellIcon(5394, "Interface\\Icons\\INV_Spear_04"),
		grace = SpellIcon(8835, "Interface\\Icons\\Spell_Nature_InvisibilityTotem"),
		earthbind = SpellIcon(2484, "Interface\\Icons\\Spell_Nature_StrengthOfEarthTotem02"),
		poison = SpellIcon(8166, "Interface\\Icons\\Spell_Nature_PoisonCleansingTotem"),
		fireRes = SpellIcon(8184, "Interface\\Icons\\Spell_FireResistanceTotem_01"),
		manaTide = SpellIcon(16190, "Interface\\Icons\\Spell_Frost_SummonWaterElemental"),
		recall = SpellIcon(36936, QUESTION),
		lightning = SpellIcon(324, "Interface\\Icons\\Spell_Nature_LightningShield"),
		water = SpellIcon(24398, "Interface\\Icons\\Ability_Shaman_WaterShield"),
		earthShield = SpellIcon(974, "Interface\\Icons\\Spell_Nature_SkinofEarth"),
		wfWeapon = SpellIcon(8232, "Interface\\Icons\\Spell_Nature_Cyclone"),
		ftWeapon = SpellIcon(8024, "Interface\\Icons\\Spell_Fire_FlameTounge"),
		fbWeapon = SpellIcon(8033, "Interface\\Icons\\Spell_Frost_FrostBrand"),
		rbWeapon = SpellIcon(8017, "Interface\\Icons\\Spell_Nature_RockBiter"),
		ns = SpellIcon(16188, "Interface\\Icons\\Spell_Nature_RavenForm"),
		ankh = SpellIcon(20608, "Interface\\Icons\\Spell_Nature_Reincarnation"),
		lust = alliance and SpellIcon(32182, "Interface\\Icons\\Ability_Shaman_Heroism") or SpellIcon(2825, "Interface\\Icons\\Spell_Nature_BloodLust"),
		lustCode = alliance and "HE" or "BL",
	}
	ICON.totems = { ICON.soe, ICON.searing, ICON.manaSpring, ICON.windfury }
	return ICON
end

-- the engine's colour for a swatch / a part: r, g, b (exactly three values)
local function RGB(spot, role)
	local r, g, b = SP:ThemeDisplayColor(spot, role)
	return r, g, b
end

-- ---------------------------------------------------------------------------
-- Drawing primitives (the page's cards, and the mocks inside them)
-- ---------------------------------------------------------------------------
local function Text(parent, font, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFontObject(Core.fonts[font or "row"])
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(true)
	return fs
end

-- wrap a string to a width and return its height (the container grows)
local function Fit(fs, w, s)
	fs:SetWidth(w)
	fs:SetText(s or "")
	return ceil(fs:GetStringHeight())
end

-- small-caps tag ("IN USE", "WOW", "CUSTOM"): the section-label treatment, no box
local function Tag(parent)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(Core.fonts.section)
	fs:SetJustifyH("LEFT")
	fs:Hide()
	return fs
end
local function SetTag(fs, text, colorKey)
	if not text then fs:Hide() return end
	fs:SetText(text)
	fs:SetTextColor(Core:Color(colorKey or "textDim"))
	fs:Show()
end

-- HUD text inside a mock: the player's font choice, like the real frame
local function HudText(parent, area, size, flags)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	if SP.SetSPFont then
		SP:SetSPFont(fs, area, size, flags or "OUTLINE")
	else
		fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, flags or "OUTLINE")
	end
	if not fs:GetFont() then fs:SetFont(SP:ResolveLocaleFontPath("Fonts\\FRIZQT__.TTF"), size, flags or "OUTLINE") end
	return fs
end

-- A selectable card (the tour's spec-card look): rest rowBg + 1px border,
-- hover rowHover + accent border, selected accent @.20 fill, accent border,
-- a 2px accent top bar and the title in accentHi.
local function PaintCard(c)
	local o = Core.opacity or 1
	if c.selected then
		c.bg:SetColorTexture(Core:Color("accent", 0.20))
		Core:SetBorderColor(c, "accent")
		c.topBar:Show()
		if c.title then c.title:SetTextColor(Core:Color("accentHi")) end
	else
		c.bg:SetColorTexture(Core:Color(c.hover and "rowHover" or "rowBg", o))
		Core:SetBorderColor(c, c.hover and "accent" or "border")
		c.topBar:Hide()
		if c.title then c.title:SetTextColor(Core:Color("text")) end
	end
end
local function NewCard(parent)
	local c = CreateFrame("Button", nil, parent)
	c.bg = c:CreateTexture(nil, "BACKGROUND")
	c.bg:SetAllPoints(c)
	Core:MakeBorder(c, "border")
	c.topBar = c:CreateTexture(nil, "ARTWORK", nil, 7)
	c.topBar:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
	c.topBar:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, 0)
	c.topBar:SetHeight(2)
	c.topBar:SetColorTexture(Core:Color("accent"))
	c.topBar:Hide()
	c.spThemes = true
	c:SetScript("OnEnter", function(self) self.hover = true; PaintCard(self) end)
	c:SetScript("OnLeave", function(self) self.hover = false; PaintCard(self) end)
	return c
end

-- a colour swatch in the Widgets look: 1px border over the grey checker
local function NewSwatch(parent, w, h)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, h)
	local checker = b:CreateTexture(nil, "BACKGROUND")
	checker:SetAllPoints(b)
	checker:SetColorTexture(0.25, 0.25, 0.25, 1)
	b.fill = b:CreateTexture(nil, "ARTWORK")
	b.fill:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
	b.fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
	Core:MakeBorder(b, "border")
	b.spThemes = true
	return b
end

-- four edges, t px thick, starting out px outside the frame
local function NewEdges(f, t, out)
	local e = {}
	for i = 1, 4 do e[i] = f:CreateTexture(nil, "OVERLAY", nil, 5) end
	e[1]:SetPoint("TOPLEFT", f, "TOPLEFT", -out, out); e[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT", out, out); e[1]:SetHeight(t)
	e[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -out, -out); e[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", out, -out); e[2]:SetHeight(t)
	e[3]:SetPoint("TOPLEFT", f, "TOPLEFT", -out, out); e[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -out, -out); e[3]:SetWidth(t)
	e[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT", out, out); e[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", out, -out); e[4]:SetWidth(t)
	return e
end
local function PaintEdges(e, r, g, b, a)
	for i = 1, 4 do e[i]:SetColorTexture(r, g, b, a or 1) end
end

-- a horizontal bar: dark track, coloured fill
local function NewBar(parent, w, h)
	local bar = { w = w }
	bar.track = parent:CreateTexture(nil, "ARTWORK", nil, 0)
	bar.track:SetSize(w, h)
	bar.track:SetColorTexture(0, 0, 0, 0.65)
	bar.fill = parent:CreateTexture(nil, "ARTWORK", nil, 1)
	bar.fill:SetHeight(h)
	bar.fill:SetPoint("TOPLEFT", bar.track, "TOPLEFT", 0, 0)
	return bar
end
local function SetBar(bar, frac, r, g, b)
	bar.fill:SetWidth(max(1, bar.w * frac))
	if SP.SetSPBarColor then SP:SetSPBarColor(bar.fill, "duration", r, g, b, 1) else bar.fill:SetColorTexture(r, g, b, 1) end
end

-- n segments in a row (a charge strip)
local function NewSegments(parent, n, w, h, gap)
	local segs = { n = n }
	local sw = (w - gap * (n - 1)) / n
	for i = 1, n do
		local s = parent:CreateTexture(nil, "ARTWORK", nil, 2)
		s:SetSize(sw, h)
		segs[i] = s
	end
	segs.sw, segs.gap = sw, gap
	return segs
end
local function PlaceSegments(segs, anchor, point, x, y)
	for i = 1, segs.n do segs[i]:SetPoint("TOPLEFT", anchor, point, x + (i - 1) * (segs.sw + segs.gap), y) end
end
local function PaintSegments(segs, lit, r, g, b)
	for i = 1, segs.n do
		if i <= lit then segs[i]:SetColorTexture(r, g, b, 1) else segs[i]:SetColorTexture(0, 0, 0, 0.75) end
	end
end

-- a HUD panel mock (bg + 1px edges), painted from a spot's bg / border roles
local function NewPanel(parent)
	local p = CreateFrame("Frame", nil, parent)
	p.bg = p:CreateTexture(nil, "BACKGROUND")
	p.bg:SetAllPoints(p)
	Core:MakeBorder(p, "border")
	return p
end
local function PaintPanel(p, spot, stdAlpha)
	local r, g, b, src = SP:ThemeDisplayColor(spot, "bg")
	local a = stdAlpha or 0.92
	if src ~= "standard" then a = SP:ThemeAlpha(spot, "bg") or a end
	p.bg:SetColorTexture(r, g, b, a)
	local er, eg, eb = SP:ThemeDisplayColor(spot, "border")
	for _, t in pairs(p.spBorder) do t:SetColorTexture(er, eg, eb, 1) end
end

-- A button mock: the icon, or (a flat-box spot on ShamanPower Minimal) the box
-- drawn the way the real skin draws it: the colour, the one-colour icon, a small
-- icon or a faint icon with the letters. Letters in Bebas Neue at under half the
-- box height. Text drawn ON the button (counts, timers) goes on s.over.
local function NewSlot(parent, size)
	local s = CreateFrame("Frame", nil, parent)
	s:SetSize(size, size)
	s.size = size
	local edge = s:CreateTexture(nil, "BACKGROUND")
	edge:SetPoint("TOPLEFT", s, "TOPLEFT", -1, 1)
	edge:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 1, -1)
	edge:SetColorTexture(0, 0, 0, 1)
	s.icon = s:CreateTexture(nil, "ARTWORK", nil, 0)
	s.icon:SetAllPoints(s)
	s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	s.box = s:CreateTexture(nil, "ARTWORK", nil, 1)
	s.box:SetAllPoints(s)
	s.tint = s:CreateTexture(nil, "ARTWORK", nil, 2)
	s.tint:SetAllPoints(s)
	s.tint:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	s.miniBd = s:CreateTexture(nil, "ARTWORK", nil, 2)
	s.miniBd:SetPoint("CENTER", s, "CENTER", 0, 0)
	s.miniBd:SetColorTexture(0, 0, 0, 1)
	s.mini = s:CreateTexture(nil, "ARTWORK", nil, 3)
	s.mini:SetPoint("CENTER", s, "CENTER", 0, 0)
	s.mini:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	s.shade = s:CreateTexture(nil, "ARTWORK", nil, 4)
	s.shade:SetAllPoints(s)
	s.shade:SetColorTexture(0, 0, 0, 1)
	s.letters = s:CreateFontString(nil, "OVERLAY")
	-- two letters: at most half the box height, and they fit across it (as the real boxes)
	local fsz = min(floor((size - 2) * 0.5), floor((size - 4) / 1.1))
	s.fontSize = fsz
	if fsz >= MIN_FONT then
		s.letters:SetFont(BEBAS, fsz, "")
		if not s.letters:GetFont() then s.letters:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", fsz, "") end
	end
	s.letters:SetPoint("CENTER", s, "CENTER", 0, 1)
	s.over = CreateFrame("Frame", nil, s)
	s.over:SetAllPoints(s)
	s.over:SetFrameLevel(s:GetFrameLevel() + 2)
	for _, t in ipairs({ s.box, s.tint, s.miniBd, s.mini, s.shade }) do t:Hide() end
	s.letters:Hide()
	return s
end

-- a button with a number in its middle (a count, a timer): as on the real
-- boxes, its letters move to the top and get smaller
local function SlotTopLetters(s)
	local fsz = min(floor((s.size - 2) * 0.36), floor((s.size - 4) / 1.1))
	s.fontSize = fsz
	if fsz >= MIN_FONT then
		s.letters:SetFont(BEBAS, fsz, "")
		if not s.letters:GetFont() then s.letters:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", fsz, "") end
	end
	s.letters:ClearAllPoints()
	s.letters:SetPoint("TOP", s, "TOP", 0, -2)
end

-- class-sheet icons keep their own coordinates
local function SetCoords(t, c)
	if c then t:SetTexCoord(c[1], c[2], c[3], c[4]) else t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
end

local function PaintSlot(s, boxed, mode, file, code, r, g, b, empty)
	if not boxed then
		s.box:Hide(); s.tint:Hide(); s.mini:Hide(); s.miniBd:Hide(); s.shade:Hide(); s.letters:Hide()
		s.icon:SetTexture(file)
		SetCoords(s.icon, s.coords)
		s.icon:SetDesaturated(empty and true or false)
		s.icon:SetAlpha(empty and 0.35 or 1)
		s.icon:Show()
		return
	end
	s.icon:Hide()
	local k = empty and 0.35 or 1
	local br, bg, bb = r * k, g * k, b * k
	s.box:SetColorTexture(br, bg, bb, 1)
	s.box:Show()
	local full = file ~= nil and not empty
	local canRead = s.fontSize >= MIN_FONT
	local lettersOn = empty and canRead or (canRead and code ~= nil and (mode == "letters" or mode == "both"))
	-- letters too small to read: the one-colour icon says it
	local fallbackTint = full and not lettersOn and (mode == "letters" or mode == "both")
	local tintOn = full and (mode == "tint" or mode == "both" or fallbackTint)
	if tintOn then
		s.tint:SetTexture(file)
		SetCoords(s.tint, s.coords)
		s.tint:SetDesaturated(true)
		s.tint:SetVertexColor(br, bg, bb)
		s.tint:SetAlpha((mode == "both" and lettersOn) and 0.65 or 0.75)
	end
	s.tint:SetShown(tintOn)
	local miniOn = full and mode == "mini"
	if miniOn then
		local m = floor(s.size * 0.56 + 0.5)
		s.mini:SetSize(m, m)
		s.miniBd:SetSize(m + 2, m + 2)
		s.mini:SetTexture(file)
		SetCoords(s.mini, s.coords)
	end
	s.mini:SetShown(miniOn)
	s.miniBd:SetShown(miniOn)
	s.shade:SetAlpha(0.27)
	s.shade:SetShown(tintOn and mode == "both" and lettersOn)
	local t = s.letters
	if not lettersOn then
		t:Hide()
	elseif empty then
		t:SetText("-")
		t:SetTextColor(r * 0.67, g * 0.67, b * 0.67)
		t:SetShadowOffset(0, 0)
		t:Show()
	elseif code then
		if InkOn(br, bg, bb) then
			t:SetTextColor(INK[1], INK[2], INK[3])
			t:SetShadowOffset(0, 0)
		else
			t:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
			t:SetShadowColor(0, 0, 0, 0.6)
			t:SetShadowOffset(1, -1)
		end
		t:SetText(code)
		t:Show()
	else
		t:Hide()
	end
end

-- a button mock of a flat-box spot, coloured by one of its roles
local function BoxSlot(s, spot, role, file, code)
	local r, g, b = SP:ThemeDisplayColor(spot, role)
	PaintSlot(s, SP:ThemeBoxed(spot), SP:ThemeShowAs(spot), file, code, r, g, b, false)
end

-- Element-Colored Borders, Also on the Cooldown Bar: the drawing's buttons get the
-- same colours as the real bar's (ShamanPower:ThemeBorderEdges, via the flat boxes'
-- rules): an element in its colour, a shield in the Shield Colors, others logo blue
local function CdBorder(s, spot, role)
	local on = SP:ThemeField("borders") == true and SP:ThemeField("bordersCooldown") == true
	if on and not s.cdEdges then s.cdEdges = NewEdges(s, 2, 0) end
	local e = s.cdEdges
	if not e then return end
	if on then
		local r, g, b
		if type(role) == "number" then
			r, g, b = SP:ThemeElement(spot, role)
		elseif role == "lightning" or role == "water" or role == "earth" then
			r, g, b = SP:ThemeColor(spot, role)
			if not r then r, g, b = SP:ThemeColor("cd.shield-box", role) end
			if not r then r, g, b = 0.2, 0.6, 1.0 end   -- today's shield blue
		else
			r, g, b = SP:ThemeColor(spot, role)
			if not r then r, g, b = 0.247, 0.663, 0.961 end   -- the logo blue
		end
		PaintEdges(e, r, g, b)
	end
	for i = 1, 4 do e[i]:SetShown(on) end
end

-- an empty choice / unassigned slot: faded totem art, or (ShamanPower Minimal)
-- the dark box with a dash
local function EmptySlot(s, spot, colorSpot, e, file)
	local r, g, b = SP:ThemeDisplayColor(colorSpot, e)
	if SP:ThemeSpotTheme(spot) == "minimal" then
		PaintSlot(s, true, "letters", nil, nil, r, g, b, true)
	else
		PaintSlot(s, false, nil, file, nil, r, g, b, true)
	end
end

-- A cooldown sweep in its selected direction; Minimal uses a dark band.
local function PaintSweep(t, s, spot)
	t:ClearAllPoints()
	local totem = spot == "tb.sweep"
	local style = totem and (SP.opt.totemCooldownSweep or "radial") or (SP.opt.cdbarSweepStyle or "greys")
	local direction = SP.opt.cdbarSweepDirection
	if totem then direction = SP.opt.totemCooldownSweepDirection end
	local fromTop = SP:SweepGrayFromTop(style, direction)
	local edge = fromTop and "TOP" or "BOTTOM"
	t:SetPoint(edge .. "LEFT", s, edge .. "LEFT", 0, 0)
	t:SetPoint(edge .. "RIGHT", s, edge .. "RIGHT", 0, 0)
	if SP:ThemeSpotTheme(spot) == "minimal" then
		t:SetHeight(floor(s.size * 0.4))
		t:SetColorTexture(0, 0, 0, 0.5)
	else
		t:SetHeight(floor(s.size * 0.45))
		t:SetColorTexture(0, 0, 0, 0.6)
	end
end

local function Caption(parent)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(Core.fonts.tiny)
	fs:SetTextColor(Core:Color("accentHi"))   -- all-caps captions (HOW IT LOOKS NOW ...): the page's heading blue
	fs:SetJustifyH("LEFT")
	return fs
end

-- ---------------------------------------------------------------------------
-- The live mini drawing of each module. build(stage) makes the frames once and
-- returns width, height and the paint that recolours them from the engine.
-- ---------------------------------------------------------------------------
local DRAW = {}

DRAW.totembar = function(st)
	local I = Icons()
	local S, G = 28, 4
	local bar = NewPanel(st)
	bar:SetPoint("TOPLEFT", st, "TOPLEFT", 0, 0)
	local slots, bars, x = {}, {}, 8
	for e = 1, 4 do
		local s = NewSlot(bar, S)
		s:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -8)
		slots[e] = s
		local b = NewBar(bar, S, 3)
		b.track:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -2)
		bars[e] = b
		x = x + S + G
	end
	-- Earth is down (overlay, its border, party dots), Fire shows the range
	-- count, Water its time left and pulse, Air a cooldown
	local ring = NewEdges(slots[1], 2, 1)
	local borders = {}
	for e = 1, 4 do borders[e] = NewEdges(slots[e], 2, 0) end   -- Element-Colored Borders
	local dots = {}
	for i = 1, 4 do
		local d = slots[1].over:CreateTexture(nil, "OVERLAY", nil, 6)
		d:SetSize(5, 5)
		d:SetPoint(CORNERS[i], slots[1], CORNERS[i], 0, 0)
		dots[i] = d
	end
	for e = 2, 4 do SlotTopLetters(slots[e]) end   -- each has a number in its middle
	local range = HudText(slots[2].over, "labels", 13, "OUTLINE")
	range:SetPoint("CENTER", slots[2], "CENTER", 0, 0)
	range:SetText("3")
	local dtext = HudText(slots[3].over, "timers", 10, "OUTLINE")
	dtext:SetPoint("CENTER", slots[3], "CENTER", 0, 0)
	dtext:SetText("1:45")
	local pulse = slots[3].over:CreateTexture(nil, "OVERLAY", nil, 6)
	pulse:SetHeight(2)
	pulse:SetWidth(floor(S * 0.6))
	pulse:SetPoint("TOPLEFT", slots[3], "TOPLEFT", 0, 0)
	local sweep = slots[4].over:CreateTexture(nil, "ARTWORK")
	local cdText = HudText(slots[4].over, "timers", 10, "OUTLINE")
	cdText:SetPoint("CENTER", slots[4], "CENTER", 0, 0)
	cdText:SetText("12")
	x = x + 4
	local dropAll = NewSlot(bar, S)
	dropAll:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -8)
	x = x + S + G
	local recall = NewSlot(bar, S)
	recall:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -8)
	x = x + S + G
	local empty
	if IS_MAINLINE then
		empty = NewSlot(bar, S)
		empty:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -8)
		x = x + S + G
	end
	local fw, fh = x + 4, 8 + S + 2 + 3 + 8
	bar:SetSize(fw, fh)
	-- a Water flyout: its arrow tab, two totems and the Empty choice
	local tab = st:CreateTexture(nil, "ARTWORK")
	tab:SetSize(8, 26)
	tab:SetPoint("TOPLEFT", st, "TOPLEFT", fw + 12, -floor((fh - 26) / 2))
	local fly = NewPanel(st)
	local flyN = IS_MAINLINE and 3 or 2   -- the Empty choice exists on WoW: Forever only
	fly:SetSize(flyN * 25 + 5, 30)
	fly:SetPoint("LEFT", tab, "RIGHT", 1, 0)
	local flySlots = {}
	for i = 1, flyN do
		local s = NewSlot(fly, 22)
		s:SetPoint("LEFT", fly, "LEFT", 4 + (i - 1) * 25, 0)
		flySlots[i] = s
	end
	local flyBorders = { NewEdges(flySlots[1], 2, 0), NewEdges(flySlots[2], 2, 0) }   -- Also on the Flyouts
	return fw + 12 + 8 + 1 + 3 * 25 + 5, fh + 4, function()
		PaintPanel(bar, "tb.frame", 0.7)
		for e = 1, 4 do
			local spot = (e == 1) and "tb.overlay-boxes" or "tb.boxes"
			BoxSlot(slots[e], spot, e, I.totems[e], CODES[e])
			local on = SP:ThemeField("borders") == true
			if on then PaintEdges(borders[e], SP:ThemeElement("tb.boxes", e)) end
			for i = 1, 4 do borders[e][i]:SetShown(on) end
			SetBar(bars[e], FILL[e], RGB("tb.duration", e))
		end
		PaintEdges(ring, RGB("tb.overlay-border", 1))
		for i = 1, 3 do dots[i]:SetColorTexture(ClassRGB(CLASS_SAMPLE[i])) end
		dots[4]:SetColorTexture(RGB("tb.dots-missing", "missing"))
		range:SetTextColor(RGB("tb.range", 2))
		dtext:SetTextColor(RGB("tb.duration-text", 3))
		pulse:SetColorTexture(RGB("tb.pulse", 3))
		PaintSweep(sweep, slots[4], "tb.sweep")
		cdText:SetTextColor(RGB("tb.cooldown-text", "text"))
		BoxSlot(dropAll, "tb.dropall", 1, I.soe, "SE")
		BoxSlot(recall, "tb.recall", "box", I.recall, "TC")
		if empty then EmptySlot(empty, "tb.empty-slot", "tb.boxes", 3, I.manaSpring) end
		-- the flyout art: Blizzard's grey tab today, a flat element tab when themed
		local r, g, b = SP:ThemeDisplayColor("tb.flyout-art", 3)
		if SP:ThemeActive("tb.flyout-art") then
			tab:SetColorTexture(r, g, b, 1)
			fly.bg:SetColorTexture(r, g, b, 0.15)
			for _, t in pairs(fly.spBorder) do t:SetColorTexture(r, g, b, 0.9) end
		else
			tab:SetColorTexture(0.42, 0.42, 0.46, 1)
			fly.bg:SetColorTexture(0, 0, 0, 0.55)
			for _, t in pairs(fly.spBorder) do t:SetColorTexture(0.3, 0.3, 0.34, 1) end
		end
		BoxSlot(flySlots[1], "tb.flyout-boxes", 3, I.healing, "HS")
		BoxSlot(flySlots[2], "tb.flyout-boxes", 3, I.manaSpring, "MS")
		if flySlots[3] then EmptySlot(flySlots[3], "tb.flyout-empty", "tb.flyout-boxes", 3, I.manaSpring) end
		local flyOn = SP:ThemeField("borders") == true and SP:ThemeField("bordersFlyouts") == true
		for k = 1, 2 do   -- (not the Empty choice)
			if flyOn then PaintEdges(flyBorders[k], SP:ThemeElement("tb.flyout-boxes", 3)) end
			for i = 1, 4 do flyBorders[k][i]:SetShown(flyOn) end
		end
	end
end

DRAW.styles = function(st)
	local I = Icons()
	-- Compact: an element line each, then the shield line full and on its last charge
	local capC = Caption(st); capC:SetPoint("TOPLEFT", st, "TOPLEFT", 0, 0); capC:SetText("COMPACT")
	local cBoxes, cLines = {}, {}
	for e = 1, 4 do
		local y = -14 - (e - 1) * 13
		local s = NewSlot(st, 11)
		s:SetPoint("TOPLEFT", st, "TOPLEFT", 1, y)
		cBoxes[e] = s
		local line = NewBar(st, 120, 7)
		line.track:SetPoint("TOPLEFT", st, "TOPLEFT", 16, y - 2)
		cLines[e] = line
	end
	local shieldFull = NewSegments(st, 3, 120, 7, 3)
	PlaceSegments(shieldFull, st, "TOPLEFT", 16, -14 - 4 * 13 - 2)
	local shieldLast = NewSegments(st, 3, 120, 7, 3)
	PlaceSegments(shieldLast, st, "TOPLEFT", 16, -14 - 5 * 13 - 2)
	-- Grid: element rings and split borders
	local gx = 170
	local capG = Caption(st); capG:SetPoint("TOPLEFT", st, "TOPLEFT", gx, 0); capG:SetText("GRID")
	local gSlots, gRings = {}, {}
	for e = 1, 4 do
		local s = NewSlot(st, 24)
		s:SetPoint("TOPLEFT", st, "TOPLEFT", gx + 2 + ((e - 1) % 2) * 32, -16 - floor((e - 1) / 2) * 32)
		gSlots[e] = s
		gRings[e] = NewEdges(s, 2, 2)
	end
	-- Blizzard's Totem Bar: the element squares ShamanPower draws on it
	local bx = 260
	local capB = Caption(st); capB:SetPoint("TOPLEFT", st, "TOPLEFT", bx, 0); capB:SetText("BLIZZARD'S TOTEM BAR")
	local bSquares = {}
	for e = 1, 4 do
		local q = st:CreateTexture(nil, "ARTWORK")
		q:SetSize(18, 18)
		q:SetPoint("TOPLEFT", st, "TOPLEFT", bx + (e - 1) * 24, -18)
		bSquares[e] = q
		local edge = NewEdges(st, 1, 0)
		for i = 1, 4 do edge[i]:ClearAllPoints() end
		edge[1]:SetPoint("TOPLEFT", q, "TOPLEFT", -1, 1); edge[1]:SetPoint("TOPRIGHT", q, "TOPRIGHT", 1, 1); edge[1]:SetHeight(1)
		edge[2]:SetPoint("BOTTOMLEFT", q, "BOTTOMLEFT", -1, -1); edge[2]:SetPoint("BOTTOMRIGHT", q, "BOTTOMRIGHT", 1, -1); edge[2]:SetHeight(1)
		edge[3]:SetPoint("TOPLEFT", q, "TOPLEFT", -1, 1); edge[3]:SetPoint("BOTTOMLEFT", q, "BOTTOMLEFT", -1, -1); edge[3]:SetWidth(1)
		edge[4]:SetPoint("TOPRIGHT", q, "TOPRIGHT", 1, 1); edge[4]:SetPoint("BOTTOMRIGHT", q, "BOTTOMRIGHT", 1, -1); edge[4]:SetWidth(1)
		PaintEdges(edge, 0, 0, 0, 1)
	end
	return bx + 4 * 24, 14 + 6 * 13 + 4, function()
		local cBoxed, cMode = SP:ThemeBoxed("st.boxes-compact"), SP:ThemeShowAs("st.boxes-compact")
		for e = 1, 4 do
			local r, g, b = SP:ThemeDisplayColor("st.boxes-compact", e)
			if cBoxed then
				PaintSlot(cBoxes[e], true, cMode, I.totems[e], CODES[e], r, g, b, false)
				cBoxes[e]:Show()
			else
				cBoxes[e]:Hide()   -- today: no icon at the start of a Compact line
			end
			SetBar(cLines[e], FILL[e], RGB("st.compact", e))
			BoxSlot(gSlots[e], "st.boxes-grid", e, I.totems[e], CODES[e])
			PaintEdges(gRings[e], RGB("st.grid", e))
			bSquares[e]:SetColorTexture(RGB("st.blizzard", e))
		end
		PaintSegments(shieldFull, 3, RGB("st.compact-shield", "full"))
		PaintSegments(shieldLast, 1, RGB("st.compact-shield", "last"))
	end
end

DRAW.cooldownbar = function(st)
	local I = Icons()
	local S, G = 30, 6
	local bar = NewPanel(st)
	bar:SetPoint("TOPLEFT", st, "TOPLEFT", 0, 0)
	local x = 8
	local function Btn()
		local s = NewSlot(bar, S)
		s:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -8)
		x = x + S + G
		return s
	end
	local shield = Btn()
	SlotTopLetters(shield)   -- its charge count sits on it
	-- the charge strip inside the bottom of the button, the count lifted above it
	local strip = NewSegments(shield.over, 3, S - 4, 4, 1)
	PlaceSegments(strip, shield, "BOTTOMLEFT", 2, 6)
	local count = HudText(shield.over, "timers", 12, "OUTLINE")
	count:SetPoint("BOTTOMRIGHT", shield, "BOTTOMRIGHT", -1, 7)
	count:SetText("3")
	local shieldBar = NewBar(bar, S, 3)
	shieldBar.track:SetPoint("TOPLEFT", shield, "BOTTOMLEFT", 0, -2)
	local recall = Btn()
	local cds, timers = {}, {}
	for i = 1, 3 do
		cds[i] = Btn()
		timers[i] = NewBar(bar, S, 3)
		timers[i].track:SetPoint("TOPLEFT", cds[i], "BOTTOMLEFT", 0, -2)
	end
	local sweep = cds[1].over:CreateTexture(nil, "ARTWORK")
	local mh, oh = Btn(), Btn()
	local mhBar, ohBar = NewBar(bar, S, 3), NewBar(bar, S, 3)
	mhBar.track:SetPoint("TOPLEFT", mh, "BOTTOMLEFT", 0, -2)
	ohBar.track:SetPoint("TOPLEFT", oh, "BOTTOMLEFT", 0, -2)
	local fw, fh = x + 2, 8 + S + 2 + 3 + 8
	bar:SetSize(fw, fh)
	-- the shield and imbue flyouts, and the Earth Shield flyout's class icons
	local es = HasEarthShield()
	local fly = NewPanel(st)
	local fx = fw + 12
	local flySlots, n = {}, es and 5 or 4
	for i = 1, n do
		local s = NewSlot(fly, 20)
		s:SetPoint("TOPLEFT", fly, "TOPLEFT", 4 + (i - 1) * 23, -4)
		flySlots[i] = s
	end
	fly:SetSize(4 + n * 23 + 1, 28)
	fly:SetPoint("TOPLEFT", st, "TOPLEFT", fx, 0)
	local classSlots = {}
	if es then
		local coordsOf = CLASS_ICON_TCOORDS or {}
		local classes = { "SHAMAN", "PALADIN", "WARRIOR" }
		for i = 1, 3 do
			local s = NewSlot(st, 20)
			s:SetPoint("TOPLEFT", fly, "BOTTOMLEFT", 4 + (i - 1) * 23, -6)
			s.coords = coordsOf[classes[i]]
			s.class = classes[i]
			classSlots[i] = s
		end
	end
	local engine, engineCap
	if IS_MAINLINE then
		engineCap = Caption(st)
		engineCap:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
		engineCap:SetText("SHIELD BAR IN COMBAT")
		engine = NewBar(st, 60, 4)
		engine.track:SetPoint("LEFT", engineCap, "RIGHT", 8, 0)
	end
	local flyW = fx + 4 + n * 23 + 1
	return flyW, fh + (IS_MAINLINE and 22 or 4), function()
		PaintPanel(bar, "cd.frame", 0.7)
		BoxSlot(shield, "cd.shield-box", "lightning", I.lightning, "LS")
		CdBorder(shield, "cd.shield-box", "lightning")
		PaintSegments(strip, 3, RGB("cd.strip", "strip"))
		count:SetTextColor(RGB("cd.count", "high"))
		SetBar(shieldBar, 0.8, RGB("cd.shieldbar", "lightning"))
		BoxSlot(recall, "cd.recall", "box", I.recall, "TC")
		CdBorder(recall, "cd.recall", "box")
		BoxSlot(cds[1], "cd.boxes", 3, I.manaTide, "MT")
		CdBorder(cds[1], "cd.boxes", 3)
		BoxSlot(cds[2], "cd.boxes", "spell", I.ns, "NS")
		CdBorder(cds[2], "cd.boxes", "spell")
		BoxSlot(cds[3], "cd.boxes", "spell", I.ankh, "RE")
		CdBorder(cds[3], "cd.boxes", "spell")
		PaintSweep(sweep, cds[1], "cd.sweep")
		SetBar(timers[1], 0.8, RGB("cd.timers", "good"))
		SetBar(timers[2], 0.35, RGB("cd.timers", "low"))
		SetBar(timers[3], 0.12, RGB("cd.timers", "bad"))
		BoxSlot(mh, "cd.imbue-boxes", 4, I.wfWeapon, "WF")
		CdBorder(mh, "cd.imbue-boxes", 4)
		BoxSlot(oh, "cd.imbue-boxes", 2, I.ftWeapon, "FT")
		CdBorder(oh, "cd.imbue-boxes", 2)
		SetBar(mhBar, 0.7, RGB("cd.imbuebar", 4))
		SetBar(ohBar, 0.4, RGB("cd.imbuebar", 2))
		PaintPanel(fly, "cd.frame", 0.7)
		BoxSlot(flySlots[1], "cd.flyout-boxes", "lightning", I.lightning, "LS")
		BoxSlot(flySlots[2], "cd.flyout-boxes", "water", I.water, "WS")
		local k = 3
		if es then BoxSlot(flySlots[3], "cd.flyout-boxes", "earth", I.earthShield, "ES"); k = 4 end
		BoxSlot(flySlots[k], "cd.flyout-boxes", 1, I.rbWeapon, "RB")
		BoxSlot(flySlots[k + 1], "cd.flyout-boxes", 3, I.fbWeapon, "FB")
		local boxed, mode = SP:ThemeBoxed("cd.class-icons"), SP:ThemeShowAs("cd.class-icons")
		for i = 1, #classSlots do
			local s = classSlots[i]
			local r, g, b = ClassRGB(s.class)
			PaintSlot(s, boxed, mode, CLASS_SHEET, strsub(s.class, 1, 2), r, g, b, false)
		end
		if engine then SetBar(engine, 1, RGB("cd.engine", "bar")) end
	end
end

DRAW.loadouts = function(st)
	local I = Icons()
	local SETS = {
		{ name = "Raid", code = "RA", file = I.windfury, e = 4 },
		{ name = "Heal", code = "HE", file = I.healing, e = 3 },
		{ name = "Solo", code = "SO", file = I.searing, e = 2 },
	}
	local slots, names = {}, {}
	for i = 1, 3 do
		local s = NewSlot(st, 28)
		s:SetPoint("TOPLEFT", st, "TOPLEFT", 1 + (i - 1) * 44, -1)
		slots[i] = s
		local nm = HudText(st, "labels", 9, "OUTLINE")
		nm:SetPoint("TOP", s, "BOTTOM", 0, -3)
		nm:SetText(SETS[i].name)
		names[i] = nm
	end
	-- a loadout's tooltip: its totems named in their element's colour
	local tip = CreateFrame("Frame", nil, st)
	tip:SetSize(190, 78)
	tip:SetPoint("TOPLEFT", st, "TOPLEFT", 150, 0)
	local tbg = tip:CreateTexture(nil, "BACKGROUND")
	tbg:SetAllPoints(tip)
	tbg:SetColorTexture(0.03, 0.03, 0.05, 0.92)
	PaintEdges(NewEdges(tip, 1, 0), 0.45, 0.45, 0.5, 1)
	local head = HudText(tip, "labels", 12, "")
	head:SetPoint("TOPLEFT", tip, "TOPLEFT", 8, -7)
	head:SetText("Raid")
	local NAMES = { "Strength of Earth Totem", "Searing Totem", "Mana Spring Totem", "Windfury Totem" }
	local lines = {}
	for e = 1, 4 do
		local t = HudText(tip, "labels", 11, "")
		t:SetPoint("TOPLEFT", tip, "TOPLEFT", 8, -24 - (e - 1) * 13)
		t:SetText(NAMES[e])
		lines[e] = t
	end
	return 340, 80, function()
		for i = 1, 3 do BoxSlot(slots[i], "lo.bar", "box", SETS[i].file, tostring(i)) end
		for e = 1, 4 do lines[e]:SetTextColor(RGB("lo.tooltip", e)) end
	end
end

DRAW.shieldcharges = function(st)
	local I = Icons()
	local GROUPS = {
		{ role = "full", n = 3, lit = 3, which = "lightning", file = I.lightning, code = "LS" },
		{ role = "low", n = 3, lit = 2, which = "lightning", file = I.lightning, code = "LS" },
		{ role = "last", n = 3, lit = 1, which = "lightning", file = I.lightning, code = "LS" },
	}
	if HasEarthShield() then GROUPS[4] = { role = "esfull", n = 6, lit = 6, which = "earth", file = I.earthShield, code = "ES" } end
	local parts = {}
	for i, gdef in ipairs(GROUPS) do
		local x = (i - 1) * 96
		local s = NewSlot(st, 26)
		s:SetPoint("TOPLEFT", st, "TOPLEFT", x + 1, -1)
		local num = HudText(st, "charges", 24, "OUTLINE")
		num:SetPoint("LEFT", s, "RIGHT", 8, 0)
		num:SetText(tostring(gdef.lit))
		local segs = NewSegments(st, gdef.n, 80, 5, 2)
		PlaceSegments(segs, st, "TOPLEFT", x, -34)
		parts[i] = { s = s, num = num, segs = segs, def = gdef }
	end
	return #GROUPS * 96 - 16, 40, function()
		for i = 1, #parts do
			local p = parts[i]
			BoxSlot(p.s, "mod.shieldcharges-icon", p.def.which, p.def.file, p.def.code)
			local r, g, b = SP:ThemeDisplayColor("mod.shieldcharges-colors", p.def.role)
			p.num:SetTextColor(r, g, b)
			PaintSegments(p.segs, p.def.lit, r, g, b)
		end
	end
end

DRAW.alerts = function(st)
	local LINES = {
		{ 2, "Searing Totem expires in 5" },
		{ 1, "Strength of Earth Totem expired" },
		{ 3, "Mana Spring Totem expired" },
		{ 4, "Windfury Totem expired" },
		{ "shield", "Lightning Shield faded" },
		{ "imbue", "Weapon imbue faded" },
		{ "destroyed", "Searing Totem destroyed" },
	}
	local fs = {}
	for i, l in ipairs(LINES) do
		local t = HudText(st, "alerts", 12, "OUTLINE")
		t:SetPoint("TOPLEFT", st, "TOPLEFT", (i > 4) and 260 or 0, -((i - 1) % 4) * 17)
		t:SetText(l[2])
		fs[i] = t
	end
	return 470, 4 * 17, function()
		for i, l in ipairs(LINES) do fs[i]:SetTextColor(RGB("mod.alerts", l[1])) end
	end
end

DRAW.partybuff = function(st)
	local I = Icons()
	-- the counter frames
	local counters, ctext = {}, {}
	local COUNTS = { "3/4", "4/4", "2/4", "4/4" }
	for e = 1, 4 do
		local p = NewPanel(st)
		p:SetSize(40, 22)
		p:SetPoint("TOPLEFT", st, "TOPLEFT", (e - 1) * 46, -10)
		counters[e] = p
		local t = HudText(p, "labels", 11, "OUTLINE")
		t:SetPoint("CENTER", p, "CENTER", 0, 0)
		t:SetText(COUNTS[e])
		ctext[e] = t
	end
	-- the coverage panel: two cells, each with its party dots
	local cov = NewPanel(st)
	cov:SetSize(150, 66)
	cov:SetPoint("TOPLEFT", st, "TOPLEFT", 200, 0)
	local title = HudText(cov, "labels", 9, "")
	title:SetPoint("TOP", cov, "TOP", 0, -5)
	title:SetText("Totem Coverage")
	local cells, dots = {}, {}
	local CELL = { { e = 1, file = I.soe, code = "SE" }, { e = 4, file = I.windfury, code = "WF" } }
	for i = 1, 2 do
		local s = NewSlot(cov, 26)
		s:SetPoint("TOPLEFT", cov, "TOPLEFT", 26 + (i - 1) * 60, -18)
		cells[i] = s
		dots[i] = {}
		for d = 1, 4 do
			local dot = cov:CreateTexture(nil, "OVERLAY")
			dot:SetSize(5, 5)
			dot:SetPoint("TOPLEFT", s, "BOTTOMLEFT", (d - 1) * 7, -4)
			dots[i][d] = dot
		end
	end
	-- the Party Strip under the counters: its icon, two members with the buff, one
	-- missing it (the circle with a slash) and one it can't tell ("?")
	local DOT = "Interface\\AddOns\\ShamanPower\\textures\\dot"
	local strip = NewPanel(st)
	strip:SetSize(100, 22)
	strip:SetPoint("TOPLEFT", st, "TOPLEFT", 0, -40)
	local line = strip:CreateTexture(nil, "ARTWORK", nil, -8)
	line:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
	line:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, 0)
	line:SetHeight(2)
	local sIcon = NewSlot(strip, 16)
	sIcon:SetPoint("LEFT", strip, "LEFT", 5, 0)
	local marks = {}
	for m = 1, 4 do
		local f = CreateFrame("Frame", nil, strip)
		f:SetSize(12, 12)
		f:SetPoint("LEFT", strip, "LEFT", 27 + (m - 1) * 17, 0)
		local rim = f:CreateTexture(nil, "ARTWORK", nil, 0)
		rim:SetTexture(DOT)
		rim:SetPoint("CENTER", f, "CENTER", 0, 0)
		rim:SetSize(14, 14)
		local d = f:CreateTexture(nil, "ARTWORK", nil, 1)
		d:SetTexture(DOT)
		d:SetAllPoints(f)
		f.rim, f.dot = rim, d
		marks[m] = f
	end
	local ring = marks[3]:CreateTexture(nil, "ARTWORK", nil, 2)
	ring:SetTexture("Interface\\AddOns\\ShamanPower\\Media\\Textures\\Ring_40px")
	ring:SetAllPoints(marks[3])
	local slash = marks[3]:CreateTexture(nil, "ARTWORK", nil, 3)
	slash:SetTexture("Interface\\AddOns\\ShamanPower\\textures\\cue_slash")
	slash:SetTexCoord(1, 0, 0, 1)
	slash:SetPoint("TOPLEFT", marks[3], "TOPLEFT", 1.5, -1.5)
	slash:SetPoint("BOTTOMRIGHT", marks[3], "BOTTOMRIGHT", -1.5, 1.5)
	local q = HudText(marks[4], "labels", 11, "OUTLINE")
	q:SetPoint("CENTER", marks[4], "CENTER", 0, 0)
	q:SetText("?")
	local STRIP_CLASSES = { "WARRIOR", "PRIEST" }
	return 350, 66, function()
		for e = 1, 4 do PaintPanel(counters[e], "mod.partybuff-frame", 0.92) end
		PaintPanel(cov, "mod.coverage-colors", 0.92)
		for i = 1, 2 do
			BoxSlot(cells[i], "mod.coverage-boxes", CELL[i].e, CELL[i].file, CELL[i].code)
			for d = 1, 3 do dots[i][d]:SetColorTexture(ClassRGB(CLASS_SAMPLE[d])) end
			dots[i][4]:SetColorTexture(RGB("mod.coverage-dots-missing", "missing"))
		end
		-- the strip at its own Background Opacity (a theme colors it, never makes it more solid)
		local ps = SP.opt and SP.opt.partyStrip
		local a = tonumber(ps and ps.bgOpacity) or 0.8
		strip.bg:SetColorTexture(RGB("mod.partystrip-frame", "bg"))
		strip.bg:SetAlpha(a)
		local er, eg, eb = RGB("mod.partystrip-frame", "border")
		for _, t in pairs(strip.spBorder) do t:SetColorTexture(er, eg, eb, a) end
		line:SetColorTexture(SP:ThemeElement("mod.partystrip-line", 4))
		line:SetAlpha(a)
		BoxSlot(sIcon, "mod.partystrip-box", 4, I.windfury, "WF")
		for m = 1, 4 do
			local f = marks[m]
			local has = m <= 2
			f.rim:SetVertexColor(0, 0, 0, has and 1 or 0)
			if has then
				local cls = STRIP_CLASSES[m]
				local r, g, b = SP:ThemeClassSetRGB("mod.partystrip-class", cls)
				if not r then r, g, b = ClassRGB(cls) end
				f.dot:SetVertexColor(r, g, b, 1)
			else
				f.dot:SetVertexColor(0.055, 0.063, 0.078, 0.85)   -- the dark disc under "missing" and "?"
			end
		end
		local mr, mg, mb = RGB("mod.partystrip-marks", "missing")
		ring:SetVertexColor(mr, mg, mb)
		slash:SetVertexColor(mr, mg, mb)
		q:SetTextColor(RGB("mod.partystrip-marks", "unknown"))
	end
end

DRAW.range = function(st)
	local I = Icons()
	local panel = NewPanel(st)
	panel:SetSize(150, 60)
	panel:SetPoint("TOPLEFT", st, "TOPLEFT", 0, 0)
	local T = { { e = 1, file = I.tremor, code = "TR", name = "Tremor" }, { e = 3, file = I.healing, code = "HS", name = "Healing" },
		{ e = 4, file = I.grace, code = "GA", name = "Grace" } }
	local slots = {}
	for i = 1, 3 do
		local s = NewSlot(panel, 26)
		s:SetPoint("TOPLEFT", panel, "TOPLEFT", 14 + (i - 1) * 46, -8)
		slots[i] = s
		local nm = HudText(panel, "labels", 9, "OUTLINE")
		nm:SetPoint("TOP", s, "BOTTOM", 0, -3)
		nm:SetText(T[i].name)
	end
	-- the totem picker window's element tints
	local heads = {}
	for e = 1, 4 do
		local h = CreateFrame("Frame", nil, st)
		h:SetSize(58, 22)
		h:SetPoint("TOPLEFT", st, "TOPLEFT", 170 + (e - 1) * 64, -18)
		h.bg = h:CreateTexture(nil, "BACKGROUND")
		h.bg:SetAllPoints(h)
		h.edges = NewEdges(h, 1, 0)
		h.t = h:CreateFontString(nil, "OVERLAY")
		h.t:SetFontObject(Core.fonts.row)
		h.t:SetPoint("CENTER", h, "CENTER", 0, 0)
		h.t:SetText(EL[e])
		heads[e] = h
	end
	local capW = Caption(st)
	capW:SetPoint("TOPLEFT", st, "TOPLEFT", 170, 0)
	capW:SetText("TOTEM PICKER WINDOW")
	return 170 + 4 * 64, 60, function()
		PaintPanel(panel, "mod.range-colors", 0.92)
		for i = 1, 3 do BoxSlot(slots[i], "mod.range-boxes", T[i].e, T[i].file, T[i].code) end
		for e = 1, 4 do
			local h = heads[e]
			local r, g, b = SP:ThemeDisplayColor("win.rangecfg", e)
			h.bg:SetColorTexture(r, g, b, 0.10)
			PaintEdges(h.edges, r, g, b, 0.9)
			h.t:SetTextColor(r, g, b)
		end
	end
end

DRAW.raidcd = function(st)
	local I = Icons()
	local panel = NewPanel(st)
	panel:SetSize(110, 58)
	panel:SetPoint("TOPLEFT", st, "TOPLEFT", 0, 0)
	local title = HudText(panel, "labels", 9, "")
	title:SetPoint("TOP", panel, "TOP", 0, -5)
	title:SetText("Raid Cooldowns")
	local tide = NewSlot(panel, 26)
	tide:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -20)
	local lust = NewSlot(panel, 26)
	lust:SetPoint("TOPLEFT", panel, "TOPLEFT", 64, -20)
	local alert = HudText(st, "alerts", 16, "OUTLINE")
	alert:SetPoint("LEFT", panel, "RIGHT", 24, 0)
	alert:SetText((I.lustCode == "HE" and "Heroism" or "Bloodlust") .. " in 3")
	return 330, 58, function()
		PaintPanel(panel, "mod.raidcd-colors", 0.92)
		BoxSlot(tide, "mod.raidcd-boxes", 3, I.manaTide, "MT")
		BoxSlot(lust, "mod.raidcd-boxes", "spell", I.lust, I.lustCode)
		alert:SetTextColor(RGB("mod.raidcd-colors", "alert"))
	end
end

DRAW.popouts = function(st)
	local I = Icons()
	local panel = NewPanel(st)
	panel:SetSize(96, 52)
	panel:SetPoint("TOPLEFT", st, "TOPLEFT", 0, 0)
	local P = { { e = 4, file = I.windfury, code = "WF", t = "1:12" }, { e = 3, file = I.manaSpring, code = "MS", t = "0:48" } }
	local slots = {}
	for i = 1, 2 do
		local s = NewSlot(panel, 28)
		s:SetPoint("TOPLEFT", panel, "TOPLEFT", 12 + (i - 1) * 42, -6)
		slots[i] = s
		local t = HudText(panel, "timers", 9, "OUTLINE")
		t:SetPoint("TOP", s, "BOTTOM", 0, -2)
		t:SetText(P[i].t)
	end
	return 96, 52, function()
		PaintPanel(panel, "mod.popouts-colors", 0.92)
		for i = 1, 2 do BoxSlot(slots[i], "mod.popouts-boxes", P[i].e, P[i].file, P[i].code) end
	end
end

DRAW.estracker = function(st)
	local I = Icons()
	local panel = NewPanel(st)
	panel:SetSize(140, 42)
	panel:SetPoint("TOPLEFT", st, "TOPLEFT", 0, 0)
	local icon = NewSlot(panel, 28)
	icon:SetPoint("LEFT", panel, "LEFT", 7, 0)
	local count = HudText(panel, "charges", 18, "OUTLINE")
	count:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	count:SetText("6")
	local name = HudText(panel, "labels", 11, "OUTLINE")
	name:SetPoint("LEFT", count, "RIGHT", 10, 0)
	name:SetText("Tank")
	return 140, 42, function()
		PaintPanel(panel, "mod.estracker-colors", 0.7)
		BoxSlot(icon, "mod.estracker-box", "earth", I.earthShield, "ES")
		count:SetTextColor(RGB("mod.estracker-colors", "count"))
	end
end

DRAW.reactive = function(st)
	local a = HudText(st, "alerts", 14, "OUTLINE")
	a:SetPoint("TOPLEFT", st, "TOPLEFT", 0, 0)
	a:SetText("Fear! Tremor Totem")
	local b = HudText(st, "alerts", 14, "OUTLINE")
	b:SetPoint("TOPLEFT", st, "TOPLEFT", 0, -20)
	b:SetText("Poison! Poison Cleansing Totem")
	return 300, 36, function()
		a:SetTextColor(RGB("mod.reactive", 1))
		b:SetTextColor(RGB("mod.reactive", 3))
	end
end

DRAW.readyreminders = function(st)
	local box = CreateFrame("Frame", nil, st)
	box:SetSize(210, 30)
	box:SetPoint("TOPLEFT", st, "TOPLEFT", 2, -2)
	local bg = box:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(box)
	bg:SetColorTexture(0, 0, 0, 0.6)
	local edges = NewEdges(box, 2, 0)
	local t = HudText(box, "alerts", 12, "OUTLINE")
	t:SetPoint("CENTER", box, "CENTER", 0, 0)
	t:SetText("Windfury Totem is ready")
	return 214, 34, function()
		PaintEdges(edges, RGB("mod.readyreminders", "border"))
		t:SetTextColor(1, 0.82, 0)   -- the reminder names its totem in gold
	end
end

DRAW.tremor = function(st)
	local I = Icons()
	local icon = NewSlot(st, 32)
	icon:SetPoint("TOPLEFT", st, "TOPLEFT", 4, -4)
	local glow = NewEdges(icon, 3, 3)
	local t = HudText(st, "alerts", 14, "OUTLINE")
	t:SetPoint("LEFT", icon, "RIGHT", 14, 0)
	t:SetText("Tremor Totem")
	return 200, 40, function()
		BoxSlot(icon, "mod.tremor-box", 1, I.tremor, "TR")
		local r, g, b = SP:ThemeDisplayColor("mod.tremor", "glow")
		PaintEdges(glow, r, g, b, 0.9)
	end
end

DRAW.readycheck = function(st)
	local panel = NewPanel(st)
	panel:SetSize(180, 52)
	panel:SetPoint("TOPLEFT", st, "TOPLEFT", 0, 0)
	local title = HudText(panel, "labels", 10, "")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -6)
	title:SetText("Ready Check")
	local l1 = HudText(panel, "labels", 10, "")
	l1:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
	l1:SetText("Totems: 4 of 4")
	local l2 = HudText(panel, "labels", 10, "")
	l2:SetPoint("TOPLEFT", l1, "BOTTOMLEFT", 0, -3)
	l2:SetText("Shield and weapon imbues: on")
	return 180, 52, function()
		PaintPanel(panel, "mod.readycheck", 0.92)
	end
end

DRAW.plates = function(st)
	local I = Icons()
	local P = { { e = 1, file = I.earthbind, code = "EB", role = "enemy", name = "Enemy" },
		{ e = 3, file = I.manaSpring, code = "MS", role = "friendly", name = "Friendly" } }
	local parts = {}
	for i = 1, 2 do
		local s = NewSlot(st, 26)
		s:SetPoint("TOPLEFT", st, "TOPLEFT", 4 + (i - 1) * 70, -4)
		local edges = NewEdges(s, 2, 2)
		local nm = HudText(st, "labels", 9, "OUTLINE")
		nm:SetPoint("TOP", s, "BOTTOM", 0, -5)
		nm:SetText(P[i].name)
		parts[i] = { s = s, edges = edges }
	end
	return 140, 48, function()
		for i = 1, 2 do
			BoxSlot(parts[i].s, "mod.plates-boxes", P[i].e, P[i].file, P[i].code)
			PaintEdges(parts[i].edges, RGB("mod.plates-colors", P[i].role))
		end
	end
end

DRAW.minimap = function(st)
	local map = CreateFrame("Frame", nil, st)
	map:SetSize(120, 60)
	map:SetPoint("TOPLEFT", st, "TOPLEFT", 0, 0)
	local bg = map:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(map)
	bg:SetColorTexture(0, 0, 0, 0.55)
	PaintEdges(NewEdges(map, 1, 0), 0.3, 0.3, 0.34, 1)
	local POS = { { 22, -14 }, { 50, -30 }, { 78, -12 }, { 96, -34 } }
	local pins, rings = {}, {}
	for e = 1, 4 do
		local ring = CreateFrame("Frame", nil, map)
		ring:SetSize(18, 18)
		ring:SetPoint("CENTER", map, "TOPLEFT", POS[e][1], POS[e][2])
		rings[e] = NewEdges(ring, 1, 0)
		local pin = map:CreateTexture(nil, "OVERLAY")
		pin:SetSize(6, 6)
		pin:SetPoint("CENTER", ring, "CENTER", 0, 0)
		pins[e] = pin
	end
	return 120, 60, function()
		for e = 1, 4 do
			local r, g, b = SP:ThemeDisplayColor("mod.minimap", e)
			pins[e]:SetColorTexture(r, g, b, 1)
			PaintEdges(rings[e], r, g, b, 0.7)
		end
	end
end

DRAW.assign = function(st)
	local heads = {}
	for e = 1, 4 do
		local h = CreateFrame("Frame", nil, st)
		h:SetSize(76, 24)
		h:SetPoint("TOPLEFT", st, "TOPLEFT", (e - 1) * 82, 0)
		h.bg = h:CreateTexture(nil, "BACKGROUND")
		h.bg:SetAllPoints(h)
		h.edges = NewEdges(h, 1, 0)
		h.t = h:CreateFontString(nil, "OVERLAY")
		h.t:SetFontObject(Core.fonts.row)
		h.t:SetPoint("CENTER", h, "CENTER", 0, 0)
		h.t:SetText(EL[e])
		heads[e] = h
	end
	return 4 * 82 - 6, 24, function()
		for e = 1, 4 do
			local h = heads[e]
			local r, g, b = SP:ThemeDisplayColor("win.assign", e)
			h.bg:SetColorTexture(r, g, b, 0.10)
			PaintEdges(h.edges, r, g, b, 0.9)
			h.t:SetTextColor(r, g, b)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Page state. Frames are kept by key and reused; `shown` is this render's list
-- (hidden on Release), `live` the ones repainted on every theme change.
-- ---------------------------------------------------------------------------
local page = { body = nil, onChanged = nil, visible = false }
local store, shown, live = {}, {}, {}
local pickCards, showCards, palCards, shieldCards, wowRows = {}, {}, {}, {}, {}
local customLine
local RepaintAll, LayoutSig

-- Shared by the drawings and their search index. Card/spot text stays in its
-- catalogue; new blocks supply their own title, description and choices here.
local BLOCKS = {
	intro = { label = INTRO },
	picker = { label = "Theme" },
	options = { label = "Theme Options", desc = "Show Icons As",
		note = "How each flat box shows which totem it is. Each part below can pick its own." },
	palettes = { label = "Element Colors" },
	borders = { label = "Element-Colored Borders", search = "Border Size",
		desc = "Outlines each totem on the totem bar in its element color from the colors above,"
			.. " like the icons on these cards."
			.. " Not shown with the Compact, Grid or Blizzard's Totem Bar styles." },
	flyoutBorders = { label = "Also on the Flyouts", search = "Flyout Border Size",
		desc = "Gives every totem in the totem bar's flyouts the same element-colored border." },
	cooldownFlyoutBorders = { label = "Also on the Cooldown Bar Flyouts", search = "Cooldown Bar Flyout Border Size",
		desc = "Gives every shield and weapon imbue in the cooldown bar's flyouts a border in the color of what it shows,"
			.. " like the cooldown bar's own buttons." },
	cooldownBorders = { label = "Also on the Cooldown Bar", search = "Cooldown Bar Border Size",
		desc = "Gives every button on the cooldown bar a border in the color of what it shows: shields in your Shield Colors,"
			.. " weapon imbues and element spells in their element color, other spells in the logo blue." },
	classColors = { label = "Class Colors", search = "Gem Dot Finish party dots coverage dots class",
		desc = "The class colors of the party dots and the Totem Coverage dots." },
	shields = { label = "Shield Colors" },
	shapes = { label = "Shapes & Textures" },
	barTexture = { label = "Bar Texture",
		desc = "The texture of every bar ShamanPower draws, unless a part picks its own."
			.. " The same setting as Bar Texture on General > Fonts & Textures." },
	shieldTexture = { label = "Shield Charge Bars",
		desc = "The texture for Shield Charges' bars and the Cooldown Bar's Shield Charge Bar. Set separately from Bar Texture."
			.. " The same setting as on General > Fonts & Textures and Shield Charges." },
	wow = { label = "WoW's Own Colors",
		desc = "The colors WoW itself uses, so the ShamanPower themes match the rest of your game."
			.. " A swatch below tagged WOW is one of these; click it to pick your own color for that part instead." },
	reset = { label = "Reset Colors for Current Theme",
		desc = "Keeps your theme. Clears every color you changed on this page (the Element Colors and Shield Colors picks,"
			.. " each shield's Charge Color, the gradients' Two-Tone colors), so each part shows the theme's colors again." },
	resetAll = { label = "Reset All Colors and Theme", caption = "Reset All Colors and Theme",
		desc = "Reset every color in ShamanPower to its default:"
			.. " the Standard theme with nothing changed, and every color option on every page, Shield Charges included."
			.. " It asks first, then reloads your interface." },
	resetEverything = { label = "Reset Everything", caption = "Reset Everything",
		desc = "Reset every setting on this page to its default. Includes Reset All Colors and Theme, plus:"
			.. " Bar Texture and Shield Charge Bars, Dot Shape, Gem Dot Finish, Glow Shape, Frame Edge, each bar's Icon Shape,"
			.. " Keep Borders Square, all three gradients, Duration Bar Background, each shield's charge look and"
			.. " Sweep Direction on the bars, Ready Reminders and Target Tracker, plus Target Tracker's Look When Missing and Icon Edge."
			.. " It asks first, then reloads your interface." },
}

local function Keep(key, make)
	local f = store[key]
	if not f then
		f = make()
		store[key] = f
	end
	f:SetParent(page.body)
	f:ClearAllPoints()
	f:Show()
	shown[#shown + 1] = f
	return f
end

local function PageChanged()
	if SP.ThemeCheckChange then SP:ThemeCheckChange() end   -- /sp themecheck: a change a theme would not capture
	if page.onChanged then page.onChanged() end
	-- a change that brings rows in or out on this page (Custom Outline Color, a
	-- gradient's colors ...): lay it out again, as a theme change does
	if page.visible and LayoutSig and page.layoutSig and LayoutSig() ~= page.layoutSig
		and ns.SPConfig and ns.SPConfig.RefreshCurrent then
		ns.SPConfig:RefreshCurrent()
	end
end

local function Header(label, y, W, note)
	-- accentHi, as the sidebar's group headers: every all-caps title on this page stands out
	local _, h = Widgets:SectionHeader(page.body, { label = label, x = 0, y = y, width = W, note = note, color = "accentHi" })
	return h
end

-- ---------------------------------------------------------------------------
-- The engine, as the top of the page shows it
-- ---------------------------------------------------------------------------
-- the Appearance palette as it is set right now (Standard shows it untouched)
local function AppearancePalette()
	local o = SP.opt
	return (o and o.elementColorPalette) or (SP.DefaultElementPalette and SP:DefaultElementPalette()) or "classic"
end
-- the Element Colors card in use: the Themes tab's pick, the theme's own, or
-- (Standard) the Appearance palette
local function InUsePalette()
	local p = SP:ThemeField("palette")
	if p then return p end
	if SP:ThemeGlobal() ~= "standard" then return "shamanpower" end
	return AppearancePalette()
end
-- the palette the ShamanPower / Minimal cards and the shield cards show
local function CustomRGB(e)
	-- Standard with the Appearance page's own Custom palette: show those colours
	if SP:ThemeField("palette") == nil and SP:ThemeGlobal() == "standard" and AppearancePalette() == "custom" then
		local c = SP.ElementColors and SP.ElementColors[e]
		if c then return c.r, c.g, c.b end
	end
	return SP:ThemePaletteRGB("custom", e)
end
local function PaletteCardRGB(key, e)
	if key == "custom" then return CustomRGB(e) end
	return SP:ThemePaletteRGB(key, e)
end
local function ShieldDefault()
	return SP:ThemeGlobal() == "standard" and "today" or "palette"
end
local function ShieldCardRGB(mode, which)
	if mode == "today" then return 0.2, 0.6, 1.0 end   -- #3399FF
	if mode == "magic" then return SP:WoWColor("DEBUFF_TYPE_MAGIC_COLOR") end
	local pal = SP:ThemeField("palette") or (SP:ThemeGlobal() ~= "standard" and "shamanpower") or nil
	if which == "water" then return SP:ThemePaletteRGB(pal, 3) end
	if which == "earth" then return SP:ThemePaletteRGB(pal, 1) end
	local lb = SP.THEME_BRAND and SP.THEME_BRAND.logoBlue
	if lb then return lb[1], lb[2], lb[3] end
	return 0.247, 0.663, 0.961
end
-- the duration bars as Standard draws them today
local function StdDuration(e)
	local def = SP:ThemeSpot("tb.duration")
	local role = def and def.roleByKey and def.roleByKey[tostring(e)]
	local c = role and role.stdRGB
	if c then return c[1], c[2], c[3] end
	local d = SP.DurationBarColors and SP.DurationBarColors[e]
	if d then return d[1], d[2], d[3] end
	return 1, 1, 1
end

-- ---------------------------------------------------------------------------
-- Colour picking (OUR picker only, never Blizzard's)
-- ---------------------------------------------------------------------------
local function PickSwatch(spot, role, title)
	if not SP.OpenColorPicker then return end
	local r, g, b, src = SP:ThemeDisplayColor(spot, role)
	local keep = (src == "custom") or SP:ThemeRoleIsSetting(spot, role)
	SP:OpenColorPicker({
		r = r, g = g, b = b, title = title,
		onChange = function(nr, ng, nb) SP:SetSpotColor(spot, role, nr, ng, nb) end,
		onCancel = function()
			-- put back exactly what was there: the setting / the edit, or no edit at all
			if keep then SP:SetSpotColor(spot, role, r, g, b) else SP:SetSpotColor(spot, role, nil) end
		end,
	})
end

-- a Custom palette swatch: edits the Themes tab's Custom palette and makes it
-- the Element Colors in use
local function PickCustom(e)
	if not SP.OpenColorPicker then return end
	local r, g, b = CustomRGB(e)
	local prevPalette, prevCustom = SP:ThemeField("palette"), SP:ThemeField("custom")
	local started = false
	SP:OpenColorPicker({
		r = r, g = g, b = b, title = EL[e] .. " (Custom element colors)",
		onChange = function(nr, ng, nb)
			if not started then
				started = true
				-- start from the four colours the card shows
				if SP:ThemeField("custom") == nil then
					local c = {}
					for i = 1, 4 do
						local cr, cg, cb = CustomRGB(i)
						c[i] = { r = cr, g = cg, b = cb }
					end
					SP:SetThemeField("custom", c)
				end
				if SP:ThemeField("palette") ~= "custom" then SP:SetThemeField("palette", "custom") end
			end
			SP:SetThemeCustomColor(e, nr, ng, nb)
		end,
		onCancel = function()
			if not started then return end
			SP:SetThemeField("custom", prevCustom)
			if SP:ThemeField("palette") ~= prevPalette then SP:SetThemeField("palette", prevPalette) end
		end,
	})
end

-- ---------------------------------------------------------------------------
-- 2. The theme picker
-- ---------------------------------------------------------------------------
local PICKS = {
	{ key = "standard", label = "Standard",
	  desc = "ShamanPower's default look. Choosing this preset restores that look every time." },
	{ key = "shamanpower", label = "ShamanPower",
	  desc = "The logo's colors on duration bars, borders and flyout tabs. Green, yellow and red charges and timers. Navy panels. Your icons stay the same. This preset never changes." },
	{ key = "minimal", label = "ShamanPower Minimal",
	  desc = "The ShamanPower theme with icons replaced by flat, colored boxes and letters. This preset never changes." },
}
local TC = {}   -- the theme cards' helpers (one local: this file is near Lua's 200-local limit)
TC.PRESET_LABEL = { standard = "Standard", shamanpower = "ShamanPower", minimal = "ShamanPower Minimal" }
local function CustomCardShown() return SP:ThemeIsCustom() or SP:ThemeHasSavedCustom() end
local CUSTOM_ON = GOLD_TEXT .. "Custom|r is in use: your changes. Save it as a theme to keep it,"
	.. " or pick any card: your changes wait on the Custom card."
local CUSTOM_OFF = "Change anything below and it becomes your " .. GOLD_TEXT
	.. "Custom|r look. Save it to keep it as your own theme."
TC.MINE_DESC = "Your theme. Picking it gives exactly this look, every time."

-- ---- the dialogs of the theme cards (ShamanPower's own dialog) ----------------
function TC.Rerender()
	if ns.SPConfig and ns.SPConfig.RefreshCurrent then ns.SPConfig:RefreshCurrent() else PageChanged() end
end
function TC.Say(msg) print("|cff0070ddShamanPower|r: " .. msg) end
function TC.SaveAsDialog(suggest)
	SP:ShowSPDialog({
		key = "themesaveas", title = "Save as Theme", subtitle = "Your Themes", width = 420,
		text = "Saves your whole look from the Themes tab under this name. Pick it any time to get exactly this look back, on any of your characters.",
		input = { text = suggest or "", maxLetters = 32 },
		buttons = {
			{ text = "Save", onClick = function(d)
				local name = strtrim(d:GetInput())
				if name == "" then return true end
				local mine = SP:ThemeMine()
				for _, th in ipairs(mine) do
					if strlower(th.name) == strlower(name) then
						SP:ShowSPDialog({
							key = "themereplace", title = "Replace " .. th.name .. "?",
							text = "You already have a theme called " .. th.name .. ". Saving replaces it with this look.",
							buttons = {
								{ text = "Replace", onClick = function() SP:ThemeSaveAs(name); TC.Rerender() end },
								{ text = "Cancel" },
							},
						})
						return
					end
				end
				SP:ThemeSaveAs(name)
				TC.Rerender()
			end },
			{ text = "Cancel" },
		},
	})
end
function TC.RenameDialog(th)
	SP:ShowSPDialog({
		key = "themerename", title = "Rename " .. th.name, subtitle = "Your Themes", width = 400,
		text = "The new name, on every character.",
		input = { text = th.name, maxLetters = 32 },
		buttons = {
			{ text = "Rename", onClick = function(d)
				local name = strtrim(d:GetInput())
				if name == "" then return true end
				if not SP:ThemeRename(th.id, name) then TC.Say("you already have a theme called " .. name .. ".") return true end
				TC.Rerender()
			end },
			{ text = "Cancel" },
		},
	})
end
function TC.DeleteDialog(th)
	SP:ShowSPDialog({
		key = "themedelete", title = "Delete " .. th.name .. "?",
		text = "It goes from Your Themes on every character. If it is in use, your look stays as it is, as an unsaved Custom look.",
		buttons = {
			{ text = "Delete", onClick = function() SP:ThemeDelete(th.id); TC.Rerender() end },
			{ text = "Cancel" },
		},
	})
end
function TC.ShareDialog(th)
	local code = SP:ThemeShareCode(th.id)
	if not code then TC.Say("could not make a code for that theme.") return end
	SP:ShowSPDialog({
		key = "themeshare", title = "Share " .. th.name, subtitle = "Theme code", width = 460, editScroll = true,
		text = "Press |cffFFD100Ctrl+C|r to copy it. Anyone with ShamanPower can paste it into Import Theme on General > Themes"
			.. " to add this theme to theirs, or share it in #ui-showcase on the ShamanPower Discord.",
		editText = code,
	})
end
function TC.ImportDialog()
	SP:ShowSPDialog({
		key = "themeimport", title = "Import Theme", subtitle = "Your Themes", width = 460,
		text = "Paste a theme code (it starts with SPT1:). The theme is added to Your Themes; click it to use it.",
		input = { text = "", maxLetters = 0 },
		buttons = {
			{ text = "Import", onClick = function(d)
				local th, err, skipped = SP:ThemeImport(d:GetInput())
				if not th then TC.Say("could not import that theme: " .. tostring(err) .. ".") return true end
				if skipped and skipped > 0 then
					TC.Say("added " .. th.name .. " to Your Themes. " .. skipped .. (skipped == 1 and " setting" or " settings")
						.. " in that code could not be used and " .. (skipped == 1 and "was" or "were") .. " left out.")
				else
					TC.Say("added " .. th.name .. " to Your Themes.")
				end
				TC.Rerender()
			end },
			{ text = "Cancel" },
		},
	})
end

-- ---- the cards ---------------------------------------------------------------
function TC.PresetOf(card)
	if type(card) == "string" and card:sub(1, 5) == "mine:" then
		local th = SP:ThemeMineById(tonumber(card:sub(6)))
		return th and th.name or "Standard"
	end
	return TC.PRESET_LABEL[card] or "Standard"
end

local function NewPickCard(p)
	local c = NewCard(page.body)
	c.slots, c.bars = {}, {}
	local I = Icons()
	for e = 1, 4 do
		local s = NewSlot(c, 26)
		s:SetPoint("TOPLEFT", c, "TOPLEFT", 12 + (e - 1) * 30, -12)
		c.slots[e] = s
		local b = NewBar(c, 26, 3)
		b.track:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -3)
		c.bars[e] = b
	end
	c.files = I.totems
	c.title = Text(c, "brand")
	c.title:SetPoint("TOPLEFT", c, "TOPLEFT", 148, -12)
	c.title:SetText(p.label or "")
	c.kindTag = Tag(c)
	c.kindTag:SetPoint("LEFT", c.title, "RIGHT", 10, 0)
	c.sub = Text(c, "rowDim")
	c.sub:SetFontObject(Core.fonts.section)
	c.sub:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -3)
	c.sub:Hide()
	c.desc = Text(c, "rowDim")
	c.tag = Tag(c)
	c.tag:SetPoint("TOPRIGHT", c, "TOPRIGHT", -12, -14)
	c.btns = {}
	c.key = p.key
	c:SetScript("OnClick", function(self)
		if InCombatLockdown() then return end
		if self.kind == "custom" then
			if SP.ThemeCustomNeedsReload and SP:ThemeCustomNeedsReload() then
				-- a Custom look kept by 3.0.4's reset: its colors come back with a reload
				SP:ShowSPDialog({
					key = "loadcustomlook", title = "Bring Back Your Custom Look?",
					text = "Your whole Custom look comes back: its theme, every color and every look (shapes, gradients, borders and the rest)."
						.. " Your interface reloads to finish.",
					buttons = {
						{ text = "Load and Reload", onClick = function() SP:ThemeLoadCustom(); ReloadUI() end },
						{ text = "Cancel" },
					},
				})
				return
			end
			SP:ThemeLoadCustom()
		elseif self.kind == "mine" then
			SP:ThemePickMine(self.mineId)
		else
			SP:SetThemeGlobal(self.key)
		end
		TC.Rerender()
	end)
	if p.key == "custom" then
		Core:AttachTooltip(c, "Custom", "Your unsaved changes. Click to bring them back when another card is in use; save them as a theme to keep them.")
	elseif p.mine then
		Core:AttachTooltip(c, p.label, "One of Your Themes: gives exactly this look, on any of your characters.")
	else
		Core:AttachTooltip(c, p.label, "A preset: applies exactly this look to everything on this tab. Your unsaved changes wait on the Custom card.")
	end
	return c
end

-- buttons along the bottom right of a card: { label, onClick, gold }
function TC.CardButtons(c, defs)
	for i = 1, #c.btns do c.btns[i]:Hide() end
	local x = -12
	for i = #defs, 1, -1 do
		local d = defs[i]
		local b = c.btns[i]
		if not b then
			b = Core:MakeButton(c, d[1], 60, false, nil)
			c.btns[i] = b
		end
		b.text:SetText(d[1])
		b:SetWidth(max(60, b.text:GetStringWidth() + 26))
		b:SetHeight(22)
		b.spTone = d[3] and "help" or nil
		b.spPaint(false)
		b:SetScript("OnClick", function() if not InCombatLockdown() then d[2]() end end)
		b:ClearAllPoints()
		b:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", x, 10)
		b:Show()
		x = x - b:GetWidth() - 8
	end
	return #defs > 0
end

-- one card laid out: title, the small line under it, the text, the buttons
function TC.LayCard(c, W, y, title, sub, desc, buttons)
	c.title:SetText(title)
	if sub then c.sub:SetText(sub); c.sub:Show() else c.sub:Hide() end
	c.desc:ClearAllPoints()
	c.desc:SetPoint("TOPLEFT", sub and c.sub or c.title, "BOTTOMLEFT", 0, sub and -3 or -4)
	local dh = Fit(c.desc, W - 148 - 12 - 90, desc)
	local has = TC.CardButtons(c, buttons or {})
	local h = 12 + ceil(c.title:GetStringHeight()) + (sub and (3 + ceil(c.sub:GetStringHeight())) or 0) + 4 + dh + 12
	if has then h = h + 30 end
	h = max(60, h)
	c:SetSize(W, h)
	c:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
	pickCards[#pickCards + 1] = c
	return y + h + 6
end

function TC.SubLabel(key, y, W, label, note)
	local f = Keep(key, function()
		local x = CreateFrame("Frame", nil, page.body)
		x.label = Tag(x)
		x.label:SetPoint("TOPLEFT", x, "TOPLEFT", 2, -2)
		x.note = Text(x, "rowDim")
		x.note:SetPoint("TOPLEFT", x.label, "BOTTOMLEFT", 0, -3)
		return x
	end)
	SetTag(f.label, label, "accentHi")
	local nh = Fit(f.note, W - 4, note)
	local h = 2 + ceil(f.label:GetStringHeight()) + 3 + nh + 8
	f:SetSize(W, h)
	f:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
	return y + h
end

function TC.ChangesText(base)
	local list = SP:ThemeChanges()
	if #list == 0 then
		return "Your changes on top of " .. base .. ". Pick another card and they wait here until you save or discard them."
	end
	local shown = {}
	for i = 1, min(3, #list) do shown[i] = list[i] end
	local s = #list .. (#list == 1 and " change" or " changes") .. " on top of " .. base .. ": " .. table.concat(shown, ", ")
	if #list > 3 then s = s .. " and " .. (#list - 3) .. " more" end
	return s .. "."
end

local function RenderPicker(y, W)
	for i = #pickCards, 1, -1 do pickCards[i] = nil end
	y = TC.SubLabel("pick:presetslabel", y, W, "PRESETS", "Fixed looks: picking one always gives exactly this. They never change.")
	for _, p in ipairs(PICKS) do
		local c = Keep("pick:" .. p.key, function() return NewPickCard(p) end)
		c.kind, c.mineId = "preset", nil
		SetTag(c.kindTag, "PRESET", "accent")
		y = TC.LayCard(c, W, y, p.label, nil, p.desc, nil)
	end
	y = y + 6
	y = TC.SubLabel("pick:minelabel", y, W, "YOUR THEMES", "Change anything below and it becomes your Custom look. Save it to keep it as your own theme, on every character.")
	-- the Custom card: unsaved changes (in use, or waiting)
	if CustomCardShown() then
		local c = Keep("pick:custom", function() return NewPickCard({ key = "custom", label = "Custom" }) end)
		c.kind, c.mineId = "custom", nil
		local th = SP:ThemeCustomOf()
		local _, card = SP:ThemeChanges()
		local inUse = SP:ThemeIsCustom()
		if th then
			SetTag(c.kindTag, "CHANGED", "help")
			y = TC.LayCard(c, W, y, th.name, nil, TC.ChangesText(th.name), {
				{ inUse and "Undo Changes" or "Discard", function() SP:ThemeDiscard(); TC.Rerender() end },
				{ "Save as New...", function() TC.SaveAsDialog(th.name .. " 2") end },
				{ "Update " .. th.name, function() SP:ThemeUpdate(); TC.Rerender() end, true },
			})
		else
			SetTag(c.kindTag, "NOT SAVED", "help")
			y = TC.LayCard(c, W, y, "Custom", nil, TC.ChangesText(TC.PresetOf(card)), {
				{ "Discard", function() SP:ThemeDiscard(); TC.Rerender() end },
				{ "Save as Theme...", function() TC.SaveAsDialog("") end, true },
			})
		end
	end
	for _, th in ipairs(SP:ThemeMine()) do
		local id = th.id
		local c = Keep("pick:mine:" .. id, function() return NewPickCard({ key = "mine:" .. id, label = th.name, mine = true }) end)
		c.kind, c.mineId, c.key = "mine", id, "mine:" .. id
		SetTag(c.kindTag, nil)
		local sub = "BASED ON " .. strupper(TC.PRESET_LABEL[th.base] or "Standard")
			.. (th.updated and ("  ·  SAVED " .. strupper(date("%b %d", th.updated))) or "")
		y = TC.LayCard(c, W, y, th.name, sub, TC.MINE_DESC, {
			{ "Share", function() TC.ShareDialog(th) end },
			{ "Rename", function() TC.RenameDialog(th) end },
			{ "Delete", function() TC.DeleteDialog(th) end },
		})
	end
	-- Save current look / Import
	local row = Keep("pick:minebuttons", function()
		local f = CreateFrame("Frame", nil, page.body)
		f.save = Core:MakeButton(f, "+  Save Current Look as a Theme", 240, false, "help")
		f.save:SetHeight(26)
		f.save:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		f.import = Core:MakeButton(f, "Import Theme...", 140, false)
		f.import:SetHeight(26)
		f.import:SetPoint("LEFT", f.save, "RIGHT", 8, 0)
		f.save:SetScript("OnClick", function() if not InCombatLockdown() then TC.SaveAsDialog("") end end)
		f.import:SetScript("OnClick", function() if not InCombatLockdown() then TC.ImportDialog() end end)
		Core:AttachTooltip(f.save, "Save Current Look as a Theme", "Your whole look from this tab, under a name: pick it any time, on any of your characters.")
		Core:AttachTooltip(f.import, "Import Theme", "Add a theme someone shared with you (a code that starts with SPT1:).")
		return f
	end)
	row:SetSize(W, 30)
	row:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -(y + 2))
	y = y + 34
	-- the Custom line
	customLine = Keep("customline", function()
		local f = CreateFrame("Frame", nil, page.body)
		f.text = Text(f, "rowDim")
		f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -4)
		return f
	end)
	local h1 = Fit(customLine.text, W - 24, CUSTOM_ON)
	local h2 = Fit(customLine.text, W - 24, CUSTOM_OFF)
	customLine.on, customLine.off = CUSTOM_ON, CUSTOM_OFF
	customLine:SetSize(W, max(h1, h2) + 8)
	customLine:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
	return y + max(h1, h2) + 8
end

local function PaintPicker()
	local card = SP:ThemeCard()
	local custom = SP:ThemeIsCustom()
	local mode = SP:ThemeField("showAs") or "both"
	for i = 1, #pickCards do
		local c = pickCards[i]
		local base, cpal
		if c.kind == "custom" then
			c.selected = custom
			base, cpal = SP:ThemeCustomLook()
		elseif c.kind == "mine" then
			c.selected = (not custom) and card == c.key
			local th = SP:ThemeMineById(c.mineId)
			local f = th and th.flat or {}
			base = f["t.global"] or "standard"
			cpal = f["t.palette"]
		else
			c.selected = (not custom) and card == c.key
			base, cpal = c.key, nil
		end
		PaintCard(c)
		if c.selected then SetTag(c.tag, "IN USE", "accentHi") else SetTag(c.tag, nil) end
		local minimal = (base == "minimal")
		for e = 1, 4 do
			local r, g, b
			if base == "standard" then
				if cpal then r, g, b = SP:ThemePaletteRGB(cpal, e) else r, g, b = StdDuration(e) end
			else
				r, g, b = SP:ThemePaletteRGB(cpal or "shamanpower", e)
			end
			PaintSlot(c.slots[e], minimal, mode, c.files[e], CODES[e], r, g, b, false)
			SetBar(c.bars[e], FILL[e], r, g, b)
		end
	end
	if customLine then customLine.text:SetText(custom and customLine.on or customLine.off) end
end

-- ---------------------------------------------------------------------------
-- 3. The picked theme's own options
-- ---------------------------------------------------------------------------
local SHOW_AS = {
	{ key = "both", label = "Letters + faint icon" },
	{ key = "letters", label = "Letters" },
	{ key = "tint", label = "One-color icon" },
	{ key = "mini", label = "Small icon" },
}

local function NewShowCard(sa)
	local c = NewCard(page.body)
	local I = Icons()
	c.slots = { NewSlot(c, 30), NewSlot(c, 30) }
	c.slots[1]:SetPoint("TOPRIGHT", c, "TOP", -4, -12)
	c.slots[2]:SetPoint("TOPLEFT", c, "TOP", 4, -12)
	c.files = { I.totems[1], I.totems[2] }
	c.title = Text(c, "row")
	c.title:SetJustifyH("CENTER")
	c.title:SetPoint("TOP", c, "TOP", 0, -52)
	c.key = sa.key
	c:SetScript("OnClick", function()
		if InCombatLockdown() then return end
		local v = (sa.key ~= "both") and sa.key or nil
		if SP:ThemeField("showAs") ~= v then SP:SetThemeField("showAs", v) end
		PageChanged()
	end)
	Core:AttachTooltip(c, "Show Icons As: " .. sa.label, "How each flat box shows which totem it is. The full name is always in the tooltip.")
	return c
end

local function RenderThemeOptions(y, W)
	local cap = Keep("showas:caption", function()
		local f = CreateFrame("Frame", nil, page.body)
		f.label = Text(f, "row")
		f.label:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -2)
		f.label:SetText(BLOCKS.options.desc)
		f.desc = Text(f, "rowDim")
		f.desc:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 0, -4)
		return f
	end)
	local dh = Fit(cap.desc, W - 24, BLOCKS.options.note)
	local ch = 2 + ceil(cap.label:GetStringHeight()) + 4 + dh + 8
	cap:SetSize(W, ch)
	cap:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
	y = y + ch
	local gap = 8
	local cw = floor((W - 3 * gap) / 4)
	local tallest = 0
	for i, sa in ipairs(SHOW_AS) do
		local c = Keep("showas:" .. sa.key, function() return NewShowCard(sa) end)
		showCards[i] = c
		local th = Fit(c.title, cw - 16, sa.label)
		tallest = max(tallest, th)
		c:SetPoint("TOPLEFT", page.body, "TOPLEFT", (i - 1) * (cw + gap), -y)
		c.tw = cw
	end
	local h = 52 + tallest + 12
	for i = 1, #SHOW_AS do showCards[i]:SetSize(showCards[i].tw, h) end
	y = y + h + 10
	return y
end

local function PaintThemeOptions()
	local sel = SP:ThemeField("showAs") or "both"
	for i = 1, #showCards do
		local c = showCards[i]
		c.selected = (c.key == sel)
		PaintCard(c)
		for k = 1, 2 do
			-- the element colors the bars use right now, whatever theme or palette is in use
			local r, g, b = SP:ThemeElement("tb.boxes", k)
			PaintSlot(c.slots[k], true, c.key, c.files[k], CODES[k], r, g, b, false)
		end
	end
end

-- ---------------------------------------------------------------------------
-- 4. Element Colors
-- ---------------------------------------------------------------------------
local PALETTE_CARDS = {
	{ key = "classic", label = "Classic", sub = "Brown Earth: the colors ShamanPower always had. The default on Anniversary." },
	{ key = "blizzard", label = "Blizzard", sub = "Green Earth and purple Air, from Blizzard's totem bar. The default on WoW: Forever." },
	{ key = "shamanpower", label = "ShamanPower", sub = "The colors of the ShamanPower logo." },
	{ key = "custom", label = "Custom", sub = "Your own four colors: click a color to change it." },
}

local function PickPalette(key)
	if InCombatLockdown() then return end
	local field = SP:ThemeField("palette")
	if SP:ThemeGlobal() ~= "standard" then
		-- the theme's own palette is no change
		local v = (key ~= "shamanpower") and key or nil
		if field ~= v then SP:SetThemeField("palette", v) end
	elseif not (field == nil and key == AppearancePalette()) then
		if field ~= key then SP:SetThemeField("palette", key) end
	end
	PageChanged()
end

local function NewPaletteCard(p)
	local c = NewCard(page.body)
	local I = Icons()
	c.title = Text(c, "brand")
	c.title:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -10)
	c.title:SetText(p.label)
	c.tag = Tag(c)
	c.tag:SetPoint("TOPRIGHT", c, "TOPRIGHT", -12, -12)
	c.sub = Text(c, "rowDim")
	c.sub:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -4)
	c.slots, c.rings, c.bars, c.sw = {}, {}, {}, {}
	for e = 1, 4 do
		local s = NewSlot(c, 24)
		PaintSlot(s, false, nil, I.totems[e], nil, 1, 1, 1, false)
		c.slots[e] = s
		c.rings[e] = NewEdges(s, 2, 1)
		c.bars[e] = NewBar(c, 24, 3)
		c.bars[e].track:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -3)
		local sw = NewSwatch(c, 16, 14)
		sw.name = Text(c, "tiny")
		sw.name:SetText(EL[e])
		sw.name:SetTextColor(Core:Color("textDim"))
		sw.name:SetPoint("TOPLEFT", sw, "TOPRIGHT", 6, 1)
		-- (no hex code under the name: dropped 2026-09-29)
		if p.key == "custom" then
			sw:SetScript("OnEnter", function(self) Core:SetBorderColor(self, "accent") end)
			sw:SetScript("OnLeave", function(self) Core:SetBorderColor(self, "border") end)
			sw:SetScript("OnClick", function() if not InCombatLockdown() then PickCustom(e) end end)
			Core:AttachTooltip(sw, EL[e], "Click to pick this element's Custom color.")
		else
			sw:EnableMouse(false)
		end
		c.sw[e] = sw
	end
	c.key = p.key
	c:SetScript("OnClick", function() PickPalette(p.key) end)
	Core:AttachTooltip(c, p.label, "Use these element colors everywhere a part follows the element colors. It is the Element Colors setting on Appearance.")
	return c
end

local function RenderPalettes(y, W)
	local gap = 10
	local cw = floor((W - gap) / 2)
	local rowH = 0
	for i, p in ipairs(PALETTE_CARDS) do
		local c = Keep("pal:" .. p.key, function() return NewPaletteCard(p) end)
		palCards[i] = c
		local th = ceil(c.title:GetStringHeight())
		local sh = Fit(c.sub, cw - 24, p.sub)
		local yI = 10 + th + 4 + sh + 12
		local x0 = floor((cw - (4 * 24 + 3 * 10)) / 2)
		local colW = floor((cw - 24) / 4)
		for e = 1, 4 do
			local s = c.slots[e]
			s:ClearAllPoints()
			s:SetPoint("TOPLEFT", c, "TOPLEFT", x0 + (e - 1) * 34, -yI)
			local sw = c.sw[e]
			sw:ClearAllPoints()
			sw:SetPoint("TOPLEFT", c, "TOPLEFT", 12 + (e - 1) * colW, -(yI + 24 + 3 + 3 + 14))
		end
		local h = yI + 24 + 6 + 14 + 22 + 8
		c:SetSize(cw, h)
		local col, row = (i - 1) % 2, floor((i - 1) / 2)
		if col == 0 and row > 0 then y = y + rowH + gap; rowH = 0 end
		c:SetPoint("TOPLEFT", page.body, "TOPLEFT", col * (cw + gap), -y)
		rowH = max(rowH, h)
	end
	-- both cards of a row the height of the taller one
	for r = 0, 1 do
		local a, b = palCards[r * 2 + 1], palCards[r * 2 + 2]
		if a and b then
			local h = max(a:GetHeight(), b:GetHeight())
			a:SetHeight(h); b:SetHeight(h)
		end
	end
	return y + rowH + 6
end

local function PaintPalettes()
	local inUse = InUsePalette()
	for i = 1, #palCards do
		local c = palCards[i]
		c.selected = (c.key == inUse)
		PaintCard(c)
		if c.selected then SetTag(c.tag, "IN USE", "accentHi") else SetTag(c.tag, nil) end
		for e = 1, 4 do
			local r, g, b = PaletteCardRGB(c.key, e)
			PaintEdges(c.rings[e], r, g, b, 1)
			SetBar(c.bars[e], FILL[e], r, g, b)
			c.sw[e].fill:SetColorTexture(r, g, b, 1)
		end
	end
end

-- ---------------------------------------------------------------------------
-- 4b. Class Colors: the set the party dots and Totem Coverage dots use, as cards
-- like Element Colors (a totem-bar preview with that set's party dots, the nine
-- classes), and Gem Dot Finish under them. The cards set the theme's default;
-- Party Dots / Coverage Dots: Class Colors (Totem Bar, Totem Coverage sections)
-- can each pick their own.
-- ---------------------------------------------------------------------------
local CC = { cards = {} }   -- the section's pieces, in one table: this file is at Lua's 200-local limit
CC.ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
CC.NAME = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
CC.PARTY = { "ROGUE", "PRIEST", "SHAMAN", "WARLOCK" }   -- the preview party, one per corner
CC.CORNER = { { "TOPLEFT", 3, -3 }, { "TOPRIGHT", -3, -3 }, { "BOTTOMLEFT", 3, 3 }, { "BOTTOMRIGHT", -3, 3 } }

function CC.RGB(set, class)
	local r, g, b = SP:ClassSetRGB(set, class)
	if r then return r, g, b end
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

function CC.Pick(key)
	if InCombatLockdown() then return end
	-- the theme's own set is no change
	local v = (key ~= SP:ThemeClassColorSetDefault()) and key or nil
	if SP:ThemeField("classColors") ~= v then SP:SetThemeField("classColors", v) end
	PageChanged()
end

-- one dot: the Dot Shape texture, its dark ring and the gem over it
function CC.NewDot(c, size, layer, class)
	local o = c:CreateTexture(nil, layer, nil, 1)
	local d = c:CreateTexture(nil, layer, nil, 2)
	local g = c:CreateTexture(nil, layer, nil, 3)
	d:SetSize(size, size)
	o:SetSize(size + 2, size + 2); o:SetPoint("CENTER", d, "CENTER", 0, 0)
	g:SetAllPoints(d); g:Hide()
	return { d = d, o = o, g = g, class = class }
end
function CC.PaintDot(p, set, tex, gem)
	local r, g, b = CC.RGB(set, p.class)
	if p.tex ~= tex then p.d:SetTexture(tex); p.o:SetTexture(tex); p.tex = tex end
	p.d:SetVertexColor(r, g, b)
	p.o:SetVertexColor(0, 0, 0, 0.9)
	if gem then p.g:SetTexture(gem); p.g:Show() else p.g:Hide() end
end

function CC.NewCard(set)
	local c = NewCard(page.body)
	local I = Icons()
	c.title = Text(c, "brand")
	c.title:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -10)
	c.title:SetText(set.label)
	c.tag = Tag(c)
	c.tag:SetPoint("TOPRIGHT", c, "TOPRIGHT", -12, -12)
	c.sub = Text(c, "rowDim")
	c.sub:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -4)
	c.slots, c.dots, c.sw = {}, {}, {}
	for e = 1, 4 do
		local s = NewSlot(c, 24)
		PaintSlot(s, false, nil, I.totems[e], nil, 1, 1, 1, false)
		c.slots[e] = s
		for k = 1, 4 do
			local p = CC.NewDot(c, 5, "OVERLAY", CC.PARTY[k])
			local at = CC.CORNER[k]
			p.d:SetPoint("CENTER", s, at[1], at[2], at[3])
			c.dots[#c.dots + 1] = p
		end
	end
	for i, class in ipairs(CC.ORDER) do
		local p = CC.NewDot(c, 10, "ARTWORK", class)
		p.name = Text(c, "tiny")
		p.name:SetText(CC.NAME[class])
		p.name:SetTextColor(Core:Color("textDim"))
		p.name:SetPoint("LEFT", p.d, "RIGHT", 5, 0)
		c.sw[i] = p
	end
	c.key = set.key
	c:SetScript("OnClick", function() CC.Pick(set.key) end)
	Core:AttachTooltip(c, set.label, "Use these class colors for the party dots and the Totem Coverage dots. Each can still pick its own in its section below (Class Colors).")
	return c
end

function CC.Render(y, W)
	local gap = 10
	local cw = floor((W - gap) / 2)
	local rowH = 0
	for i, set in ipairs(SP.CLASS_COLOR_SETS) do
		local c = Keep("cls:" .. set.key, function() return CC.NewCard(set) end)
		CC.cards[i] = c
		local th = ceil(c.title:GetStringHeight())
		local sh = Fit(c.sub, cw - 24, set.sub)
		local yI = 10 + th + 4 + sh + 12
		local x0 = floor((cw - (4 * 24 + 3 * 10)) / 2)
		for e = 1, 4 do
			local s = c.slots[e]
			s:ClearAllPoints()
			s:SetPoint("TOPLEFT", c, "TOPLEFT", x0 + (e - 1) * 34, -yI)
		end
		-- the nine classes in two rows (five, then four)
		local colW = floor((cw - 24) / 5)
		local ys = yI + 24 + 16
		for j, p in ipairs(c.sw) do
			local col, row = (j - 1) % 5, floor((j - 1) / 5)
			p.d:ClearAllPoints()
			p.d:SetPoint("TOPLEFT", c, "TOPLEFT", 12 + col * colW, -(ys + row * 18))
		end
		local h = ys + 2 * 18 + 8
		c:SetSize(cw, h)
		local col, row = (i - 1) % 2, floor((i - 1) / 2)
		if col == 0 and row > 0 then y = y + rowH + gap; rowH = 0 end
		c:SetPoint("TOPLEFT", page.body, "TOPLEFT", col * (cw + gap), -y)
		rowH = max(rowH, h)
	end
	for r = 0, 2 do
		local a, b = CC.cards[r * 2 + 1], CC.cards[r * 2 + 2]
		if a and b then
			local h = max(a:GetHeight(), b:GetHeight())
			a:SetHeight(h); b:SetHeight(h)
		end
	end
	y = y + rowH + 8
	local _, gh = Widgets:Toggle(page.body, {
		label = "Gem Dot Finish", x = 0, y = y, width = W,
		desc = "Add a dark rim and soft highlight to party dots and Totem Coverage dots. Follows Dot Shape. Does not apply to Ring. Also on Party Buff Tracker.",
		get = function() return SP.opt.dotGem == true end,
		set = function(v) SP:SetDotGem(v) end,
		onChanged = PageChanged,
	})
	return y + gh + 6
end

function CC.Paint()
	local inUse = SP:ThemeClassColorSetGlobal()
	local tex, gem = SP:DotTexture(), SP:DotGemTexture()
	for i = 1, #CC.cards do
		local c = CC.cards[i]
		c.selected = (c.key == inUse)
		PaintCard(c)
		if c.selected then SetTag(c.tag, "IN USE", "accentHi") else SetTag(c.tag, nil) end
		for _, p in ipairs(c.dots) do CC.PaintDot(p, c.key, tex, gem) end
		for _, p in ipairs(c.sw) do CC.PaintDot(p, c.key, tex, gem) end
	end
end

-- ---------------------------------------------------------------------------
-- 5. Shield Colors
-- ---------------------------------------------------------------------------
local SHIELD_CARDS = {
	-- (each sub is read when the page is drawn: WoW: Forever has no Earth Shield)
	{ key = "today", label = "Today", sub = function() return HasEarthShield() and "The blue ShamanPower has always used, on all three shields."
		or "The blue ShamanPower has always used, on both shields." end },
	{ key = "palette", label = "Follow Palette", sub = function() return HasEarthShield() and "Lightning Shield in the logo blue, Water Shield and Earth Shield in the element colors' Water and Earth."
		or "Lightning Shield in the logo blue, Water Shield in the element colors' Water." end },
	{ key = "magic", label = "WoW Magic Blue", sub = function() return HasEarthShield() and "All three in the blue WoW puts on magic auras."
		or "Both in the blue WoW puts on magic auras." end, wow = true },
}

local function PickShield(key)
	if InCombatLockdown() then return end
	local v = (key ~= ShieldDefault()) and key or nil
	if SP:ThemeField("shield") ~= v then SP:SetThemeField("shield", v) end
	PageChanged()
end

local function NewShieldCard(sc)
	local c = NewCard(page.body)
	local I = Icons()
	c.title = Text(c, "brand")
	c.title:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -10)
	c.title:SetText(sc.label)
	c.wow = Tag(c)
	c.wow:SetPoint("LEFT", c.title, "RIGHT", 8, 0)
	if sc.wow then SetTag(c.wow, "WOW", "accentHi") end
	c.tag = Tag(c)
	c.tag:SetPoint("TOPRIGHT", c, "TOPRIGHT", -12, -12)
	c.sub = Text(c, "rowDim")
	c.sub:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -4)
	local list = { { "lightning", I.lightning, 3 }, { "water", I.water, 3 } }
	if HasEarthShield() then list[3] = { "earth", I.earthShield, 6 } end
	c.parts = {}
	for j, sdef in ipairs(list) do
		local s = NewSlot(c, 26)
		PaintSlot(s, false, nil, sdef[2], nil, 1, 1, 1, false)
		local num = HudText(s.over, "timers", 12, "OUTLINE")
		num:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -1, 2)
		num:SetText(tostring(sdef[3]))
		local segs = NewSegments(c, 3, 26, 4, 2)
		c.parts[j] = { which = sdef[1], s = s, num = num, segs = segs }
	end
	c.key = sc.key
	c:SetScript("OnClick", function() PickShield(sc.key) end)
	Core:AttachTooltip(c, sc.label, "The shield colors everywhere a part has Shield Colors (Use Theme's).")
	return c
end

local function RenderShields(y, W)
	local gap = 10
	local cw = floor((W - 2 * gap) / 3)
	local tallest = 0
	for i, sc in ipairs(SHIELD_CARDS) do
		local c = Keep("shield:" .. sc.key, function() return NewShieldCard(sc) end)
		shieldCards[i] = c
		local th = ceil(c.title:GetStringHeight())
		local sh = Fit(c.sub, cw - 24, type(sc.sub) == "function" and sc.sub() or sc.sub)
		local yI = 10 + th + 4 + sh + 12
		local n = #c.parts
		local colW = floor((cw - 24) / n)
		for j, p in ipairs(c.parts) do
			local x = 12 + (j - 1) * colW + floor((colW - 26) / 2)
			p.s:ClearAllPoints()
			p.s:SetPoint("TOPLEFT", c, "TOPLEFT", x, -yI)
			for k = 1, p.segs.n do p.segs[k]:ClearAllPoints() end
			PlaceSegments(p.segs, c, "TOPLEFT", x, -(yI + 26 + 4))
		end
		c.h = yI + 26 + 4 + 4 + 12
		tallest = max(tallest, c.h)
		c:SetPoint("TOPLEFT", page.body, "TOPLEFT", (i - 1) * (cw + gap), -y)
		c.cw = cw
	end
	for i = 1, #SHIELD_CARDS do shieldCards[i]:SetSize(shieldCards[i].cw, tallest) end
	return y + tallest + 6
end

local function PaintShields()
	local inUse = SP:ThemeField("shield") or ShieldDefault()
	for i = 1, #shieldCards do
		local c = shieldCards[i]
		c.selected = (c.key == inUse)
		PaintCard(c)
		if c.selected then SetTag(c.tag, "IN USE", "accentHi") else SetTag(c.tag, nil) end
		for _, p in ipairs(c.parts) do
			local r, g, b = ShieldCardRGB(c.key, p.which)
			p.num:SetTextColor(r, g, b)
			PaintSegments(p.segs, 3, r, g, b)
		end
	end
end

-- ---------------------------------------------------------------------------
-- 5b. Shapes & Textures: the same settings as on each part's own page (named
-- in each row's line). A theme card never changes them; the first card of
-- each row is today's look.
-- ---------------------------------------------------------------------------
local shapeCards = {}   -- [row key] = { card, card, ... }
-- any bar on Rounded or Circle (Keep Borders Square shows then)
local function IconShapedAny()
	for _, kind in ipairs({ "totem", "cooldown", "ready" }) do
		local k = SP.IconShapeOf and SP:IconShapeOf(kind)
		if k == "rounded" or k == "circle" then return true end
	end
	return false
end
local SHAPE_ROWS = {
	{ key = "dot", label = "Dot Shape", list = function() return SP.DOT_SHAPES end,
	  note = "The party dots and Totem Coverage's dots. Also on Party Buff Tracker.",
	  get = function() return SP.opt.dotShape or "default" end, set = function(k) SP:SetDotShape(k) end },
	{ key = "glow", label = "Glow Shape", list = function() return SP.GLOW_SHAPES end,
	  note = "The pulse flash and the ready and alert glows. Also on Totem Bar > Duration Bars and Ready Reminders.",
	  get = function() return SP.opt.glowShape or "default" end, set = function(k) SP:SetGlowShape(k) end },
	{ key = "edge", label = "Frame Edge", list = function() return SP.FRAME_EDGES end,
	  note = "The totem bar, the cooldown bar and ShamanPower's panels. Also on Appearance > Totem Bar and Cooldown Bar.",
	  get = function() return SP.opt.frameEdge or "default" end, set = function(k) SP:SetFrameEdge(k) end },
	-- Icon Shape: one per bar (the same settings as on each bar's own page)
	{ key = "icon", iconKind = "totem", label = "Totem Bar Icon Shape", list = function() return SP.ICON_SHAPES end,
	  note = "The totem bar's buttons, its flyouts, pop-outs and Drop All (ShamanPower Minimal's boxes too). Also on Appearance > Totem Bar.",
	  get = function() return SP:IconShapeOf("totem") or "default" end, set = function(k) SP:SetIconShape(k, "totem") end },
	{ key = "iconcd", iconKind = "cooldown", label = "Cooldown Bar Icon Shape", list = function() return SP.ICON_SHAPES end,
	  note = "The cooldown bar's buttons and its shield and imbue flyouts (ShamanPower Minimal's boxes too). Also on the Cooldown Bar page (Bar).",
	  get = function() return SP:IconShapeOf("cooldown") or "default" end, set = function(k) SP:SetIconShape(k, "cooldown") end },
	{ key = "iconrr", iconKind = "ready", label = "Ready Reminders Icon Shape", list = function() return SP.ICON_SHAPES end,
	  search = "Keep Borders Square",
	  note = "Ready Reminders' icons (ShamanPower Minimal's boxes too); the glow keeps Glow Shape. Also on Ready Reminders.",
	  get = function() return SP:IconShapeOf("ready") or "default" end, set = function(k) SP:SetIconShape(k, "ready") end,
	  extra = function(y, W)
		-- borders round a Rounded / Circle icon follow its shape, unless this is on
		if not IconShapedAny() then return y end
		local _, h = Widgets:Toggle(page.body, {
			label = "Keep Borders Square", x = 0, y = y, width = W,
			desc = "Keep borders square around Rounded or Circle icons. Applies to all bars and Ready Reminders. Also on Appearance > Totem Bar, Cooldown Bar and Ready Reminders.",
			get = function() return SP.opt.iconBordersSquare == true end,
			set = function(v) SP:SetIconBordersSquare(v) end,
			onChanged = PageChanged,
		})
		return y + h + 10
	  end },
}
-- Gradients (Miska's request): the bars' fill and the outlines, shaded. The same
-- settings as Bar Gradient on Totem Bar > Duration Bars and Outline Gradient on
-- Appearance > Totem Bar. Two-Tone and Fade Out get their own rows under the cards.
local GRAD_COLORS = { { 0.2, 0.8, 0.2 }, { 0.9, 0.3, 0.1 }, { 0.2, 0.5, 0.9 }, { 0.8, 0.8, 0.8 } }   -- today's duration bar colors
-- Bar Gradient's directions, one per kind of bar: area, label, what it shades
local BAR_DIRECTIONS = {
	{ "duration", "Duration Bars Direction", "the totem duration bars" },
	{ "pulse", "Pulse Bars Direction", "the pulse bars" },
	{ "cooldown", "Cooldown Bar Direction", "the cooldown bar's progress bars" },
	{ "other", "Ready Reminders Bar Direction", "Ready Reminders' bar" },
}
local function GradientExtra(field, part)
	return function(y, W)
		local o = SP.opt
		local kind = o[field]
		local function changed() SP:RefreshGradients() end
		if kind and field == "barGradient" then
			-- each kind of bar has its own direction
			for _, d in ipairs(BAR_DIRECTIONS) do
				local area = d[1]
				local _, hd = Widgets:Dropdown(page.body, {
					label = d[2], x = 0, y = y, width = W,
					desc = "Where the gradient starts on " .. d[3] .. ". Along the Bar follows each bar: left to right, or bottom to top on a vertical bar.",
					values = function() return (SP:GradientDirectionValues(field)) end,
					order = function() return select(2, SP:GradientDirectionValues(field)) end,
					get = function() return SP:BarGradientDirection(area) end,
					set = function(v) SP:SetBarGradientDirection(area, v) end,
					onChanged = PageChanged,
				})
				y = y + hd + 6
			end
		elseif kind then
			local _, hd = Widgets:Dropdown(page.body, {
				label = part .. " Gradient Direction", x = 0, y = y, width = W,
				desc = (field == "outlineGradient")
					and "Where the gradient starts: from the top edge down by default, or from the bottom, the left or the right."
					or "Where the gradient starts. Along the Bar follows each bar: left to right, or bottom to top on a vertical bar. The others are the same on every bar.",
				values = function() return (SP:GradientDirectionValues(field)) end,
				order = function() return select(2, SP:GradientDirectionValues(field)) end,
				get = function() return o[field .. "Direction"] or "default" end,
				set = function(v) SP:SetGradientField(field .. "Direction", v) end,
				onChanged = PageChanged,
			})
			y = y + hd + 6
		end
		if kind == "two" then
			local _, h1 = Widgets:Toggle(page.body, {
				label = "Start From Each " .. part .. "'s Own Color", x = 0, y = y, width = W,
				desc = "On: each " .. strlower(part) .. " starts in its own color (Earth green, Fire red...) and shades into the second color. Off: every one starts in the first color below.",
				get = function() return o[field .. "Color1"] == nil end,
				set = function(v) if v then o[field .. "Color1"] = nil else o[field .. "Color1"] = { r = 0.25, g = 0.66, b = 0.96 } end; changed() end,
				onChanged = PageChanged,
			})
			y = y + h1 + 6
			if o[field .. "Color1"] then
				local _, h2 = Widgets:Color(page.body, {
					label = part .. " First Color", x = 0, y = y, width = W,
					get = function() local c = o[field .. "Color1"] or {}; return c.r or 1, c.g or 1, c.b or 1, 1 end,
					set = function(r, g, b) o[field .. "Color1"] = { r = r, g = g, b = b }; changed() end,
					onChanged = PageChanged,
				})
				y = y + h2 + 6
			end
			local _, h3 = Widgets:Color(page.body, {
				label = part .. " Second Color", x = 0, y = y, width = W,
				desc = "The color the gradient shades into. WoW gold by default.",
				get = function() local c = o[field .. "Color2"] or {}; return c.r or 1, c.g or 0.82, c.b or 0, 1 end,
				set = function(r, g, b) o[field .. "Color2"] = { r = r, g = g, b = b }; changed() end,
				onChanged = PageChanged,
			})
			y = y + h3 + 10
		elseif kind == "fade" then
			local _, h = Widgets:Slider(page.body, {
				label = part .. " Fade To", x = 0, y = y, width = W, min = 0, max = 1, step = 0.01, isPercent = true,
				desc = "How much of the color is left at the faded end: 0% fades right into the game world.",
				get = function() local f = o[field .. "Fade"]; if f == nil then return 0.15 end return f end,
				set = function(v) o[field .. "Fade"] = v; changed() end,
				onChanged = PageChanged,
			})
			y = y + h + 10
		end
		return y
	end
end
SHAPE_ROWS[#SHAPE_ROWS + 1] = { key = "bargrad", label = "Bar Gradient", list = function() return SP.GRADIENTS end,
	search = "Gradient Direction Duration Bars Direction Pulse Bars Direction Cooldown Bar Direction Ready Reminders Bar Direction"
		.. " Two-Tone First Color Second Color Fade To Duration Bar Background",
	note = "Duration and pulse bars, the cooldown bar's progress bars and Ready Reminders' bar (never Shield Charges). Also on Totem Bar > Duration Bars.",
	get = function() return SP.opt.barGradient or "default" end, set = function(k) SP:SetGradientField("barGradient", k) end,
	extra = function(y, W)
		y = GradientExtra("barGradient", "Bar")(y, W)
		-- the duration bars' dark track: the same setting as on Totem Bar > Duration Bars
		local _, h = Widgets:Toggle(page.body, {
			label = "Duration Bar Background", x = 0, y = y, width = W,
			desc = "The dark track behind the duration bars. Turn it off to show only the colored bar, like the pulse bars. The same setting as on Totem Bar > Duration Bars.",
			get = function() return SP.opt.durationBarBackground ~= false end,
			set = function(v) SP:SetDurationBarBackground(v) end,
			onChanged = PageChanged,
		})
		return y + h + 10
	end }
SHAPE_ROWS[#SHAPE_ROWS + 1] = { key = "outgrad", label = "Outline Gradient", list = function() return SP.GRADIENTS end,
	search = "Outline Gradient Direction Two-Tone First Color Second Color Fade To",
	note = "The element-colored borders round each totem, and the totem bar, cooldown bar and panel borders. Also on Appearance > Totem Bar.",
	get = function() return SP.opt.outlineGradient or "default" end, set = function(k) SP:SetGradientField("outlineGradient", k) end,
	extra = GradientExtra("outlineGradient", "Outline") }

-- Shield Charges: each shield's look, today's bar or one orb per charge (the same
-- setting as Lightning / Water / Earth Shield Look on Shield Charges). Earth Shield
-- is Anniversary only.
local ORB_TEX = "Interface\\AddOns\\ShamanPower\\Media\\Textures\\"
local ORB_ICON_FILE = { "Orbs_Icon_Lightning_3", "Orbs_Icon_Water_3", "Orbs_Icon_Earth_6" }
local ORB_STORM_FILE = { "Orbs_Storm_LS_3", "Orbs_Storm_WS_3", "Orbs_Storm_ES_6" }
local ORB_EXTRA = {
	[2] = { { "tide", "Tide Orbs", "Orbs_Tide_WS_3" }, { "bubble", "Bubble Orbs", "Orbs_Bubble_WS_3" }, { "foam", "Foam Orbs", "Orbs_Foam_WS_3" } },
	[3] = { { "stone", "Stone Ring Orbs", "Orbs_Stone_ES_6" }, { "leaf", "Leaf Wreath Orbs", "Orbs_Leaf_ES_6" }, { "spike", "Spiked Stone Orbs", "Orbs_Spike_ES_6" } },
}
local orbCardCache = {}
local function OrbCards(which)
	local cards = orbCardCache[which]
	if cards then return cards end
	local n = (which == 3) and 6 or 3
	cards = {
		{ key = "bar",   label = "Bar (default)", count = n },
		{ key = "glow",  label = "Glowing Orbs", count = n, file = ORB_TEX .. "Orbs_Glow_" .. n },
		{ key = "icon",  label = "Shield Icon Orbs", count = n, file = ORB_TEX .. ORB_ICON_FILE[which], white = true },
		{ key = "flat",  label = "Flat Orbs", count = n, file = ORB_TEX .. "Orbs_Flat_" .. n },
		-- Miska's Water Shield orb is a plain picture; every other Storm look glows additively
		{ key = "storm", label = "Storm Orbs", count = n, file = ORB_TEX .. ORB_STORM_FILE[which], white = true, add = which ~= 2, storm = true },
	}
	for _, e in ipairs(ORB_EXTRA[which] or {}) do
		cards[#cards + 1] = { key = e[1], label = e[2], count = n, file = ORB_TEX .. e[3], white = true, add = true, storm = true }
	end
	orbCardCache[which] = cards
	return cards
end
local function ShieldBarShown()
	local s = SP.opt and SP.opt.shieldChargeDisplay
	return SP.ShieldChargesLoaded and s and s.showChargeBar and true or false
end
local ORB_ROW = {
	{ label = "Lightning Shield Charges", note = "Lightning Shield's charges: the bar, or one orb per charge. Also on Shield Charges (Lightning Shield Look)." },
	{ label = "Water Shield Charges", note = "Water Shield's charges: the bar, or one orb per charge. Also on Shield Charges (Water Shield Look)." },
	{ label = "Earth Shield Charges", note = "Earth Shield's charges (on your Earth Shield target): the bar, or one orb per charge. Also on Shield Charges (Earth Shield Look)." },
}
for which = 1, 3 do
	SHAPE_ROWS[#SHAPE_ROWS + 1] = { key = "orbs" .. which, orbs = which, label = ORB_ROW[which].label, note = ORB_ROW[which].note,
		list = function() return OrbCards(which) end,
		-- Earth Shield: Anniversary only (WoW: Forever has none)
		shown = function() return ShieldBarShown() and (which < 3 or not SPCompat.FOREVER) end,
		get = function() return SP.GetShieldLook and SP:GetShieldLook(which) or "bar" end,
		set = function(k) if SP.SetShieldLook then SP:SetShieldLook(which, k) end end }
end
-- Shield Charges' own gradient and colors (never Bar Gradient's): the same
-- settings as Colors & Gradient on Shield Charges
local CHARGE_NAMES = { "Lightning Shield Charge Color", "Water Shield Charge Color", "Earth Shield Charge Color" }
SHAPE_ROWS[#SHAPE_ROWS + 1] = { key = "chargegrad", label = "Charge Bar Gradient", list = function() return SP.GRADIENTS end,
	search = "Charge Bar Gradient Direction Lightning Shield Charge Color Water Shield Charge Color Earth Shield Charge Color Default Charge Colors",
	note = "Shield Charges' own: the charge bar, the Glowing and Flat orbs and the cooldown bar's Shield Charge Bar. Bar Gradient never touches them. Also on Shield Charges.",
	shown = function() return ShieldBarShown() end,
	get = function() return SP.opt.chargeGradient or "default" end, set = function(k) SP:SetGradientField("chargeGradient", k) end,
	extra = function(y, W)
		y = GradientExtra("chargeGradient", "Charge Bar")(y, W)
		-- each shield's own charge color (purple Water Shield? sure)
		for w = 1, (SPCompat.FOREVER) and 2 or 3 do
			local _, h = Widgets:Color(page.body, {
				label = CHARGE_NAMES[w], x = 0, y = y, width = W,
				desc = "The color of this shield's charge bar and orbs (Shield Icon Orbs keep their icons). The same setting as on Shield Charges.",
				get = function() if SP.ShieldChargeColorOf then local r, g, b = SP:ShieldChargeColorOf(w); return r, g, b, 1 end return 0.2, 0.6, 1, 1 end,
				set = function(r, g, b) if SP.SetShieldChargeColor then SP:SetShieldChargeColor(w, r, g, b) end end,
				onChanged = PageChanged,
			})
			y = y + h + 6
		end
		local _, bh = Widgets:Button(page.body, {
			label = "Default Charge Colors", buttonText = "Default Charge Colors", x = 0, y = y, width = W,
			desc = "Each shield's charges back to their usual color.",
			func = function() if SP.SetShieldChargeColor then for w = 1, 3 do SP:SetShieldChargeColor(w, nil) end end end,
			onChanged = PageChanged,
		})
		return y + bh + 10
	end }
-- Target Tracker's two looks: the same settings as each spell's right-click menu > Look on
-- Target Tracker (Look When Missing on the three shocks, Icon Edge on all four spells); the
-- cards are drawn by Target Tracker itself, so each shows exactly what the spell looks like
local TT_SHOCKS, TT_ALL = { "fs", "frs", "ss" }, { "fs", "frs", "ss", "purge" }
SHAPE_ROWS[#SHAPE_ROWS + 1] = { key = "ttmiss", tt = "miss", label = "Target Tracker Look When Missing",
	note = "How the gray warning looks while your shock isn't on your target: Flame Shock, Frost Shock and Stormstrike. Also on Target Tracker (right-click a spell > Look).",
	shown = function() return SP.TT_MISS_LOOKS ~= nil end, list = function() return SP.TT_MISS_LOOKS end,
	get = function() return SP.TT_Get and SP:TT_Get("fs", "missLook") or "edge" end,
	set = function(k) for _, key in ipairs(TT_SHOCKS) do SP:TT_Set(key, "missLook", k) end end }
SHAPE_ROWS[#SHAPE_ROWS + 1] = { key = "ttedge", tt = "edge", label = "Target Tracker Icon Edge",
	note = "The edge around each spell's icon: Flame Shock, Frost Shock, Stormstrike and Purge. Spell Color: each spell's own color. Also on Target Tracker (right-click a spell > Look).",
	shown = function() return SP.TT_ICON_EDGES ~= nil end, list = function() return SP.TT_ICON_EDGES end,
	get = function() return SP.TT_Get and SP:TT_Get("fs", "border") or "thin" end,
	set = function(k) for _, key in ipairs(TT_ALL) do SP:TT_Set(key, "border", k) end end }
-- Next Shock's look (D49): the same setting as Look When It's Time to Cast in Flame Shock's right-click menu (Target Tracker)
SHAPE_ROWS[#SHAPE_ROWS + 1] = { key = "ttcast", tt = "cast", label = "Next Shock Look When It's Time to Cast",
	note = "How Next Shock's Flame Shock looks when it's time to cast it: while your target doesn't have yours, and again just before yours runs out. Also in Flame Shock's right-click menu on Target Tracker, under Next Shock.",
	shown = function() return SP.TT_CAST_LOOKS ~= nil end, list = function() return SP.TT_CAST_LOOKS end,
	get = function() return SP.TT_Get and SP:TT_Get("ns", "castLook") or "gold" end,
	set = function(k) if SP.TT_Set then SP:TT_Set("ns", "castLook", k) end end }
local PREVIEW_H = 44
local DOT_CLASSES = { "ROGUE", "WARRIOR", "PRIEST", "HUNTER" }

-- the picture on a card: the shape on real icons, as the part draws it
local function BuildShapePreview(c, row, s)
	local I = Icons()
	local p = CreateFrame("Frame", nil, c)
	p:SetSize(120, PREVIEW_H)
	c.preview = p
	if row.tt then
		-- Target Tracker draws its own sample (its icon parts, with this look)
		if SP.TT_LookSample then SP:TT_LookSample(p, row.tt, s.key) end
	elseif row.key == "dot" then
		local ic = p:CreateTexture(nil, "ARTWORK")
		ic:SetSize(30, 30); ic:SetPoint("CENTER", p, "CENTER", 0, 0)
		ic:SetTexture(I.soe); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local spots = { { "TOPLEFT", -2, 2 }, { "TOPRIGHT", 2, 2 }, { "BOTTOMLEFT", -2, -2 }, { "BOTTOMRIGHT", 2, -2 } }
		for i = 1, 4 do
			local o = p:CreateTexture(nil, "OVERLAY", nil, 1)
			o:SetTexture(s.file); o:SetVertexColor(0, 0, 0, 0.9); o:SetSize(9, 9)
			o:SetPoint("CENTER", ic, spots[i][1], spots[i][2], spots[i][3])
			local d = p:CreateTexture(nil, "OVERLAY", nil, 2)
			d:SetTexture(s.file); d:SetSize(7, 7); d:SetPoint("CENTER", o, "CENTER", 0, 0)
			if i == 4 then d:SetVertexColor(1, 0.1, 0.1) else d:SetVertexColor(ClassRGB(DOT_CLASSES[i])) end
		end
	elseif row.key == "glow" then
		local ic = p:CreateTexture(nil, "ARTWORK")
		ic:SetSize(26, 26); ic:SetPoint("CENTER", p, "CENTER", 0, 0)
		ic:SetTexture(I.tremor); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local g = p:CreateTexture(nil, "OVERLAY")
		g:SetPoint("TOPLEFT", ic, "TOPLEFT", -10, 10); g:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", 10, -10)
		g:SetTexture(s.file); g:SetBlendMode("ADD"); g:SetVertexColor(0.4, 1, 0.4); g:SetAlpha(0.9)
	elseif row.orbs then
		local n = s.count or 3
		local bar = CreateFrame("StatusBar", nil, p)
		bar:SetMinMaxValues(0, n); bar:SetValue(n - 1)
		if s.file then
			-- the strips' own proportions: Storm 2:1 (3 orbs) / 4:1 (6), the others 4:1 / 8:1
			local w = (n == 6) and 108 or 64
			local h = s.storm and ((n == 6) and 27 or 32) or ((n == 6) and 14 or 16)
			bar:SetSize(w, h); bar:SetPoint("CENTER", p, "CENTER", 0, 0)
			bar:SetStatusBarTexture(s.file)
			if s.add then bar:GetStatusBarTexture():SetBlendMode("ADD") end
			if s.white then bar:SetStatusBarColor(1, 1, 1) else bar:SetStatusBarColor(0.2, 0.6, 1.0) end
			local back = bar:CreateTexture(nil, "BACKGROUND"); back:SetAllPoints(bar)
			back:SetTexture(ORB_TEX .. (s.storm and "Orbs_StormEmpty_" or "Orbs_Empty_") .. n)
			if s.white then back:SetVertexColor(0.55, 0.6, 0.7, 0.9) else back:SetVertexColor(0.11, 0.33, 0.55, 0.9) end
		else
			local w = (n == 6) and 90 or 60
			bar:SetSize(w, 7); bar:SetPoint("CENTER", p, "CENTER", 0, 0)
			bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8"); bar:SetStatusBarColor(0.2, 0.6, 1.0)
			local back = bar:CreateTexture(nil, "BACKGROUND")
			back:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1); back:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
			back:SetColorTexture(0, 0, 0, 0.6)
			for i = 1, n - 1 do
				local d = bar:CreateTexture(nil, "OVERLAY"); d:SetColorTexture(0, 0, 0, 0.9); d:SetWidth(1)
				d:SetPoint("TOP", bar, "TOPLEFT", w * i / n, 0); d:SetPoint("BOTTOM", bar, "BOTTOMLEFT", w * i / n, 0)
			end
		end
	elseif row.key == "bargrad" then
		-- four duration bars; repainted with the page, so Two-Tone's colors and
		-- Fade Out's opacity show on the cards as they change
		local bars = {}
		for k = 1, 4 do
			local t = p:CreateTexture(nil, "ARTWORK")
			t:SetSize(96, 6); t:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -3 - (k - 1) * 11)
			local back = p:CreateTexture(nil, "BACKGROUND")
			back:SetPoint("TOPLEFT", t, "TOPLEFT", -1, 1); back:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 1, -1)
			back:SetColorTexture(0, 0, 0, 0.7)
			bars[k] = t
		end
		c.repaint = function()
			for k, t in ipairs(bars) do
				local col = GRAD_COLORS[k]
				if s.key ~= "default" then
					-- the real painter, so the card follows Gradient Direction too
					t:SetColorTexture(1, 1, 1, 1)
					SP:PaintBarGradient(t, col[1], col[2], col[3], 1, false, s.key, "duration")
				else
					t:SetColorTexture(col[1], col[2], col[3], 1)
				end
			end
		end
		c.repaint()
	elseif row.key == "chargegrad" then
		local t = p:CreateTexture(nil, "ARTWORK")
		t:SetSize(96, 12); t:SetPoint("CENTER", p, "CENTER", 0, 0)
		local back = p:CreateTexture(nil, "BACKGROUND")
		back:SetPoint("TOPLEFT", t, "TOPLEFT", -1, 1); back:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 1, -1)
		back:SetColorTexture(0, 0, 0, 0.6)
		for i = 1, 2 do
			local d = p:CreateTexture(nil, "OVERLAY")
			d:SetColorTexture(0, 0, 0, 0.9); d:SetSize(1, 12)
			d:SetPoint("LEFT", t, "LEFT", 32 * i, 0)
		end
		c.repaint = function()
			local r, g, b = 0.2, 0.6, 1
			if SP.ShieldChargeColorOf then r, g, b = SP:ShieldChargeColorOf(1) end
			if s.key ~= "default" then
				t:SetColorTexture(1, 1, 1, 1)
				SP:PaintBarGradient(t, r, g, b, 1, false, s.key, "shieldcharges")
			else
				t:SetColorTexture(r, g, b, 1)
			end
		end
		c.repaint()
	elseif row.key == "outgrad" then
		-- four totem icons in their element-colored outlines
		local sets = {}
		for k = 1, 4 do
			local ic = p:CreateTexture(nil, "ARTWORK")
			ic:SetSize(22, 22); ic:SetPoint("LEFT", p, "CENTER", -50 + (k - 1) * 25, 0)
			ic:SetTexture(I.totems[k]); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			local e = {}
			for i = 1, 4 do e[i] = p:CreateTexture(nil, "OVERLAY") end
			e[1]:SetPoint("TOPLEFT", ic, "TOPLEFT"); e[1]:SetPoint("TOPRIGHT", ic, "TOPRIGHT"); e[1]:SetHeight(2)
			e[2]:SetPoint("BOTTOMLEFT", ic, "BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT"); e[2]:SetHeight(2)
			e[3]:SetPoint("TOPLEFT", ic, "TOPLEFT", 0, -2); e[3]:SetPoint("BOTTOMLEFT", ic, "BOTTOMLEFT", 0, 2); e[3]:SetWidth(2)
			e[4]:SetPoint("TOPRIGHT", ic, "TOPRIGHT", 0, -2); e[4]:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", 0, 2); e[4]:SetWidth(2)
			sets[k] = e
		end
		c.repaint = function()
			for k, e in ipairs(sets) do
				local col = GRAD_COLORS[k]
				for i = 1, 4 do e[i]:SetColorTexture(1, 1, 1, 1) end
				if s.key ~= "default" then
					SP:PaintOutlineEdges(e[1], e[2], e[3], e[4], col[1], col[2], col[3], 1, s.key)
				else
					for i = 1, 4 do e[i]:SetVertexColor(col[1], col[2], col[3], 1) end
				end
			end
		end
		c.repaint()
	elseif row.key == "edge" then
		local f = CreateFrame("Frame", nil, p, "BackdropTemplate")
		f:SetSize(4 * 22 + 5 * 3, 28); f:SetPoint("CENTER", p, "CENTER", 0, 0)
		f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		f:SetBackdropColor(0, 0, 0, 0.7); f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
		for i = 1, 4 do
			local ic = f:CreateTexture(nil, "ARTWORK")
			ic:SetSize(22, 22); ic:SetPoint("LEFT", f, "LEFT", 3 + (i - 1) * 25, 0)
			ic:SetTexture(I.totems[i]); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
		if SP.PaintFrameEdgePreview then SP:PaintFrameEdgePreview(f, s.key) end
	else
		-- Icon Shape: the totem bar's Square shows the whole icon picture (as the bar
		-- does today); Flat, and every shape elsewhere, the trimmed picture
		local whole = row.iconKind == "totem" and s.key == "default"
		for i = 1, 4 do
			local ic = p:CreateTexture(nil, "ARTWORK")
			ic:SetSize(24, 24); ic:SetPoint("LEFT", p, "CENTER", -52 + (i - 1) * 27, 0)
			ic:SetTexture(I.totems[i])
			if whole then ic:SetTexCoord(0, 1, 0, 1) else ic:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
			if s.file then
				local m = p:CreateMaskTexture()
				m:SetAllPoints(ic)
				m:SetTexture(s.file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
				ic:AddMaskTexture(m)
			end
		end
	end
end

local function NewShapeCard(row, s)
	local c = NewCard(page.body)
	c.title = Text(c, "brand")
	c.title:SetPoint("TOPLEFT", c, "TOPLEFT", 10, -8)
	c.title:SetText((s.label:gsub(" %(default%)", "")))
	c.tag = Tag(c)
	c.tag:SetPoint("TOPRIGHT", c, "TOPRIGHT", -10, -10)
	BuildShapePreview(c, row, s)
	c.key, c.row = s.key, row
	c:SetScript("OnClick", function()
		if row.get() ~= s.key then row.set(s.key) end
		PageChanged()
	end)
	Core:AttachTooltip(c, row.label .. ": " .. s.label, row.note)
	return c
end

local function RenderShapes(y, W, selection)
	-- the two bar texture choices: the same settings as General > Fonts & Textures
	local function texValues(def)
		return function()
			local v = { [DEFAULT] = def }
			for _, name in ipairs(SP.TextureList and SP:TextureList() or {}) do v[name] = name end
			return v
		end
	end
	local function texOrder()
		local o = { DEFAULT }
		for _, name in ipairs(SP.TextureList and SP:TextureList() or {}) do o[#o + 1] = name end
		return o
	end
	local function refresh() if SP.RefreshTextures then SP:RefreshTextures() end end
	if not selection or selection.barTexture then
		local _, h1 = Widgets:Dropdown(page.body, {
			label = BLOCKS.barTexture.label, x = 0, y = y, width = W,
			desc = BLOCKS.barTexture.desc,
			values = texValues("Default (as designed)"), order = texOrder,
			get = function() return SP.opt.barTexture or DEFAULT end,
			set = function(v) if v == DEFAULT then v = nil end; SP.opt.barTexture = v; refresh() end,
			onChanged = PageChanged,
		})
		y = y + h1 + 6
	end
	if not selection or selection.shieldTexture then
		local _, h2 = Widgets:Dropdown(page.body, {
			label = BLOCKS.shieldTexture.label, x = 0, y = y, width = W,
			desc = BLOCKS.shieldTexture.desc,
			values = texValues("Default (as designed)"), order = texOrder,
			get = function() local t = SP.opt.barTextureAreas; return (t and t.shieldcharges) or DEFAULT end,
			set = function(v)
				if v == DEFAULT then v = nil end
				SP.opt.barTextureAreas = SP.opt.barTextureAreas or {}
				SP.opt.barTextureAreas.shieldcharges = v
				refresh()
			end,
			onChanged = PageChanged,
		})
		y = y + h2 + 10
	end
	local gap = 10
	for _, row in ipairs(SHAPE_ROWS) do
		if (not selection or selection.rows[row.key]) and (not row.shown or row.shown()) then
			local list = row.list() or {}
			local lab = Keep("shapelabel:" .. row.key, function()
				local f = CreateFrame("Frame", nil, page.body)
				f.name = Text(f, "section")
				f.name:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
				f.name:SetText(strupper(row.label))
				-- accentHi, as the sidebar's group headers: each row's title stands out from its note
				f.name:SetTextColor(Core:Color("accentHi"))
				f.note = Text(f, "rowDim")
				f.note:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -3)
				return f
			end)
			local nh = Fit(lab.note, W, row.note)
			local lh = ceil(lab.name:GetStringHeight()) + 3 + nh
			lab:SetSize(W, lh)
			lab:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
			y = y + lh + 6
			local n = #list
			-- more than five cards wrap onto two lines, so none gets too narrow
			local perLine = (n > 5) and ceil(n / 2) or n
			local lines = ceil(n / max(perLine, 1))
			local cw = floor((W - (perLine - 1) * gap) / max(perLine, 1))
			local cards = {}
			for i, s in ipairs(list) do
				local c = Keep("shape:" .. row.key .. ":" .. s.key, function() return NewShapeCard(row, s) end)
				if not c.tagW then c.tag:SetText("IN USE"); c.tagW = ceil(c.tag:GetStringWidth()) end
				-- the title wraps inside the card, clear of the IN USE tag; a word too long
				-- to sit beside the tag (Diamond) takes the card's width, the tag under it
				local full, beside = max(20, cw - 20), max(20, cw - 20 - c.tagW - 6)
				local text, longest = c.title:GetText() or "", 0
				for word in text:gmatch("%S+") do
					c.title:SetText(word)
					longest = max(longest, c.title.GetUnboundedStringWidth and c.title:GetUnboundedStringWidth() or c.title:GetStringWidth())
				end
				c.title:SetText(text)
				c.tag:ClearAllPoints()
				if longest > beside then
					c.title:SetWidth(full)
					c.tag:SetPoint("TOPRIGHT", c.title, "BOTTOMRIGHT", 0, -2)
					c.th = ceil(c.title:GetStringHeight()) + 2 + ceil(c.tag:GetStringHeight())
				else
					c.title:SetWidth(beside)
					c.tag:SetPoint("TOPRIGHT", c, "TOPRIGHT", -10, -10)
					c.th = ceil(c.title:GetStringHeight())
				end
				cards[i] = c
			end
			-- one height for the row: the tallest title
			local tallest = 0
			for _, c in ipairs(cards) do tallest = max(tallest, c.th) end
			local ch = 8 + tallest + 4 + PREVIEW_H + 8
			for i, c in ipairs(cards) do
				local col, line = (i - 1) % perLine, floor((i - 1) / perLine)
				c:SetSize(cw, ch)
				c:SetPoint("TOPLEFT", page.body, "TOPLEFT", col * (cw + gap), -(y + line * (ch + gap)))
				c.preview:ClearAllPoints()
				c.preview:SetPoint("TOP", c, "TOP", 0, -(8 + tallest + 4))
			end
			shapeCards[row.key] = cards
			y = y + lines * ch + (lines - 1) * gap + 12
			if row.extra then y = row.extra(y, W) end   -- Two-Tone colors / Fade Out opacity
		else
			shapeCards[row.key] = nil
		end
	end
	return y
end

local function PaintShapes()
	for _, row in ipairs(SHAPE_ROWS) do
		if shapeCards[row.key] then
			local inUse = row.get()
			for _, c in ipairs(shapeCards[row.key]) do
				c.selected = (c.key == inUse)
				PaintCard(c)
				if c.repaint then c.repaint() end   -- the gradient cards follow their colors
				if c.selected then SetTag(c.tag, "IN USE", "accentHi") else SetTag(c.tag, nil) end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- 6. WoW's own colours
-- ---------------------------------------------------------------------------
local WOW_ROWS = {
	{ "GREEN_FONT_COLOR", "Green", "Full charges and plenty of time left. Friendly totems on nameplates." },
	{ "YELLOW_FONT_COLOR", "Yellow", "Charges or time running low." },
	{ "RED_FONT_COLOR", "Red", "The last charge or almost out, a missing buff, a destroyed totem. Enemy totems on nameplates." },
	{ "NORMAL_FONT_COLOR", "Gold", "The Tremor Totem glow and the Raid Cooldowns alert." },
	{ "ORANGE_FONT_COLOR", "Orange", "A weapon imbue running out." },
	{ "DEBUFF_TYPE_MAGIC_COLOR", "Magic blue", "The blue WoW gives magic buffs. Your shields use it when you pick WoW Magic Blue above." },
}

local function NewWoWRow(def)
	local f = CreateFrame("Frame", nil, page.body)
	Core:RowBg(f)
	f.sw = NewSwatch(f, 20, 20)
	f.sw:EnableMouse(false)
	f.sw:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
	f.name = Text(f, "row")
	f.name:SetPoint("TOPLEFT", f, "TOPLEFT", 44, -8)
	f.name:SetText(def[2])
	f.use = Text(f, "rowDim")
	f.use:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -3)
	f.key = def[1]
	return f
end

-- ---------------------------------------------------------------------------
-- 6b. Colors from each part's own page, drawn in that part's section: the
-- option's own get / set, so one setting changed in either place (nothing
-- moves off its page). A row its page hides is left out; one it greys out is
-- greyed out here too. path.label names a row where the option's own name
-- would be unclear in the section.
-- ---------------------------------------------------------------------------
local SPOT_EXTRAS = {
	["tb.sweep"] = { { "fluffy", "totembar_duration_section", "totem_cooldown_direction" } },
	["cd.sweep"] = { { "fluffy", "cooldown_display_section", "cdbar_sweep_direction" } },
	["tb.pulse"] = {
		{ "fluffy", "totembar_duration_section", "pulse_bar_color" },
		{ "fluffy", "totembar_duration_section", "pulse_flash_color" } },
	["tb.frame"] = {
		{ "fluffy", "color_section", "color_partial", label = "Background (Partially Buffed)" },
		{ "fluffy", "color_section", "color_missing", label = "Background (None Buffed)" } },
	["st.compact"] = {
		{ "settings", "settings_totemMode", "compactOptions", "compactOutlineColorMode" },
		{ "settings", "settings_totemMode", "compactOptions", "compactOutlineColor" } },
	["mod.readyreminders"] = {
		{ "fluffy", "readyreminders_section", "glowColor" },
		{ "fluffy", "readyreminders_section", "barColor" },
		{ "fluffy", "readyreminders_section", "rangeColor" } },
}
-- a section's own extra row, labelled like a part: Mana Tint at the end of Totem Bar
local MODULE_EXTRAS = {
	totembar = { { key = "extra.manatint", label = "Mana Tint",
		note = "Totem and cooldown buttons you do not have the mana for. Also on Appearance > Textures & Colors (turn Mana Tint on there).",
		paths = { { "fluffy", "button_tints_section", "manaTintColor" } } } },
}
local function OptionAt(path)
	local node = SP.options
	for i = 1, #path do node = node and node.args and node.args[path[i]] end
	return node
end
local function OptionInfo(path, option)   -- what AceConfig hands an option's own functions
	local info = { option = option, type = option.type, options = SP.options }
	for i = 1, #path do info[i] = path[i] end
	return info
end
local function OptionValue(v, info)       -- a field that may be a function
	if type(v) == "function" then
		local ok, r = pcall(v, info)
		if ok then return r end
		return nil
	end
	return v
end
local function ColorRowShown(path)
	local o = OptionAt(path)
	if not (o and o.get and o.set) then return false end
	return not OptionValue(o.hidden, OptionInfo(path, o))
end
-- which rows show, for the page's layout signature
local function ColorRowsSig()
	local s = ""
	for _, paths in pairs(SPOT_EXTRAS) do
		for _, path in ipairs(paths) do s = s .. (ColorRowShown(path) and "1" or "0") end
	end
	for _, list in pairs(MODULE_EXTRAS) do
		for _, ex in ipairs(list) do
			for _, path in ipairs(ex.paths) do s = s .. (ColorRowShown(path) and "1" or "0") end
		end
	end
	return s
end
-- the rows of a list of options at x, from y down, w wide; returns the new y
local function RenderOptionRows(paths, y, x, w)
	for _, path in ipairs(paths) do
		if ColorRowShown(path) then
			local o = OptionAt(path)
			local info = OptionInfo(path, o)
			local label, desc = path.label or OptionValue(o.name, info) or "", OptionValue(o.desc, info)
			local off = o.disabled and function() return OptionValue(o.disabled, info) and true or false end or nil
			local h
			if o.type == "color" then
				_, h = Widgets:Color(page.body, {
					label = label, desc = desc, x = x, y = y, width = w, hasAlpha = o.hasAlpha and true or false,
					disabled = off,
					get = function() return o.get(info) end,
					set = function(r, g, b, a) o.set(info, r, g, b, a) end,
					onChanged = PageChanged,
				})
			elseif o.type == "select" then
				_, h = Widgets:Dropdown(page.body, {
					label = label, desc = desc, x = x, y = y, width = w,
					disabled = off,
					values = function() return OptionValue(o.values, info) or {} end,
					order = o.sorting and function() return OptionValue(o.sorting, info) end or nil,
					get = function() return o.get(info) end,
					set = function(v) o.set(info, v) end,
					onChanged = PageChanged,
				})
			end
			if h then y = y + h + 6 end
		end
	end
	return y
end

local function RenderWoW(y, W)
	local _, dh = Widgets:Description(page.body, { x = 0, y = y, width = W,
		text = BLOCKS.wow.desc })
	y = y + dh
	local gap = 12
	local colW = floor((W - gap) / 2)
	local rowH = 0
	for i, def in ipairs(WOW_ROWS) do
		local f = Keep("wow:" .. def[1], function() return NewWoWRow(def) end)
		wowRows[i] = f
		local uh = Fit(f.use, colW - 56, def[3])
		local h = max(40, 8 + ceil(f.name:GetStringHeight()) + 3 + uh + 8)
		f:SetSize(colW, h)
		local col = (i - 1) % 2
		if col == 0 and i > 1 then y = y + rowH + 6; rowH = 0 end
		f:SetPoint("TOPLEFT", page.body, "TOPLEFT", col * (colW + gap), -y)
		rowH = max(rowH, h)
	end
	return y + rowH + 6
end

local function PaintWoW()
	for i = 1, #wowRows do
		local f = wowRows[i]
		local r, g, b = SP:WoWColor(f.key)
		f.sw.fill:SetColorTexture(r, g, b, 1)
	end
end

-- ---------------------------------------------------------------------------
-- 8. The module sections: a row per spot
-- ---------------------------------------------------------------------------
local function ListFns(list)
	local values, order = {}, {}
	for _, it in ipairs(list) do
		local k = it.key == nil and DEFAULT or it.key
		values[k] = it.label
		order[#order + 1] = k
	end
	return function() return values end, function() return order end
end
local L = SP.THEME_LISTS
local THEME_V, THEME_O = ListFns(L.theme)
local PAL_V, PAL_O = ListFns(L.palette)
local SHIELD_V, SHIELD_O = ListFns(L.shield)
local SHOWAS_V, SHOWAS_O = ListFns(L.showAs)
CC.V, CC.O = ListFns(L.classColors)
local choiceFns = {}
local function ChoiceFns(spot)
	local c = choiceFns[spot.id]
	if not c then
		local list = { { key = nil, label = "Use Theme's" } }
		for _, ch in ipairs(spot.choices) do list[#list + 1] = { key = ch.key, label = ch.label } end
		local v, o = ListFns(list)
		c = { v, o }
		choiceFns[spot.id] = c
	end
	return c[1], c[2]
end
local CHOICE_LABEL = { ["tb.duration-text"] = "Text Color", ["tb.pulse"] = "Pulse Color" }
local SPOT_FIELDS = {
	theme = { label = "Theme", list = L.theme,
		desc = ": the theme this part uses. Use General Theme follows the theme picked at the top of this page." },
	palette = { label = "Colors", list = L.palette,
		desc = ": the element colors this part uses. Use Theme's follows Element Colors at the top"
			.. " (Standard: your Appearance colors)." },
	shield = { label = "Shield Colors", list = L.shield,
		desc = ": the shield colors this part uses. Use Theme's follows Shield Colors at the top." },
	showAs = { label = "Show Icons As", list = L.showAs,
		desc = ": how its flat boxes show which totem it is. Use Theme's follows Show Icons As at the top." },
	choice = { label = "Color", desc = ": the color this part uses. Use Theme's: the theme's own." },
	classColors = { label = "Class Colors", list = L.classColors,
		desc = ": the class colors its dots use. Use Theme's follows Class Colors at the top." },
}

-- spots that do nothing on this client or class
local FOREVER_ONLY = { ["tb.empty-slot"] = true, ["tb.flyout-empty"] = true, ["cd.engine"] = true }
local function SpotShown(spot)
	if spot.hidden then return false end   -- (the effects spots: the bars' Effects tabs)
	if FOREVER_ONLY[spot.id] and not IS_MAINLINE then return false end
	if spot.id == "cd.class-icons" and not HasEarthShield() then return false end
	return true
end
local SHAMAN_MODULES = { totembar = true, styles = true, cooldownbar = true, loadouts = true, shieldcharges = true, alerts = true,
	partybuff = true, popouts = true, reactive = true, readyreminders = true, tremor = true, readycheck = true,
	minimap = true, assign = true }
local function ModuleShown(mod)
	if mod.themeLevel then return false end   -- drawn by the cards at the top
	if SHAMAN_MODULES[mod.key] and not PLAYER_IS_SHAMAN then return false end
	if mod.key == "estracker" and not HasEarthShield() then return false end   -- no Earth Shield in this client (WoW: Forever)
	return true
end

local function SpotDropdown(spot, field, label, desc, valuesFn, orderFn, x, y, w)
	local id = spot.id
	local _, h = Widgets:Dropdown(page.body, {
		label = label, desc = desc, x = x, y = y, width = w,
		values = valuesFn, order = orderFn,
		get = function()
			local v = SP:ThemeSpotField(id, field)
			if v == nil then return DEFAULT end
			return v
		end,
		set = function(v)
			if v == DEFAULT then v = nil end
			if SP:ThemeSpotField(id, field) ~= v then SP:SetSpotField(id, field, v) end
		end,
		onChanged = PageChanged,
	})
	return h
end

-- the swatch strip: a swatch per colour role, flowing across a row card
local SOURCE_TEXT = {
	setting = "Your own setting: its own settings page changes it too.",
	custom = "Your color for this part.",
	wow = "WoW's own color.",
	theme = "The theme's color.",
	standard = "Today's color.",
}
local tagW = 0

local function RoleShown(role)
	if role.placeholder and not role.setting then return false end   -- a setting not registered (its module is off)
	if role.kind == "shield" and role.which == "earth" and not HasEarthShield() then return false end   -- no Earth Shield here (WoW: Forever)
	return true
end

local function StripTip(self)
	local r, g, b, src = SP:ThemeDisplayColor(self.spot, self.role)
	local tip = Core:Tooltip()
	tip:SetOwner(self, "ANCHOR_CURSOR")
	tip:AddLine(self.title)
	tip:AddLine(Hex(r, g, b) .. "   " .. (SOURCE_TEXT[src] or ""))
	tip:AddHint("Click to pick a color")
	tip:AddHint("Right-click: back to the theme's color")
	tip:Show()
end

local function NewStripItem(parent)
	local it = CreateFrame("Button", nil, parent)
	it:SetHeight(18)
	it:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	it.sw = NewSwatch(it, 26, 18)
	it.sw:EnableMouse(false)
	it.sw:SetPoint("LEFT", it, "LEFT", 0, 0)
	it.label = Text(it, "row")
	it.label:SetPoint("LEFT", it.sw, "RIGHT", 6, 0)
	it.tag = Tag(it)
	it.tag:SetPoint("LEFT", it.label, "RIGHT", 6, 0)
	it.spThemes = true
	it:SetScript("OnEnter", function(self) Core:SetBorderColor(self.sw, "accent"); StripTip(self) end)
	it:SetScript("OnLeave", function(self)
		Core:SetBorderColor(self.sw, "border")
		Core:HideTooltipFor(self)
	end)
	it:SetScript("OnClick", function(self, button)
		if InCombatLockdown() then return end
		if button == "RightButton" then
			SP:SetSpotColor(self.spot, self.role, nil)
			PageChanged()
			return
		end
		PickSwatch(self.spot, self.role, self.title)
	end)
	return it
end

local function PaintStrip(f)
	for i = 1, f.n or 0 do
		local it = f.items[i]
		local r, g, b, src = SP:ThemeDisplayColor(it.spot, it.role)
		it.sw.fill:SetColorTexture(r, g, b, 1)
		if src == "wow" then SetTag(it.tag, "WOW", "accentHi")
		elseif src == "custom" then SetTag(it.tag, "CUSTOM", "textDim")
		else SetTag(it.tag, nil) end
	end
end

local function NewStrip()
	local f = CreateFrame("Frame", nil, page.body)
	Core:RowBg(f)
	f.items = {}
	f.Paint = PaintStrip
	return f
end

local function LayoutStrip(f, spot, w)
	f:SetWidth(w)
	local x, lineY, n = 12, 8, 0
	for _, role in ipairs(spot.roles) do
		if RoleShown(role) then
			n = n + 1
			local it = f.items[n]
			if not it then it = NewStripItem(f); f.items[n] = it end
			it.spot, it.role = spot.id, role.key
			it.title = spot.label .. ": " .. (role.label or role.key)
			it.label:SetText(role.label or role.key)
			local iw = 26 + 6 + ceil(it.label:GetStringWidth())
			if not role.setting then iw = iw + 6 + tagW end   -- room for WOW / CUSTOM
			if x > 12 and x + iw > w - 12 then x, lineY = 12, lineY + 24 end
			it:SetWidth(iw)
			it:ClearAllPoints()
			it:SetPoint("TOPLEFT", f, "TOPLEFT", x, -lineY)
			it:Show()
			x = x + iw + 16
		end
	end
	for i = n + 1, #f.items do f.items[i]:Hide() end
	f.n = n
	local h = lineY + 18 + 8
	f:SetHeight(h)
	return h
end

local function HasRoles(spot)
	for _, role in ipairs(spot.roles) do
		if RoleShown(role) then return true end
	end
	return false
end

local function NewSpotText()
	local f = CreateFrame("Frame", nil, page.body)
	f.label = Text(f, "row")
	f.label:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
	f.note = Text(f, "rowDim")
	f.note:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 0, -4)
	return f
end

local function RenderSpot(spot, y, W)
	local leftW = floor(W * 0.38)
	local rx, rw = leftW + 12, W - leftW - 12
	local t = Keep("spot:" .. spot.id, NewSpotText)
	t:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
	local lh = Fit(t.label, leftW - 24, spot.label)
	local nh = spot.note and Fit(t.note, leftW - 24, spot.note) or 0
	if not spot.note then t.note:SetText("") end
	local th = 10 + lh + (nh > 0 and (4 + nh) or 0) + 10
	t:SetSize(leftW, th)
	local name = spot.label
	local ry = y
	ry = ry + SpotDropdown(spot, "theme", SPOT_FIELDS.theme.label,
		name .. SPOT_FIELDS.theme.desc,
		THEME_V, THEME_O, rx, ry, rw)
	if spot.palette then
		ry = ry + SpotDropdown(spot, "palette", SPOT_FIELDS.palette.label,
			name .. SPOT_FIELDS.palette.desc,
			PAL_V, PAL_O, rx, ry, rw)
	end
	if spot.shield then
		ry = ry + SpotDropdown(spot, "shield", SPOT_FIELDS.shield.label,
			name .. SPOT_FIELDS.shield.desc,
			SHIELD_V, SHIELD_O, rx, ry, rw)
	end
	if spot.classColors then
		ry = ry + SpotDropdown(spot, "classColors", SPOT_FIELDS.classColors.label,
			name .. SPOT_FIELDS.classColors.desc,
			CC.V, CC.O, rx, ry, rw)
	end
	if spot.box and SP:ThemeBoxed(spot.id) then
		ry = ry + SpotDropdown(spot, "showAs", SPOT_FIELDS.showAs.label,
			name .. SPOT_FIELDS.showAs.desc,
			SHOWAS_V, SHOWAS_O, rx, ry, rw)
	end
	if spot.choices then
		local v, o = ChoiceFns(spot)
		ry = ry + SpotDropdown(spot, "choice", CHOICE_LABEL[spot.id] or SPOT_FIELDS.choice.label,
			name .. SPOT_FIELDS.choice.desc, v, o, rx, ry, rw)
	end
	if HasRoles(spot) then
		local s = Keep("strip:" .. spot.id, NewStrip)
		s:SetPoint("TOPLEFT", page.body, "TOPLEFT", rx, -ry)
		ry = ry + LayoutStrip(s, spot, rw) + 6
		live[#live + 1] = s
	end
	-- the part's color options from its own page (Pulse Bar Color ...)
	if SPOT_EXTRAS[spot.id] then ry = RenderOptionRows(SPOT_EXTRAS[spot.id], ry, rx, rw) end
	return max(y + th, ry) + 8
end

-- a section's own extra row, laid out like a part: its label and note on the
-- left, its options on the right
local function RenderExtraSpot(ex, y, W)
	local any = false
	for _, path in ipairs(ex.paths) do if ColorRowShown(path) then any = true break end end
	if not any then return y end
	local leftW = floor(W * 0.38)
	local rx, rw = leftW + 12, W - leftW - 12
	local t = Keep("spot:" .. ex.key, NewSpotText)
	t:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
	local lh = Fit(t.label, leftW - 24, ex.label)
	local nh = ex.note and Fit(t.note, leftW - 24, ex.note) or 0
	local th = 10 + lh + (nh > 0 and (4 + nh) or 0) + 10
	t:SetSize(leftW, th)
	local ry = RenderOptionRows(ex.paths, y, rx, rw)
	return max(y + th, ry) + 8
end

local function RenderModule(mod, y, W, selection)
	-- where the section starts, for the settings window's live preview (Page:SectionAt)
	local secs = page.sections
	secs[#secs + 1] = { key = mod.key, label = mod.label, y = y }
	y = y + Header(mod.label, y, W)
	local draw = DRAW[mod.key]
	if draw then
		local p = Keep("draw:" .. mod.key, function()
			local f = CreateFrame("Frame", nil, page.body)
			Core:SolidTex(f, "contentBg", "BACKGROUND")
			Core:MakeBorder(f, "border")
			local cap = Caption(f)
			cap:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
			cap:SetText("HOW IT LOOKS NOW")
			local stage = CreateFrame("Frame", nil, f)
			local w, h, paint = draw(stage)
			stage:SetSize(w, h)
			stage:SetPoint("TOP", f, "TOP", 0, -22)
			f.stageH, f.Paint = h, paint
			return f
		end)
		p:SetSize(W, p.stageH + 32)
		p:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
		live[#live + 1] = p
		y = y + p.stageH + 32 + 10
	end
	for _, spot in ipairs(mod.spots) do
		if SpotShown(spot) and (not selection or selection[spot.id]) then
			-- Totem Bar Styles: the preview shows the style of the rows in view
			if mod.key == "styles" then secs[#secs + 1] = { key = mod.key, label = mod.label, y = y, spot = spot.id } end
			y = RenderSpot(spot, y, W)
		end
	end
	for _, ex in ipairs(MODULE_EXTRAS[mod.key] or {}) do
		if not selection or selection[ex.key] then y = RenderExtraSpot(ex, y, W) end
	end
	return y
end

-- ---------------------------------------------------------------------------
-- Paint and the page's life
-- ---------------------------------------------------------------------------
local function AddSearchText(parts, text)
	if type(text) == "function" then text = text() end
	if text then parts[#parts + 1] = string.lower(ns.Tree:StripColor(text)) end
end

local function AddSearchChoices(parts, choices)
	for _, choice in ipairs(choices or {}) do
		AddSearchText(parts, choice.label)
		AddSearchText(parts, choice.desc)
		AddSearchText(parts, choice.sub)
	end
end

local function SearchParts(def)
	local parts = {}
	AddSearchText(parts, def.label)
	AddSearchText(parts, def.desc)
	AddSearchText(parts, def.note)
	AddSearchText(parts, def.caption)
	AddSearchText(parts, def.search)   -- the block's own controls (sliders, toggles, colors under it)
	return parts
end

local function SearchMatch(parts, query)
	return string.find(table.concat(parts, " "), query, 1, true) ~= nil
end

local function SpotSearchParts(spot)
	local parts = SearchParts(spot)
	for _, field in ipairs({ "theme", "palette", "shield", "showAs", "choice", "classColors" }) do
		if field == "theme" or (field == "showAs" and spot.box and SP:ThemeBoxed(spot.id))
			or (field == "choice" and spot.choices) or (field ~= "showAs" and spot[field]) then
			local def = SPOT_FIELDS[field]
			AddSearchText(parts, field == "choice" and CHOICE_LABEL[spot.id] or def.label)
			AddSearchText(parts, spot.label .. def.desc)
			AddSearchChoices(parts, def.list or spot.choices)
			if field == "choice" then AddSearchText(parts, "Use Theme's") end
		end
	end
	for _, role in ipairs(spot.roles) do
		if RoleShown(role) then AddSearchText(parts, role.label or role.key) end
	end
	-- its color options from its own page (Pulse Bar Color ...), as drawn beside it
	for _, path in ipairs(SPOT_EXTRAS[spot.id] or {}) do
		if ColorRowShown(path) then
			local o = OptionAt(path)
			local info = OptionInfo(path, o)
			AddSearchText(parts, path.label or OptionValue(o.name, info))
			AddSearchText(parts, OptionValue(o.desc, info))
			if o.type == "select" then
				for _, label in pairs(OptionValue(o.values, info) or {}) do AddSearchText(parts, label) end
			end
		end
	end
	return parts
end

-- This bar shares its shield colors with the charge strip. Keep related names
-- as catalogue references, not query-specific synonyms or a second visible label.
local SEARCH_RELATED = { ["cd.shieldbar"] = { "cd.strip" } }

-- One index per render, never per frame. Only text from currently available
-- blocks/choices/roles participates; the drawing keeps using the original controls.
function Page.Search(_, query)
	query = query and string.lower(query):match("^%s*(.-)%s*$")
	if not query or query == "" then return nil end
	local result = { blocks = {}, shapes = { rows = {} }, modules = {} }
	local any = false
	local function Include(key, parts)
		local hit = SearchMatch(parts or SearchParts(BLOCKS[key]), query)
		result.blocks[key] = hit
		if hit then any = true end
		return hit
	end
	Include("intro")
	local picker = SearchParts(BLOCKS.picker)
	for _, pick in ipairs(PICKS) do
		AddSearchText(picker, pick.label)
		AddSearchText(picker, pick.desc)
	end
	AddSearchText(picker, "Presets Your Themes Custom Save as Theme Save Current Look Import Theme Share Rename Delete Update Discard")
	for _, th in ipairs(SP:ThemeMine()) do AddSearchText(picker, th.name) end
	AddSearchText(picker, SP:ThemeIsCustom() and CUSTOM_ON or CUSTOM_OFF)
	Include("picker", picker)
	if SP:ThemeGlobal() == "minimal" then
		local parts = SearchParts(BLOCKS.options)
		AddSearchChoices(parts, SHOW_AS)
		Include("options", parts)
	end
	local palettes = SearchParts(BLOCKS.palettes)
	AddSearchChoices(palettes, PALETTE_CARDS)
	for _, name in ipairs(EL) do AddSearchText(palettes, name) end
	Include("palettes", palettes)
	Include("borders")
	local classParts = SearchParts(BLOCKS.classColors)
	AddSearchChoices(classParts, SP.CLASS_COLOR_SETS)
	for _, class in ipairs(CC.ORDER) do AddSearchText(classParts, CC.NAME[class]) end
	Include("classColors", classParts)
	if SP:ThemeField("borders") == true then Include("flyoutBorders"); Include("cooldownBorders") end
	if SP:ThemeField("borders") == true and SP:ThemeField("bordersCooldown") == true then Include("cooldownFlyoutBorders") end

	local spots, shieldUses = {}, {}
	for _, mod in ipairs(SP.THEME_MODULES) do
		if ModuleShown(mod) then
			for _, spot in ipairs(mod.spots) do
				if SpotShown(spot) then
					spots[spot.id] = SpotSearchParts(spot)
					-- Shield Colors is the shared control for these consumers. Their
					-- visible names make its scope searchable without changing its cards.
					if spot.shield then
						AddSearchText(shieldUses, spot.label)
						AddSearchText(shieldUses, spot.note)
						for _, role in ipairs(spot.roles) do
							if RoleShown(role) then AddSearchText(shieldUses, role.label or role.key) end
						end
					end
				end
			end
		end
	end
	local shields = SearchParts(BLOCKS.shields)
	AddSearchChoices(shields, SHIELD_CARDS)
	shields[#shields + 1] = table.concat(shieldUses, " ")
	Include("shields", shields)
	local shapeTitle = SearchParts(BLOCKS.shapes)
	local allShapes = SearchMatch(shapeTitle, query)
	local textures = SP.TextureList and SP:TextureList() or {}
	for _, key in ipairs({ "barTexture", "shieldTexture" }) do
		local parts = SearchParts(BLOCKS[key])
		AddSearchText(parts, "Default (as designed)")
		for _, name in ipairs(textures) do AddSearchText(parts, name) end
		result.shapes[key] = allShapes or SearchMatch(parts, query)
		if result.shapes[key] then result.blocks.shapes, any = true, true end
	end
	for _, row in ipairs(SHAPE_ROWS) do
		if not row.shown or row.shown() then
			local parts = SearchParts(row)
			AddSearchChoices(parts, row.list())
			result.shapes.rows[row.key] = allShapes or SearchMatch(parts, query)
			if result.shapes.rows[row.key] then result.blocks.shapes, any = true, true end
		end
	end
	local wow = SearchParts(BLOCKS.wow)
	for _, row in ipairs(WOW_ROWS) do AddSearchText(wow, row[2]); AddSearchText(wow, row[3]) end
	Include("wow", wow)
	Include("reset")
	Include("resetAll")
	Include("resetEverything")
	for _, mod in ipairs(SP.THEME_MODULES) do
		if ModuleShown(mod) then
			local whole = SearchMatch(SearchParts(mod), query)
			local matching = {}
			for _, spot in ipairs(mod.spots) do
				local parts = spots[spot.id]
				if parts then
					for _, id in ipairs(SEARCH_RELATED[spot.id] or {}) do
						if spots[id] then parts[#parts + 1] = table.concat(spots[id], " ") end
					end
					if whole or SearchMatch(parts, query) then matching[spot.id], any = true, true end
				end
			end
			-- the section's own extra rows (Mana Tint at the end of Totem Bar)
			for _, ex in ipairs(MODULE_EXTRAS[mod.key] or {}) do
				local parts = {}
				AddSearchText(parts, ex.label)
				AddSearchText(parts, ex.note)
				for _, path in ipairs(ex.paths) do
					if ColorRowShown(path) then
						local o = OptionAt(path)
						AddSearchText(parts, path.label or OptionValue(o.name, OptionInfo(path, o)))
					end
				end
				if whole or SearchMatch(parts, query) then matching[ex.key], any = true, true end
			end
			if whole or next(matching) then result.modules[mod.key], any = whole or matching, true end
		end
	end
	return any and result or nil
end

local function Safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then geterrorhandler()(err) end
end

-- what decides which rows the page has: the picked theme (Theme Options) and
-- which parts are flat boxes (their Show Icons As). Built only on a change.
-- the theme cards: which are shown, their names, and how many changes the Custom card lists
function TC.CardsSig()
	local parts = { SP:ThemeCustomOf() and "o" or "-", tostring(#(SP:ThemeChanges())) }
	for _, th in ipairs(SP:ThemeMine()) do parts[#parts + 1] = th.id .. th.name end
	return table.concat(parts, ",")
end
LayoutSig = function()
	local o = SP.opt or {}
	local parts = { SP:ThemeGlobal() == "minimal" and "m" or "-", SP:ThemeField("borders") == true and "b" or "-",
		SP:ThemeField("bordersFlyouts") == true and "f" or "-", SP:ThemeField("bordersCooldown") == true and "c" or "-",
		SP:ThemeField("bordersCooldownFlyouts") == true and "g" or "-",
		CustomCardShown() and "c" or "-", TC.CardsSig(),
		-- the rows under the gradient cards come and go with the style picked
		o.barGradient or "-", o.barGradientColor1 and "1" or "0", o.outlineGradient or "-", o.outlineGradientColor1 and "1" or "0",
		o.chargeGradient or "-", o.chargeGradientColor1 and "1" or "0", IconShapedAny() and "r" or "-", ColorRowsSig() }
	for _, row in ipairs(SHAPE_ROWS) do
		if row.shown then parts[#parts + 1] = row.shown() and "s" or "h" end
	end
	for _, mod in ipairs(SP.THEME_MODULES) do
		for _, spot in ipairs(mod.spots) do
			if spot.box then parts[#parts + 1] = SP:ThemeBoxed(spot.id) and "1" or "0" end
		end
	end
	return table.concat(parts)
end

RepaintAll = function()
	if not page.visible then return end
	local blocks = page.selection and page.selection.blocks
	if not blocks or blocks.picker then Safe(PaintPicker) end
	if page.showOptions then Safe(PaintThemeOptions) end
	if not blocks or blocks.palettes then Safe(PaintPalettes) end
	if not blocks or blocks.classColors then Safe(CC.Paint) end
	if not blocks or blocks.shields then Safe(PaintShields) end
	if not blocks or blocks.shapes then Safe(PaintShapes) end
	if not blocks or blocks.wow then Safe(PaintWoW) end
	for i = 1, #live do
		local f = live[i]
		if f.Paint then Safe(f.Paint, f) end
	end
end

-- Draw all blocks, or a search selection, starting at startY; return the ending y.
function Page.Render(_, body, W, onChanged, selection, startY)
	page.sections = {}
	page.selection = selection
	local function Includes(key) return not selection or selection.blocks[key] end
	page.body, page.onChanged = body, onChanged
	if SP.ThemeCheckSnapshot then SP:ThemeCheckSnapshot() end   -- /sp themecheck: the look as the page opened
	for i = #shown, 1, -1 do shown[i] = nil end
	for i = #live, 1, -1 do live[i] = nil end
	if tagW == 0 then
		local m = body:CreateFontString(nil, "OVERLAY")
		m:SetFontObject(Core.fonts.section)
		m:SetText("CUSTOM")
		tagW = max(30, ceil(m:GetStringWidth()))
		m:Hide()
	end
	local y = startY or 0
	if Includes("intro") then
		local _, h = Widgets:Description(body, { text = INTRO, x = 0, y = y, width = W })
		y = y + h
	end
	-- the two reset buttons first, above the Theme picker, so they are easy to find
	if Includes("reset") then
		local _, bh = Widgets:Button(body, {
			label = BLOCKS.reset.label, buttonText = BLOCKS.reset.label, x = 0, y = y + 4, width = W,
			desc = BLOCKS.reset.desc,
			func = function() SP:ResetThemeColors() end,
			onChanged = PageChanged,
		})
		y = y + 4 + bh
	end
	-- the emergency button: every color in ShamanPower back to how it came
	if Includes("resetAll") then
		local _, rh = Widgets:Button(body, {
			label = BLOCKS.resetAll.label, buttonText = BLOCKS.resetAll.caption, x = 0, y = y + 4, width = W,
			desc = BLOCKS.resetAll.desc,
			func = function()
				SP:ShowSPDialog({
					key = "resetallcolors",
					title = "Reset All Colors and Theme?",
					text = "Reset every color in ShamanPower to its default:\n\n"
						.. "- the Standard theme, with no separate choices for individual features, color edits or element-colored borders\n"
						.. "- the default Element Colors and Status Colors\n"
						.. "- every color option on every page: Cooldown Text, Pulse Bar and Pulse Flash, Compact outline, Mana Tint,"
						.. " each shield's Charge Color, the gradients' Two-Tone colors, Ready Reminders and Tremor Reminder\n\n"
						.. "Nothing else changes. Everything it clears is kept on the Custom card: click it to bring it all back."
						.. " Your interface reloads to finish.",
					buttons = {
						{ text = "Reset and Reload", onClick = function()
							SP:ResetAllColorsToDefault()
							ReloadUI()
						end },
						{ text = "Cancel" },
					},
				})
			end,
		})
		y = y + 4 + rh
	end
	-- every setting on this page, the looks too, back to how it came
	if Includes("resetEverything") then
		local _, eh = Widgets:Button(body, {
			label = BLOCKS.resetEverything.label, buttonText = BLOCKS.resetEverything.caption, x = 0, y = y + 4, width = W,
			desc = BLOCKS.resetEverything.desc,
			func = function()
				SP:ShowSPDialog({
					key = "reseteverything",
					title = "Reset Everything?",
					text = "Reset every setting on the Themes tab to its default:\n\n"
						.. "- everything Reset All Colors and Theme does: the Standard theme with nothing changed, and every color option on every page\n"
						.. "- Bar Texture and Shield Charge Bars: Default\n"
						.. "- Dot Shape: Round, Gem Dot Finish off\n"
						.. "- Glow Shape: Square\n"
						.. "- Frame Edge: Plain\n"
						.. "- Icon Shape on the totem bar, cooldown bar and Ready Reminders: Square, Keep Borders Square off\n"
						.. "- Bar Gradient, Outline Gradient and Charge Bar Gradient: Flat, with their directions and colors\n"
						.. "- Duration Bar Background on\n"
						.. "- each shield's charges: the Bar\n\n"
						.. "Everything you had is kept on the Custom card: click it to bring your whole look back. Your interface reloads to finish.",
					buttons = {
						{ text = "Reset and Reload", onClick = function()
							SP:ResetEverythingToDefault()
							ReloadUI()
						end },
						{ text = "Cancel" },
					},
				})
			end,
		})
		y = y + 4 + eh
	end
	if Includes("picker") then
		y = y + Header(BLOCKS.picker.label, y, W)
		y = RenderPicker(y, W)
	end
	-- Show Icons As only means something for flat boxes: shown with ShamanPower Minimal only
	page.layoutSig = LayoutSig()
	page.showOptions = SP:ThemeGlobal() == "minimal" and Includes("options")
	if page.showOptions then
		y = y + Header(BLOCKS.options.label, y, W)
		y = RenderThemeOptions(y, W)
	end
	if Includes("palettes") then
		y = y + Header(BLOCKS.palettes.label, y, W)
		y = RenderPalettes(y, W)
	end
	-- Border Size: one slider under each turned-on toggle (the square edge and the ring)
	local function BorderSize(field, label, what)
		local _, h = Widgets:Slider(body, {
			label = label, x = 0, y = y, width = W, min = 1, max = 6, step = 1,
			desc = "How thick the element-colored border is on " .. what .. ", in pixels: the square edge, or the ring round Rounded and Circle icons. 2 by default.",
			get = function() return SP:ThemeField(field) or 2 end,
			set = function(v)
				v = math.floor((tonumber(v) or 2) + 0.5)
				if v == 2 then v = nil end
				SP:SetThemeField(field, v)
			end,
			onChanged = PageChanged,
		})
		y = y + h + 6
	end
	if Includes("borders") then
		local _, bh1 = Widgets:Toggle(body, {
			label = BLOCKS.borders.label, x = 0, y = y, width = W,
			desc = BLOCKS.borders.desc,
			get = function() return SP:ThemeField("borders") == true end,
			set = function(v) SP:SetThemeField("borders", v and true or nil) end,
			onChanged = PageChanged,
		})
		y = y + bh1 + 6
		if SP:ThemeField("borders") == true then BorderSize("borderSize", "Border Size", "the totem bar") end
	end
	if SP:ThemeField("borders") == true then   -- only while the borders are on
		if Includes("flyoutBorders") then
			local _, bh2 = Widgets:Toggle(body, {
				label = BLOCKS.flyoutBorders.label, x = 0, y = y, width = W,
				desc = BLOCKS.flyoutBorders.desc,
				get = function() return SP:ThemeField("bordersFlyouts") == true end,
				set = function(v) SP:SetThemeField("bordersFlyouts", v and true or nil) end,
				onChanged = PageChanged,
			})
			y = y + bh2 + 6
			if SP:ThemeField("bordersFlyouts") == true then BorderSize("borderSizeFlyouts", "Flyout Border Size", "the flyouts") end
		end
		if Includes("cooldownBorders") then
			local _, bh3 = Widgets:Toggle(body, {
				label = BLOCKS.cooldownBorders.label, x = 0, y = y, width = W,
				desc = BLOCKS.cooldownBorders.desc,
				get = function() return SP:ThemeField("bordersCooldown") == true end,
				set = function(v) SP:SetThemeField("bordersCooldown", v and true or nil) end,
				onChanged = PageChanged,
			})
			y = y + bh3 + 6
			if SP:ThemeField("bordersCooldown") == true then BorderSize("borderSizeCooldown", "Cooldown Bar Border Size", "the cooldown bar") end
		end
		-- the cooldown bar's shield and imbue flyouts, while its own borders are on
		if SP:ThemeField("bordersCooldown") == true and Includes("cooldownFlyoutBorders") then
			local _, bh4 = Widgets:Toggle(body, {
				label = BLOCKS.cooldownFlyoutBorders.label, x = 0, y = y, width = W,
				desc = BLOCKS.cooldownFlyoutBorders.desc,
				get = function() return SP:ThemeField("bordersCooldownFlyouts") == true end,
				set = function(v) SP:SetThemeField("bordersCooldownFlyouts", v and true or nil) end,
				onChanged = PageChanged,
			})
			y = y + bh4 + 6
			if SP:ThemeField("bordersCooldownFlyouts") == true then
				BorderSize("borderSizeCooldownFlyouts", "Cooldown Bar Flyout Border Size", "the cooldown bar's flyouts")
			end
		end
	end
	if Includes("classColors") then
		y = y + Header(BLOCKS.classColors.label, y, W)
		y = CC.Render(y, W)
	end
	if Includes("shields") then
		y = y + Header(BLOCKS.shields.label, y, W)
		y = RenderShields(y, W)
	end
	if Includes("shapes") then
		y = y + Header(BLOCKS.shapes.label, y, W)
		y = RenderShapes(y, W, selection and selection.shapes)
	end
	if Includes("wow") then
		y = y + Header(BLOCKS.wow.label, y, W)
		y = RenderWoW(y, W)
	end
	for _, mod in ipairs(SP.THEME_MODULES) do
		local matches = selection and selection.modules[mod.key]
		if ModuleShown(mod) and (not selection or matches) then
			y = RenderModule(mod, y, W, type(matches) == "table" and matches or nil)
		end
	end
	-- the page repaints with the window's own refresh (a change on any row)
	body._spRefreshers = body._spRefreshers or {}
	table.insert(body._spRefreshers, RepaintAll)
	page.visible = true
	RepaintAll()
	return y
end

-- Release the drawn blocks before changing the page, tab, or search selection.
function Page:Release()
	local tip = Core:Tooltip()
	local owner = tip:IsShown() and tip:GetOwner()
	if owner and owner.spThemes then tip:Hide() end
	for i = #shown, 1, -1 do
		shown[i]:Hide()
		shown[i] = nil
	end
	for i = #live, 1, -1 do live[i] = nil end
	-- Cached frames stay in store, but only the next render's controls may repaint.
	wipe(pickCards)
	wipe(showCards)
	wipe(palCards)
	wipe(shieldCards)
	wipe(wowRows)
	wipe(shapeCards)
	customLine = nil
	page.sections, page.selection = nil, nil
	page.visible = false
end

-- the module section at page height y (the last one starting at or above it):
-- key, label and (Totem Bar Styles) the spot; nil above the first section
function Page:SectionAt(y)
	local secs = page.sections
	local hit
	if secs then
		for i = 1, #secs do
			if secs[i].y <= y then hit = secs[i] else break end
		end
	end
	if hit then return hit.key, hit.label, hit.spot end
	return nil
end

function Page:IsShown()
	return page.visible and page.body ~= nil and page.body:IsVisible() and true or false
end

-- A theme changed while the page is up (a colour picker drag, a profile switch).
function Page:Repaint()
	if not self:IsShown() then return end
	-- Search text and visibility can change together; refresh through the window
	-- so it retains the query and scroll position instead of drawing the full page.
	if (page.selection or LayoutSig() ~= page.layoutSig) and ns.SPConfig and ns.SPConfig.RefreshCurrent then
		ns.SPConfig:RefreshCurrent()
		return
	end
	RepaintAll()
end
