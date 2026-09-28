-- ShamanPowerThemeBoxes.lua
-- The flat boxes of the ShamanPower Minimal theme, per spot (General > Themes).
--
-- A LOOK ONLY. A skin is a few textures and one text line drawn on an icon's
-- own frame ABOVE the icon (the icon's draw layer, higher sublevels), anchored
-- to the icon and following it through hooks on the icon's own SetTexture /
-- SetDesaturated / SetAlpha / SetVertexColor / SetTexCoord / Show / Hide. A
-- button keeps its size, position, clicks, flyouts, keybinds, cooldowns,
-- counts and effects: nothing of it is changed, moved or re-wired.
--
-- Every skin belongs to a spot of SP.THEME_MODULES (tb.boxes, cd.shield-box,
-- lo.bar ...). It shows only while SP:ThemeBoxed(spot); its Show Icons As is
-- SP:ThemeShowAs(spot); its colour comes from the spot's roles (SP:ThemeElement,
-- SP:ThemeColor, shield roles). tb.flyout-empty / tb.empty-slot draw the dark
-- box with a dash while SP:ThemeMinimal(spot); tb.sweep / cd.sweep turn the
-- grey cooldown sweep over a box into a dark band. A spot that leaves Minimal
-- hides its skins and the icon shows exactly as before.
--
-- Nothing is created or hooked while no spot is boxed: a player who never picks
-- ShamanPower Minimal runs none of this. Paint code allocates nothing.
-- Displays the game engine draws itself (aura containers on WoW: Forever) are
-- never touched; forbidden frames are never entered.
local SP = ShamanPower
if not SP then return end

local type, pairs, ipairs, select, tonumber, rawget, pcall = type, pairs, ipairs, select, tonumber, rawget, pcall
local floor, min, max = math.floor, math.min, math.max

local IS_MAINLINE = (WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
local secret = issecretvalue or function() return false end
local SECRET = {}                         -- FileOf's answer for a secret texture

local FONT = "Interface\\AddOns\\ShamanPower\\Media\\Fonts\\BebasNeue-Regular.ttf"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local CREAM = { 0.957, 0.937, 0.902 }     -- letters on a dark or saturated box
local INK = { 0.102, 0.133, 0.188 }       -- letters on a light box
local LOGO = (SP.THEME_BRAND and SP.THEME_BRAND.logoBlue) or { 0.247, 0.663, 0.961 }   -- #3FA9F5
local TODAY_SHIELD = { 0.2, 0.6, 1.0 }    -- #3399FF: every shield, today
local DARK = 0.35                         -- nothing down / ghosted / empty: this much of the colour
local DIMMED = 0.6                        -- greyed (out of range, missing, on cooldown)
local GHOST_ALPHA = 0.6                   -- an icon faded below this is "not placed"
local TINT_ALPHA = { tint = 0.75, both = 0.65 }
local LETTER_H = 0.5                      -- letters: at most half the box height (brand-guidelines, section 2)
local LETTER_H_TOP = 0.36                 -- ...smaller at the top when a number sits in the middle
local MIN_FONT = 6                        -- below this the letters would not read: show the one-colour icon

-- ---------------------------------------------------------------------------
-- The spots this file draws
-- ---------------------------------------------------------------------------
local BOX_SPOTS = {
	"tb.boxes", "tb.flyout-boxes", "tb.overlay-boxes", "tb.dropall", "tb.recall",
	"st.boxes-compact", "st.boxes-grid",
	"cd.boxes", "cd.shield-box", "cd.imbue-boxes", "cd.flyout-boxes", "cd.class-icons", "cd.recall",
	"lo.bar", "mod.shieldcharges-icon", "mod.coverage-boxes", "mod.range-boxes", "mod.raidcd-boxes",
	"mod.popouts-boxes", "mod.estracker-box", "mod.plates-boxes",
	"mod.tremor-box", "mod.readyreminders-boxes", "mod.reactive-boxes", "mod.alerts-box", "mod.minimap-boxes",
}
local EMPTY_SPOTS = { "tb.flyout-empty", "tb.empty-slot" }
local EMPTY_SET = { ["tb.flyout-empty"] = true, ["tb.empty-slot"] = true }

local function Boxed(spot) return SP.ThemeBoxed and SP:ThemeBoxed(spot) or false end
local function Minimal(spot) return SP.ThemeMinimal and SP:ThemeMinimal(spot) or false end

local function AnyOn()
	for i = 1, #BOX_SPOTS do if Boxed(BOX_SPOTS[i]) then return true end end
	if IS_MAINLINE then   -- the Empty choice and the unassigned slot exist on WoW: Forever only
		for i = 1, #EMPTY_SPOTS do if Minimal(EMPTY_SPOTS[i]) then return true end end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- What an icon shows: two letters and a colour kind, looked up by its file
-- ---------------------------------------------------------------------------
-- Totems, unique within each element (the colour names the element), indexed
-- like SP.TotemNames. TBC Anniversary and WoW: Forever.
SP.ThemeTotemCodes = {
	[1] = { "SE", "SS", "TR", "EB", "SC", "EE" },             -- Strength of Earth, Stoneskin, Tremor, Earthbind, Stoneclaw, Earth Elemental
	[2] = { "TW", "SR", "MG", "FN", "FT", "FR", "FE" },       -- Totem of Wrath, Searing, Magma, Fire Nova, Flametongue, Frost Resistance, Fire Elemental
	[3] = { "MS", "HS", "MT", "PC", "DC", "FR" },             -- Mana Spring, Healing Stream, Mana Tide, Poison / Disease Cleansing, Fire Resistance
	[4] = { "WF", "GA", "WR", "TA", "GR", "NR", "WW", "SN" }, -- Windfury, Grace of Air, Wrath of Air, Tranquil Air, Grounding, Nature Resistance, Windwall, Sentry
}
-- Other spells, by spell ID: { letters, colour kind, argument }. Unique within
-- the bar that shows them. Colours follow the approved pictures (cd.boxes):
-- Nature's Swiftness in Air, Bloodlust / Heroism in Fire; spells with no
-- element in the spot's Spells colour.
local SPELLS = {
	-- shields (the spot's shield colours)
	[324] = { "LS", "shield", "lightning" }, [24398] = { "WS", "shield", "water" },
	[408510] = { "WS", "shield", "water" }, [52127] = { "WS", "shield", "water" },
	[974] = { "ES", "shield", "earth" }, [32593] = { "ES", "shield", "earth" }, [32594] = { "ES", "shield", "earth" },
	[383648] = { "ES", "shield", "earth" },
	-- weapon imbues (their element)
	[8232] = { "WF", "element", 4 }, [8024] = { "FT", "element", 2 }, [8033] = { "FB", "element", 3 },
	[8017] = { "RB", "element", 1 }, [51730] = { "EL", "element", 1 },
	-- the cooldown bar
	[36936] = { "TC", "brand" },           -- Totemic Call / Recall
	[20608] = { "RE", "brand" },           -- Reincarnation
	[16188] = { "NS", "element", 4 },      -- Nature's Swiftness
	[16190] = { "MT", "element", 3 },      -- Mana Tide Totem
	[30823] = { "SR", "brand" },           -- Shamanistic Rage
	[2825] = { "BL", "element", 2 },       -- Bloodlust
	[32182] = { "HE", "element", 2 },      -- Heroism
	[16166] = { "EM", "brand" },           -- Elemental Mastery
	[425336] = { "RF", "brand" },          -- Rage of the Farseer (WoW: Forever)
	[437009] = { "TP", "brand" },          -- Totemic Projection (WoW: Forever)
	[425874] = { "DT", "element", 1 },     -- Decoy Totem (WoW: Forever, Earth)
}
-- items and plain icon files some displays use: { letters, kind, arg }
local FILES = {
	["Interface\\Icons\\INV_Misc_Drum_02"] = { "DR", "brand" },          -- Drums (Raid Cooldowns)
	["Interface\\Icons\\INV_Misc_Drum_03"] = { "DR", "brand" },
	["Interface\\Icons\\INV_Misc_Drum_04"] = { "DR", "brand" },
	["Interface\\Icons\\ClassIcon_Shaman"] = { "SH", "class", "SHAMAN" }, -- the loadout bar's anchor
}
-- the Raid Cooldowns caller buttons: these take the spot's Bloodlust / Heroism colour
local RAID_SPELL = { BL = true, HE = true, DR = true }
-- class icons: a box in the class colour with the class's two letters
local CLASS_CODES = {
	WARRIOR = "WA", PALADIN = "PA", HUNTER = "HU", ROGUE = "RO", PRIEST = "PR", DEATHKNIGHT = "DK",
	SHAMAN = "SH", MAGE = "MA", WARLOCK = "WL", MONK = "MO", DRUID = "DR", DEMONHUNTER = "DH", EVOKER = "EV",
}
local CLASS_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
-- loadout numbers without building strings while painting
local NUM = {}
for i = 1, 40 do NUM[i] = tostring(i) end

local byFile = {}         -- file ID or path -> { code, kind, arg }
local emptyFile = {}      -- files that mean "no totem here"
local classSheet = {}     -- the class sheet's file ID / path
local codesBuilt = false
local SpellTex = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture

-- two letters from a name nobody listed ("Healing Stream" -> HS, "Stoneskin" -> ST)
local SKIP = { of = true, the = true, totem = true, Totem = true, Of = true, The = true }
local function CodeFromName(name)
	if type(name) ~= "string" or name == "" then return nil end
	local a, b = nil, nil
	for word in name:gmatch("%a+") do
		if not SKIP[word] then
			if not a then a = word elseif not b then b = word break end
		end
	end
	if not a then return nil end
	if b then return (a:sub(1, 1) .. b:sub(1, 1)):upper() end
	return a:sub(1, 2):upper()
end

local function BuildCodes()
	if codesBuilt then return end
	codesBuilt = true
	local scratch = CreateFrame("Frame"):CreateTexture()
	local function keys(tex, fn)
		if tex == nil or secret(tex) then return end
		fn(tex)
		if type(tex) == "string" then
			fn(tex:lower())
			scratch:SetTexture(tex)
			local id = scratch.GetTextureFileID and scratch:GetTextureFileID()
			if id and id ~= 0 then fn(id) end
		end
	end
	local function add(tex, info) keys(tex, function(k) if byFile[k] == nil then byFile[k] = info end end) end
	for element = 1, 4 do
		local codes = SP.ThemeTotemCodes[element] or {}
		local names = SP.TotemNames and SP.TotemNames[element] or {}
		local icons = SP.TotemIcons and SP.TotemIcons[element] or {}
		local spells = SP.Totems and SP.Totems[element] or {}
		local seen = {}
		for idx in pairs(codes) do seen[idx] = true end
		for idx in pairs(names) do seen[idx] = true end
		for idx in pairs(icons) do seen[idx] = true end
		for idx in pairs(spells) do seen[idx] = true end
		for idx in pairs(seen) do
			local code = codes[idx] or CodeFromName(names[idx])
			if code then
				local info = { code, "element", element }
				add(icons[idx], info)
				local spell = spells[idx]
				if type(spell) == "number" and SpellTex then
					local ok, tex = pcall(SpellTex, spell)
					if ok then add(tex, info) end
				end
			end
		end
	end
	for spell, info in pairs(SPELLS) do
		if SpellTex then
			local ok, tex = pcall(SpellTex, spell)
			if ok then add(tex, info) end
		end
	end
	local WEAPON = { { "WF", 4 }, { "FT", 2 }, { "FB", 3 }, { "RB", 1 } }
	for e, tex in pairs(SP.WeaponIcons or {}) do
		local w = WEAPON[e]
		if w then add(tex, { w[1], "element", w[2] }) end
	end
	if SP.EarthShield and SP.EarthShield.icon then add(SP.EarthShield.icon, { "ES", "shield", "earth" }) end
	for path, info in pairs(FILES) do add(path, info) end
	for class, code in pairs(CLASS_CODES) do
		local name = class:sub(1, 1) .. class:sub(2):lower()
		if class == "DEATHKNIGHT" then name = "DeathKnight" elseif class == "DEMONHUNTER" then name = "DemonHunter" end
		add("Interface\\Icons\\ClassIcon_" .. name, { code, "class", class })
	end
	keys(CLASS_SHEET, function(k) classSheet[k] = true end)
	-- "no totem here": Blizzard's totem bar sheet (the flyout's Empty choice,
	-- cut by texcoords) and the question mark. The element placeholder icons are
	-- NOT empty: each is also a real totem's icon (Earth Elemental, Fire Nova...).
	keys("Interface\\Buttons\\UI-TotemBar", function(k) emptyFile[k] = true end)
	keys("Interface\\Icons\\INV_Misc_QuestionMark", function(k) emptyFile[k] = true end)
end

-- the icon's file (ID first), SECRET, or nil
local function FileOf(icon)
	local id = icon.GetTextureFileID and icon:GetTextureFileID()
	if secret(id) then return SECRET end
	if id and id ~= 0 then return id end
	local path = icon:GetTexture()
	if secret(path) then return SECRET end
	if path == nil or path == 0 or path == "" then return nil end
	return path
end

-- ---------------------------------------------------------------------------
-- Colours
-- ---------------------------------------------------------------------------
local function lin(v) if v <= 0.03928 then return v / 12.92 end return ((v + 0.055) / 1.055) ^ 2.4 end
local function Lum(r, g, b) return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) end
local L_INK, L_CREAM = Lum(INK[1], INK[2], INK[3]), Lum(CREAM[1], CREAM[2], CREAM[3])
-- ink or cream, whichever reads better on the box (WCAG contrast): any palette,
-- a Custom one too, stays readable
local function InkOn(r, g, b)
	local L = Lum(r, g, b)
	return (L + 0.05) / (L_INK + 0.05) >= (L_CREAM + 0.05) / (L + 0.05)
end

local function ClassRGB(class)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return LOGO[1], LOGO[2], LOGO[3]
end

-- a forced palette (a preview card drawn in a given theme)
local function ForcedRGB(pal, ck, arg)
	if ck == "element" then return SP:ThemePaletteRGB(pal, arg) end
	if ck == "shield" then
		if arg == "water" then return SP:ThemePaletteRGB(pal, 3) end
		if arg == "earth" then return SP:ThemePaletteRGB(pal, 1) end
	end
	return LOGO[1], LOGO[2], LOGO[3]
end

-- the box colour of one skin: the spot's roles; nil roles fall back to today
local function SkinRGB(s, spot, ck, arg)
	if ck == "class" then return ClassRGB(arg) end
	local f = s.force
	if f and f.palette then return ForcedRGB(f.palette, ck, arg) end
	if ck == "element" then return SP:ThemeElement(spot, arg) end
	local r, g, b
	if ck == "shield" then
		r, g, b = SP:ThemeColor(spot, arg)
		if r then return r, g, b end
		r, g, b = SP:ThemeColor("cd.shield-box", arg)   -- a spot without shield roles: the shield button's
		if r then return r, g, b end
		return TODAY_SHIELD[1], TODAY_SHIELD[2], TODAY_SHIELD[3]
	end
	-- spells with no element, Totemic Call, the loadout numbers
	r, g, b = SP:ThemeColor(spot, "spell")
	if r then return r, g, b end
	r, g, b = SP:ThemeColor(spot, "box")
	if r then return r, g, b end
	return LOGO[1], LOGO[2], LOGO[3]
end

-- General > Themes > Element-Colored Borders, Also on the Cooldown Bar
-- (ShamanPower.lua ThemeBorderEdges): the colour a flat box gives this icon.
-- Element spells and imbues in their element, shields in the Shield Colors,
-- other spells in the logo blue; nil while the icon can't be read (secret).
local NO_FORCE = {}
function SP:ThemeIconRGB(icon, spot)
	if not icon then return nil end
	BuildCodes()
	local f = FileOf(icon)
	if f == SECRET then return nil end
	local info = f and byFile[f]
	return SkinRGB(NO_FORCE, spot, info and info[2], info and info[3])
end

-- ---------------------------------------------------------------------------
-- Which spot a skin belongs to (it can change: Grid, a pop-out)
-- ---------------------------------------------------------------------------
local TOTEM_KEYS = { "totem_earth", "totem_fire", "totem_water", "totem_air" }
local CD_KEYS = {}
for i = 1, 24 do CD_KEYS[i] = "cd_" .. i end

local function GridOn() return SP.GridActive and SP:GridActive() or false end
local function Popped(key)
	local p = key and SP.opt and SP.opt.poppedOut
	return p and p[key] and true or false
end

-- box spot, spot whose Minimal draws the empty dark box, sweep spot
local function SpotOf(s)
	local k = s.kind
	if k == "main" or k == "assigned" then
		if GridOn() then return "st.boxes-grid", "tb.empty-slot", "tb.sweep" end
		if Popped(TOTEM_KEYS[s.element]) then return "mod.popouts-boxes", "tb.empty-slot", "tb.sweep" end
		return "tb.boxes", "tb.empty-slot", "tb.sweep"
	elseif k == "flyout" then
		if s.host.totemIndex == 0 then return "tb.flyout-empty", "tb.flyout-empty", "tb.sweep" end
		if GridOn() then return "st.boxes-grid", "tb.flyout-empty", "tb.sweep" end
		return "tb.flyout-boxes", "tb.flyout-empty", "tb.sweep"
	elseif k == "cd" or k == "cd2" then
		local btn = s.host
		if Popped(CD_KEYS[btn.cooldownType or 0]) then return "mod.popouts-boxes", "mod.popouts-boxes", "cd.sweep" end
		local t = btn.spellType
		local spot = (t == "shield" and "cd.shield-box") or (t == "weaponImbue" and "cd.imbue-boxes")
			or (btn.spellID == 36936 and "cd.recall") or "cd.boxes"
		return spot, spot, "cd.sweep"
	elseif k == "esbtn" then
		if SP.IsEarthShieldPoppedOut and SP:IsEarthShieldPoppedOut() then return "mod.popouts-boxes", "mod.popouts-boxes", "cd.sweep" end
		return "cd.shield-box", "cd.shield-box", "cd.sweep"
	elseif k == "dropall" then
		if SP.IsDropAllPoppedOut and SP:IsDropAllPoppedOut() then return "mod.popouts-boxes", "mod.popouts-boxes", "tb.sweep" end
		return "tb.dropall", "tb.dropall", "tb.sweep"
	end
	local spot = s.spot
	return spot, s.emptySpot or spot, s.sweepSpot or "tb.sweep"
end

-- the spot whose colours an empty dark box takes (its neighbours' colours)
local function EmptyColorSpot(spot)
	if spot == "tb.flyout-empty" then return GridOn() and "st.boxes-grid" or "tb.flyout-boxes" end
	if spot == "tb.empty-slot" then return GridOn() and "st.boxes-grid" or "tb.boxes" end
	return spot
end

-- ---------------------------------------------------------------------------
-- The skin
-- ---------------------------------------------------------------------------
local skins = {}          -- [icon texture] = skin (real bars and previews)
local realList = {}       -- the real bars' skins, in creation order
local mainSkins = {}      -- [element] = the totem button's skin (tracks "nothing down")
local on = false          -- any of this file's spots draws
local Paint               -- below

local function Region(host, layer, sub)
	local t = host:CreateTexture(nil, layer, nil, sub)
	t:Hide()
	return t
end
local function Inset(t, icon, d)
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", icon, "TOPLEFT", d, -d)
	t:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -d, d)
end

local function OnIconChanged(icon)
	local s = skins[icon]
	if s and (on or s.visible or s.force) then Paint(s) end
end
local function OnIconCoords(icon)
	local s = skins[icon]
	if not (s and (on or s.visible or s.force)) then return end
	local ulx, uly, _, _, _, _, lrx, lry = icon:GetTexCoord()
	if ulx ~= s.tcUlx or uly ~= s.tcUly or lrx ~= s.tcLrx or lry ~= s.tcLry then
		s.kFile = false   -- a full paint: the tint copies the icon's coordinates
		Paint(s)
	end
end

-- A FontString that sits on the icon: a number in the middle moves the letters
-- to the top (center), a label over the whole box hides them (yield).
local textOwner = {}
local function OnTextShown(fs)
	local s = textOwner[fs]
	if s and s.visible then s.kFile = false; Paint(s) end
end
local function AddText(s, fs, yield)
	if type(fs) ~= "table" or textOwner[fs] then return end
	local ok, kind = pcall(fs.GetObjectType, fs)
	if not ok or kind ~= "FontString" then return end
	textOwner[fs] = s
	local list = yield and "yields" or "centers"
	local t = s[list]
	if not t then t = {}; s[list] = t end
	t[#t + 1] = fs
	hooksecurefunc(fs, "Show", OnTextShown)
	hooksecurefunc(fs, "Hide", OnTextShown)
	hooksecurefunc(fs, "SetShown", OnTextShown)
end
local function Busy(list)
	if not list then return false end
	for i = 1, #list do
		local fs = list[i]
		if fs:IsShown() then
			local t = fs:GetText()
			if secret(t) or (t ~= nil and t ~= "") then return true end
		end
	end
	return false
end

-- ---- cooldown sweeps -------------------------------------------------------
-- The grey sweeps a button draws over its icon (the grey that grows down) sit
-- in the icon's own layer, under the box. A band on the box follows each one:
-- today's grey icon while the sweep spot is on Standard, a dark band under
-- ShamanPower Minimal (tb.sweep / cd.sweep).
local SWEEP_FIELDS = { "greyOverlay", "cdSweep", "greyOverlayMain", "greyOverlayOff" }

local function SyncSweep(s, i)
	local src, band = s.sweepSrc[i], s.sweeps[i]
	if not (s.visible and src:IsShown()) then band:Hide() return end
	if s.sweepDark then
		if band.spMode ~= 1 then
			band:SetTexture(WHITE)
			band:SetTexCoord(0, 1, 0, 1)
			band:SetDesaturated(false)
			band:SetVertexColor(0, 0, 0, 0.5)
			band.spMode = 1
		end
	else
		local tex = src:GetTexture()
		if secret(tex) then band:Hide() return end
		band:SetTexture(tex)
		band:SetTexCoord(src:GetTexCoord())
		band:SetDesaturated(src:IsDesaturated() and true or false)
		band:SetVertexColor(src:GetVertexColor())
		band.spMode = 2
	end
	band:Show()
end

local function Sweeps(s)
	local host = s.host
	for f = 1, #SWEEP_FIELDS do
		local src = rawget(host, SWEEP_FIELDS[f])
		if src and not s.sweepSeen[src] then
			s.sweepSeen[src] = true
			local band = host:CreateTexture(nil, s.layer, nil, s.bandSub)
			band:SetAllPoints(src)
			band:Hide()
			local i = #s.sweeps + 1
			s.sweeps[i], s.sweepSrc[i] = band, src
			local function sync() SyncSweep(s, i) end
			hooksecurefunc(src, "Show", sync)
			hooksecurefunc(src, "Hide", sync)
			hooksecurefunc(src, "SetShown", sync)
			hooksecurefunc(src, "SetTexture", sync)
			hooksecurefunc(src, "SetTexCoord", sync)
			SyncSweep(s, i)
		end
	end
end

-- WoW: Forever's engine-filled sweep (a StatusBar of the greyed icon, above
-- the button's own layers): under a Minimal sweep spot its fill turns into the
-- dark band; back on Standard it gets exactly the look ShamanPower.lua gives it.
local function DarkenEngineBar(bar)
	bar:SetStatusBarTexture(WHITE)
	if bar.SetStatusBarDesaturated then bar:SetStatusBarDesaturated(false) end
	bar:SetStatusBarColor(0, 0, 0, 0.5)
	local t = bar:GetStatusBarTexture()
	if t then t:SetDesaturated(false) end
	bar.spThemeBand = true
end
local function RestoreEngineBar(bar, icon)
	local tex = icon and icon:GetTexture()
	if tex ~= nil and not secret(tex) then bar:SetStatusBarTexture(tex) end
	if bar.SetStatusBarDesaturated then bar:SetStatusBarDesaturated(true) end
	bar:SetStatusBarColor(0.5, 0.5, 0.5, 1)
	local t = bar:GetStatusBarTexture()
	if t then t:SetDesaturated(true); t:SetVertexColor(0.5, 0.5, 0.5) end
	bar.spThemeBand = nil
end
-- fresh = ShamanPower.lua just (re)built the bar's look (post-hook)
local function EngineSweep(s, fresh)
	if not IS_MAINLINE or s.noSweeps then return end
	local bar = rawget(s.host, "cdBar")
	if not bar then return end
	local want = s.visible and s.sweepDark
	if fresh then
		bar.spThemeBand = nil
		if want then DarkenEngineBar(bar) end
	elseif want and not bar.spThemeBand then
		DarkenEngineBar(bar)
	elseif not want and bar.spThemeBand then
		RestoreEngineBar(bar, s.icon)
	end
end

-- ---- make / hide -----------------------------------------------------------
local function MakeSkin(host, icon)
	local s = { host = host, icon = icon, sweeps = {}, sweepSrc = {}, sweepSeen = {} }
	-- just above the icon, in its own draw layer (most icons: ARTWORK 0)
	local layer, sub = icon:GetDrawLayer()
	if layer ~= "BACKGROUND" and layer ~= "BORDER" and layer ~= "ARTWORK" and layer ~= "OVERLAY" then layer = "ARTWORK" end
	sub = tonumber(sub) or 0
	local function lv(n) return min(7, sub + n) end
	s.layer, s.bandSub = layer, lv(7)
	s.base = Region(host, layer, lv(2))                     -- the black edge round the box
	s.base:SetColorTexture(0, 0, 0, 1)
	s.base:SetAllPoints(icon)
	s.box = Region(host, layer, lv(3))
	s.box:SetColorTexture(1, 1, 1, 1)
	Inset(s.box, icon, 1)
	s.tint = Region(host, layer, lv(4))
	Inset(s.tint, icon, 1)
	s.miniBd = Region(host, layer, lv(4))
	s.miniBd:SetColorTexture(0, 0, 0, 1)
	s.miniBd:SetPoint("CENTER", icon, "CENTER", 0, 0)
	s.mini = Region(host, layer, lv(5))
	s.mini:SetPoint("CENTER", icon, "CENTER", 0, 0)
	s.shade = Region(host, layer, lv(6))
	s.shade:SetColorTexture(0, 0, 0, 1)
	Inset(s.shade, icon, 1)
	-- letters: above the box, under the button's own OVERLAY texts and shades
	s.text = host:CreateFontString(nil, "OVERLAY", nil, layer == "OVERLAY" and 7 or -1)
	s.text:SetFont(FONT, 10, "")
	s.text:SetJustifyH("CENTER")
	s.text:Hide()
	s.regions = { s.base, s.box, s.tint, s.miniBd, s.mini, s.shade, s.text }
	skins[icon] = s
	hooksecurefunc(icon, "SetTexture", OnIconChanged)
	hooksecurefunc(icon, "SetDesaturated", OnIconChanged)
	hooksecurefunc(icon, "SetAlpha", OnIconChanged)
	hooksecurefunc(icon, "SetVertexColor", OnIconChanged)
	hooksecurefunc(icon, "SetTexCoord", OnIconCoords)
	hooksecurefunc(icon, "Show", OnIconChanged)
	hooksecurefunc(icon, "Hide", OnIconChanged)
	hooksecurefunc(icon, "SetShown", OnIconChanged)
	return s
end

local function HideSkin(s)
	local r = s.regions
	for i = 1, #r do r[i]:Hide() end
	s.visible = false
	for i = 1, #s.sweeps do s.sweeps[i]:Hide() end
	EngineSweep(s, false)
	s.kFile = false   -- the next paint starts over
end

-- ---- paint -----------------------------------------------------------------
local function BoxOn(s, spot)
	local f = s.force
	if f and f.boxed ~= nil then return f.boxed end
	if s.mockBar then
		local W = SP.Wizard
		local st = SP.GetTotemBarStyle and SP:GetTotemBarStyle(W and W.optOverride or nil) or "normal"
		if st ~= "normal" and st ~= "totemtimers" and st ~= "single" and st ~= "dynamic" then return false end
	end
	return Boxed(spot)
end
local function MinimalOn(s, spot)
	local f = s.force
	if f and f.boxed ~= nil then return f.boxed end
	return Minimal(spot)
end

-- which class a cut of the class sheet shows: by its coordinates (set before the
-- button's class attribute when the flyout is refilled), else the attribute
local function ClassOf(s)
	local tc = CLASS_ICON_TCOORDS
	local ulx, uly = s.icon:GetTexCoord()
	if tc and type(ulx) == "number" and not secret(ulx) then
		for class, c in pairs(tc) do
			if math.abs(c[1] - ulx) < 0.01 and math.abs(c[3] - uly) < 0.01 then return class end
		end
	end
	local host = s.host
	if host.GetAttribute then
		local ok, c = pcall(host.GetAttribute, host, "memberClass")
		if ok and type(c) == "string" and not secret(c) and CLASS_CODES[c] then return c end
	end
	return nil
end

-- the loadout number a button shows
local function LoadoutCode(s)
	if s.loadoutAnchor then
		local n = SP.opt and SP.opt.activeLoadout
		return type(n) == "number" and NUM[n] or nil
	end
	if s.loadoutIndex then return NUM[s.loadoutIndex] end
	local host = s.host
	if host.GetAttribute then
		local ok, n = pcall(host.GetAttribute, host, "loadoutIndex")
		if ok and type(n) == "number" and not secret(n) then return NUM[n] end
	end
	return nil
end

-- Draw a skin from its icon's state. Cheap to call often: it returns early when
-- nothing it draws from has changed. Allocates nothing.
Paint = function(s)
	local icon = s.icon
	if not icon:IsShown() then
		if s.visible then HideSkin(s) end
		return
	end
	local spot, emptySpot, sweepSpot = SpotOf(s)
	local file = FileOf(icon)
	if file == SECRET then   -- a texture the game keeps secret: the real icon stays
		if s.visible then HideSkin(s) end
		return
	end
	local isEmpty = s.forceEmpty or file == nil or emptyFile[file] or false
	local box
	if isEmpty and EMPTY_SET[emptySpot] then
		-- the dark box with a dash is its own spot; WoW: Forever only (the Classic
		-- line has no Empty choice and no unassigned-slot art: it stays as it is)
		box = IS_MAINLINE and MinimalOn(s, emptySpot) or false
	else
		box = BoxOn(s, spot)
	end
	if not box then
		if s.visible then HideSkin(s) end
		return
	end

	-- what it is: letters and colour kind
	local code, ck, arg = s.code, s.ck, s.arg
	if not isEmpty then
		local info = byFile[file]
		if info then
			if not code then code = info[1] end
			if not ck then ck, arg = info[2], info[3] end
		elseif classSheet[file] then
			local class = ClassOf(s)
			if class then
				code, ck, arg = code or CLASS_CODES[class], "class", class
			else
				isEmpty = true
			end
		end
		if s.loadout then code = LoadoutCode(s) or code end
	end
	if s.element and not s.ck and ck ~= "class" and ck ~= "shield" then ck, arg = "element", s.element end
	if spot == "mod.raidcd-boxes" and code and RAID_SPELL[code] then ck, arg = "brand", nil end
	if not ck then ck = "brand" end

	local colorSpot = isEmpty and EmptyColorSpot(EMPTY_SET[emptySpot] and emptySpot or spot) or spot
	if isEmpty and not s.element then ck = "brand" end
	local r, g, b = SkinRGB(s, colorSpot, isEmpty and (s.element and "element" or "brand") or ck,
		isEmpty and s.element or arg)
	local cr, cg, cb = r, g, b

	-- state: ghosted / nothing down (dark), greyed (dim). The loadout bar dims its
	-- icon under the four small totems: that is a backdrop, not a state.
	local a = icon:GetAlpha() or 1
	if secret(a) or s.loadout then a = 1 end
	local f = s.force
	local placed = s.placed
	if f and f.placed ~= nil then placed = f.placed end
	local ghost = isEmpty or placed == false or a < GHOST_ALPHA
	local dim = false
	if not ghost then
		local d = icon.IsDesaturated and icon:IsDesaturated()
		local vr = icon:GetVertexColor()
		if secret(d) then d = false end
		if secret(vr) then vr = 1 end
		dim = d and true or ((tonumber(vr) or 1) < 0.95)
	end
	local k = ghost and DARK or (dim and DIMMED or 1)
	r, g, b = r * k, g * k, b * k
	local da = ghost and 1 or a   -- a ghosted icon's box is solid dark, not see-through

	local mode = (f and f.showAs) or (SP.ThemeShowAs and SP:ThemeShowAs(spot)) or "both"
	local h, w = icon:GetHeight(), icon:GetWidth()
	if not h or h < 4 then h = s.host:GetHeight() or 26 end
	if not w or w < 4 then w = h end
	local top = Busy(s.centers)
	local yield = Busy(s.yields)
	local sweepDark = (not s.noSweeps) and MinimalOn(s, sweepSpot) or false
	local ulx, uly, _, _, _, _, lrx, lry = icon:GetTexCoord()

	if s.visible and s.kFile == file and s.kCode == code and s.kMode == mode and s.kR == r and s.kG == g and s.kB == b
		and s.kA == da and s.kH == h and s.kW == w and s.kTop == top and s.kYield == yield and s.kEmpty == isEmpty
		and s.kDark == sweepDark and s.tcUlx == ulx and s.tcUly == uly and s.tcLrx == lrx and s.tcLry == lry then
		if not s.noSweeps then Sweeps(s) end   -- a sweep the button made since
		return
	end
	s.visible, s.kFile, s.kCode, s.kMode, s.kR, s.kG, s.kB, s.kA, s.kH, s.kW, s.kTop, s.kYield, s.kEmpty, s.kDark =
		true, file, code, mode, r, g, b, da, h, w, top, yield, isEmpty, sweepDark
	s.tcUlx, s.tcUly, s.tcLrx, s.tcLry = ulx, uly, lrx, lry
	s.sweepDark = sweepDark

	-- letters (the dash on an empty box): at most half the box, always inside it
	local text = isEmpty and "-" or code
	local lettersOn = isEmpty or ((mode == "letters" or mode == "both") and code ~= nil and not yield)
	local size = 0
	if lettersOn then
		local bh, bw = h - 2, w - 2
		size = floor(bh * ((top and not isEmpty) and LETTER_H_TOP or LETTER_H))
		local wcap = floor((bw - 2) / (0.5 * max(#text, 1) + 0.1))
		if wcap < size then size = wcap end
		if size < MIN_FONT then lettersOn = false end
	end
	-- letters that cannot be drawn (too small, nothing known): the one-colour icon says it
	local fallbackTint = not isEmpty and not lettersOn and (mode == "letters" or mode == "both")
	local trim = (ulx == 0 and uly == 0 and lrx == 1 and lry == 1)

	s.base:Show()
	s.box:SetVertexColor(r, g, b)
	s.box:SetAlpha(da)
	s.box:Show()

	local tintOn = not isEmpty and (mode == "tint" or mode == "both" or fallbackTint)
	if tintOn then
		local tint = s.tint
		tint:SetTexture(file)
		if trim then tint:SetTexCoord(0.08, 0.92, 0.08, 0.92) else tint:SetTexCoord(icon:GetTexCoord()) end
		tint:SetDesaturated(true)
		tint:SetVertexColor(r, g, b)
		tint:SetAlpha(da * ((mode == "both" and lettersOn) and TINT_ALPHA.both or TINT_ALPHA.tint))
	end
	s.tint:SetShown(tintOn)

	local miniOn = not isEmpty and mode == "mini"
	if miniOn then
		local m = floor(min(h, w) * 0.56 + 0.5)
		local mini = s.mini
		mini:SetSize(m, m)
		s.miniBd:SetSize(m + 2, m + 2)
		mini:SetTexture(file)
		if trim then mini:SetTexCoord(0.08, 0.92, 0.08, 0.92) else mini:SetTexCoord(icon:GetTexCoord()) end
		mini:SetDesaturated(dim and true or false)
		mini:SetAlpha(da * (ghost and 0.55 or 1))
		s.miniBd:SetAlpha(da)
	end
	s.mini:SetShown(miniOn)
	s.miniBd:SetShown(miniOn)

	local shadeOn = mode == "both" and tintOn and lettersOn
	if shadeOn then s.shade:SetAlpha(da * 0.27) end
	s.shade:SetShown(shadeOn)

	local t = s.text
	if lettersOn then
		if s.kSize ~= size then t:SetFont(FONT, size, ""); s.kSize = size end
		t:ClearAllPoints()
		if top and not isEmpty then t:SetPoint("TOP", icon, "TOP", 0, -2) else t:SetPoint("CENTER", icon, "CENTER", 0, 1) end
		if ghost then
			-- the dark box: the letters in a mid shade of the same colour
			t:SetTextColor(cr * 0.67, cg * 0.67, cb * 0.67)
			t:SetShadowOffset(0, 0)
		elseif InkOn(r, g, b) then
			t:SetTextColor(INK[1], INK[2], INK[3])
			t:SetShadowOffset(0, 0)
		else
			t:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
			t:SetShadowColor(0, 0, 0, 0.6)
			t:SetShadowOffset(1, -1)
		end
		t:SetAlpha(da)
		t:SetText(text)
	end
	t:SetShown(lettersOn)

	if not s.noSweeps then
		Sweeps(s)
		for i = 1, #s.sweeps do SyncSweep(s, i) end
		EngineSweep(s, false)
	end
end

-- ---------------------------------------------------------------------------
-- Surfaces: each collector hands icons to Skin(); a skin is made once per icon
-- ---------------------------------------------------------------------------
local pendingCombat = false   -- a protected frame met in combat: made after the fight

local function IsTexture(t)
	if type(t) ~= "table" or not t.GetObjectType then return false end
	local ok, kind = pcall(t.GetObjectType, t)
	return ok and kind == "Texture"
end
local function Forbidden(f)
	return f.IsForbidden and f:IsForbidden() or false
end

local function NewSkin(icon)
	if not IsTexture(icon) then return nil end
	local host = icon:GetParent()
	if not host or Forbidden(host) then return nil end
	if InCombatLockdown() and host.IsProtected and host:IsProtected() then pendingCombat = true return nil end
	return MakeSkin(host, icon)
end

-- a real bar's icon: kind decides the spot, element the colour
local function Skin(icon, kind, element)
	if not icon then return nil end
	local s = skins[icon]
	if s then return s end
	s = NewSkin(icon)
	if not s then return nil end
	s.kind, s.element = kind, element
	realList[#realList + 1] = s
	return s
end
local function SkinSpot(icon, spot, element, noSweeps)
	local s = Skin(icon, "spot", element)
	if s and not s.spot then s.spot = spot end
	if s and noSweeps then s.noSweeps = true end
	return s
end

local EMPTY = {}   -- read-only stand-in for a list that is not there (no table per call)
local SHIELD_CHARGE_FRAMES = { "ShamanPowerPlayerShieldCharge", "ShamanPowerEarthShieldCharge" }
local CALLER_BUTTONS = { "ShamanPowerCallerBLBtn", "ShamanPowerCallerDrumBtn" }

local function Named(name) local f = _G[name]; if type(f) == "table" then return f end return nil end
local function IconOf(btn, name)
	local icon = rawget(btn, "icon")
	if icon then return icon end
	return name and Named(name .. "Icon") or nil
end

-- the totem bar: buttons, the corner of TotemTimers, the dropped-totem overlay,
-- flyouts, Compact's squares, Drop All and Totemic Call
local function TotemBar()
	local bars = SP.totemProgressBars
	for element = 1, 4 do
		local btn = SP.totemButtons and SP.totemButtons[element]
		if btn then
			local s = Skin(btn.icon, "main", element)
			if s then
				mainSkins[element] = s
				AddText(s, rawget(btn, "cooldownText"))
				local rc = SP.rangeCounterTexts and SP.rangeCounterTexts[element]
				AddText(s, rc)
				local pb = bars and bars[element]
				if pb then AddText(s, rawget(pb, "iconText")) end
			end
			Skin(rawget(btn, "assignedIndicatorIcon"), "assigned", element)
			local c = rawget(btn, "compact")
			if c and c.sq then SkinSpot(c.sq, "st.boxes-compact", element, true) end
		end
		local ov = SP.activeTotemOverlays and SP.activeTotemOverlays[element]
		if ov and ov.icon then SkinSpot(ov.icon, "tb.overlay-boxes", element) end
		local fly = SP.totemFlyouts and SP.totemFlyouts[element]
		local all = fly and fly.allButtons
		if all then
			for i = 1, #all do
				local fb = all[i]
				if fb and fb.icon then Skin(fb.icon, "flyout", element) end
			end
		end
	end
	local da = Named("ShamanPowerAutoDropAll")
	if da then
		local s = Skin(IconOf(da, "ShamanPowerAutoDropAll"), "dropall")
		if s then s.code = "DA" end
	end
	local tc = Named("ShamanPowerAutoTotemicCall")
	if tc then
		local s = SkinSpot(IconOf(tc, "ShamanPowerAutoTotemicCall"), "tb.recall")
		if s then s.code, s.ck = "TC", "brand" end
	end
	-- Compact's lines for the shield and Earth Shield
	local c = SP.shieldButton and rawget(SP.shieldButton, "compact")
	if c and c.sq then SkinSpot(c.sq, "st.boxes-compact", nil, true) end
	local es = Named("ShamanPowerEarthShieldBtn")
	c = es and rawget(es, "compact")
	if c and c.sq then SkinSpot(c.sq, "st.boxes-compact", nil, true) end
end

-- the cooldown bar: every button (the imbue's two halves), the shield and
-- imbue flyouts, the Earth Shield button, its overlay and its class flyout
local function CooldownBar()
	local list = SP.cooldownButtons
	if list then
		for i = 1, #list do
			local btn = list[i]
			local s = btn and Skin(btn.icon, "cd")
			if s then
				AddText(s, rawget(btn, "iconText"))
				AddText(s, rawget(btn, "timeText"))
				if btn.spellID == 36936 and btn.spellType ~= "shield" then s.code, s.ck = "TC", "brand" end
			end
			local icon2 = btn and rawget(btn, "icon2")
			if icon2 then
				local s2 = Skin(icon2, "cd2")
				if s2 then s2.noSweeps = true; AddText(s2, rawget(btn, "iconText2")) end
			end
		end
	end
	local nShield = (SP.ShieldSpells and #SP.ShieldSpells or 2) + 2
	for i = 1, nShield do
		local f = Named("ShamanPowerShieldFlyout" .. i)
		if f and f.icon then SkinSpot(f.icon, "cd.flyout-boxes", nil, true) end
	end
	for i = 1, 6 do
		local f = Named("ShamanPowerImbueFlyout" .. i)
		if f and f.icon then SkinSpot(f.icon, "cd.flyout-boxes", nil, true) end
	end
	local es = Named("ShamanPowerEarthShieldBtn")
	if es then
		local s = Skin(IconOf(es, "ShamanPowerEarthShieldBtn"), "esbtn")
		if s then s.ck, s.arg = "shield", "earth" end
	end
	local ov = SP.esActiveOverlay
	if type(ov) == "table" and ov.icon then
		local s = Skin(ov.icon, "esbtn")
		if s then s.ck, s.arg, s.noSweeps = "shield", "earth", true end
	end
	local fly = SP.esFlyoutButtons
	if fly then
		for _, b in pairs(fly) do
			if type(b) == "table" and b.icon then
				local s = SkinSpot(b.icon, "cd.class-icons")
				if s then s.noSweeps = true; AddText(s, rawget(b, "nameText"), true) end
			end
		end
	end
end

-- the loadout bar: the anchor (active loadout), its buttons (their numbers) and
-- the four small totems in their corners
local function LoadoutBar()
	local function minis(btn)
		local m = rawget(btn, "miniIcons")
		if m then
			for e = 1, 4 do
				local s = m[e] and SkinSpot(m[e], "lo.bar", e)
				if s then s.noSweeps = true end
			end
		end
	end
	local anchor = SP.loadoutAnchor
	if anchor then
		local s = SkinSpot(anchor.icon, "lo.bar")
		if s then s.loadout, s.loadoutAnchor, s.ck, s.noSweeps = true, true, "brand", true end
		minis(anchor)
	end
	for _, btn in ipairs(SP.loadoutButtons or EMPTY) do
		local s = SkinSpot(btn.icon, "lo.bar")
		if s then s.loadout, s.ck, s.noSweeps = true, "brand", true end
		minis(btn)
	end
end

-- single totems popped out (their own icon holder); a popped-out button keeps
-- its skin and switches to the Pop-Out spot by itself
local function PopOuts()
	for _, f in pairs(SP.poppedOutFrames or EMPTY) do
		local tex = type(f) == "table" and rawget(f, "iconTex")
		if tex then
			local s = SkinSpot(tex, "mod.popouts-boxes", rawget(f, "element"))
			if s then s.sweepSpot = "tb.sweep" end
		end
	end
end

local function Coverage()
	local frame = SP.coverageFrame
	if not frame then return end
	for element, btn in pairs(frame.buttons or EMPTY) do
		local s = btn.icon and SkinSpot(btn.icon, "mod.coverage-boxes", element)
		if s then s.noSweeps = true; AddText(s, rawget(btn, "statusText"), true) end
	end
	for key, btn in pairs(frame.totemCells or EMPTY) do
		local element = type(key) == "number" and floor(key / 100) or nil
		if element and (element < 1 or element > 4) then element = nil end
		local s = btn.icon and SkinSpot(btn.icon, "mod.coverage-boxes", element)
		if s then s.noSweeps = true; AddText(s, rawget(btn, "statusText"), true) end
	end
end

local function RangeTracker()
	local frame = SP.spRangeFrame
	local host = frame and rawget(frame, "iconContainer")
	if not host then return end
	for i = 1, select("#", host:GetChildren()) do
		local btn = select(i, host:GetChildren())
		local icon = btn and rawget(btn, "icon")
		if icon then
			local s = SkinSpot(icon, "mod.range-boxes")
			if s then s.noSweeps = true; AddText(s, rawget(btn, "statusText"), true) end
		end
	end
end

local function ESTracker()
	for _, btn in pairs(SP.esTrackerButtons or EMPTY) do
		local icon = type(btn) == "table" and rawget(btn, "icon")
		if icon then
			local s = SkinSpot(icon, "mod.estracker-box")
			if s then s.ck, s.arg, s.noSweeps = "shield", "earth", true; AddText(s, rawget(btn, "targetText")) end
		end
	end
end

local function ShieldCharges()
	for _, name in ipairs(SHIELD_CHARGE_FRAMES) do
		local f = Named(name)
		local icon = f and rawget(f, "icon")
		if icon then
			local s = SkinSpot(icon, "mod.shieldcharges-icon")
			if s then s.noSweeps = true; AddText(s, rawget(f, "text")) end
		end
	end
end

local function RaidCooldowns()
	local frame = Named("ShamanPowerCallerButtons")
	if not frame then return end
	for _, name in ipairs(CALLER_BUTTONS) do
		local b = Named(name)
		if b and b.icon then SkinSpot(b.icon, "mod.raidcd-boxes", nil, true) end
	end
	for _, b in ipairs(rawget(frame, "mtButtons") or EMPTY) do
		if b.icon then SkinSpot(b.icon, "mod.raidcd-boxes", 3, true) end
	end
end

local function PlateFrame(f)
	local icon = type(f) == "table" and rawget(f, "icon")
	if icon then
		local s = SkinSpot(icon, "mod.plates-boxes")
		if s then s.noSweeps = true; AddText(s, rawget(f, "pulseText")) end
	end
end
-- the reminders and alerts: Tremor Reminder, Ready Reminders, Reactive Totems,
-- Expiring Alerts and the minimap's totem pins. A skin made here is painted at
-- once (these frames show up in the middle of a fight).
local REMINDER_ELEMENT = { earthshock = 1, flameshock = 2, frostshock = 3, lavaburst = 2, firenova = 2, riptide = 3 }
local function SkinNow(icon, spot, element, code)
	if not icon then return end
	local new = not skins[icon]
	local s = SkinSpot(icon, spot, element, true)
	if not s then return end
	if code and not s.code then s.code = code end
	if new and on then Paint(s) end
end
local function AlertKids(...)
	for i = 1, select("#", ...) do
		local f = select(i, ...)
		SkinNow(type(f) == "table" and rawget(f, "icon"), "mod.alerts-box")
	end
end
local function MinimapPins()
	for _, pin in pairs(SP.minimapTotemPins or EMPTY) do
		SkinNow(type(pin) == "table" and rawget(pin, "icon"), "mod.minimap-boxes")
	end
end
local function Reminders()
	local tr = Named("ShamanPowerTremorReminderFrame")
	if tr then SkinNow(rawget(tr, "icon"), "mod.tremor-box", 1) end
	for key, f in pairs(SP.readyReminderFrames or EMPTY) do
		if type(f) == "table" then
			local entry = rawget(f, "entry")
			SkinNow(rawget(f, "icon"), "mod.readyreminders-boxes", REMINDER_ELEMENT[key], entry and CodeFromName(entry.name))
		end
	end
	for _, f in pairs(SP.reactiveFrames or EMPTY) do
		if type(f) == "table" then SkinNow(rawget(f, "icon"), "mod.reactive-boxes") end
	end
	local host = SP.expiringAlertsFrame
	if type(host) == "table" and host.GetChildren then AlertKids(host:GetChildren()) end
	MinimapPins()
end

local function Plates()
	for _, f in ipairs(SP.totemPlateCache or EMPTY) do PlateFrame(f) end
	if C_NamePlate and C_NamePlate.GetNamePlates then
		local ok, plates = pcall(C_NamePlate.GetNamePlates)
		if ok and type(plates) == "table" then
			for _, np in ipairs(plates) do
				if not Forbidden(np) then PlateFrame(rawget(np, "totemPlateFrame")) end
			end
		end
	end
	local demo = Named("ShamanPowerTotemPlatesDemo")
	if demo then
		for i = 1, select("#", demo:GetChildren()) do
			local np = select(i, demo:GetChildren())
			PlateFrame(np and rawget(np, "totemPlateFrame"))
		end
	end
end

-- ---------------------------------------------------------------------------
-- Previews: the settings window's mocks, the setup tour, the Themes page's
-- cards. The same skin on the mock's icons, sized from the mock icon exactly as
-- on the real bar (letters at the same share of the box).
-- ---------------------------------------------------------------------------
local previewRoots = setmetatable({}, { __mode = "k" })   -- root -> { family, spot, force, list }
local FAMILY_SPOT = {
	totembar = "tb.boxes", grid = "st.boxes-grid", cooldownbar = "cd.boxes", loadout = "lo.bar",
	coverage = "mod.coverage-boxes", range = "mod.range-boxes", raidcd = "mod.raidcd-boxes",
	popouts = "mod.popouts-boxes", estracker = "mod.estracker-box", plates = "mod.plates-boxes",
	shieldcharges = "mod.shieldcharges-icon", compact = "st.boxes-compact",
}
local WALK = { Frame = true, Button = true, CheckButton = true, StatusBar = true }

-- the spot of a preview icon: the root's spot, else its family refined by what
-- the icon shows (a shield on the cooldown bar mock is the shield button...)
local function PreviewSpot(rec, family, icon)
	if rec.spot then return rec.spot end
	local spot = FAMILY_SPOT[family] or "tb.boxes"
	if family == "cooldownbar" then
		BuildCodes()
		local file = FileOf(icon)
		local info = file ~= SECRET and file and byFile[file]
		if info then
			if info[2] == "shield" then return "cd.shield-box" end
			if info[1] == "TC" then return "cd.recall" end
			if info[2] == "element" and SP.WeaponIcons then
				for _, tex in pairs(SP.WeaponIcons) do
					if byFile[tex] == info then return "cd.imbue-boxes" end
				end
			end
		elseif file and file ~= SECRET and classSheet[file] then
			return "cd.class-icons"
		end
	end
	return spot
end

local function PreviewSkin(rec, host, icon, spot, extra)
	if not IsTexture(icon) then return nil end
	local s = skins[icon]
	if not s then
		if Forbidden(host) then return nil end
		BuildCodes()
		s = MakeSkin(icon:GetParent() or host, icon)
		s.kind, s.spot, s.preview, s.noSweeps = "spot", spot, true, true
		rec.list[#rec.list + 1] = s
	end
	s.force = rec.force
	if extra then extra(s) end
	return s
end

-- the loadout mock's k-th flyout button shows the k-th loadout that is not the
-- active one, as the live flyout does (nil: a sample the bar would not show)
local function LoadoutPreviewIndex(k)
	local list = rawget(_G, "ShamanPower_TotemLoadouts")
	if type(list) ~= "table" then return nil end
	local active = SP.opt and SP.opt.activeLoadout
	local n = 0
	for i = 1, #list do
		if i ~= active then
			n = n + 1
			if n == k then return i end
		end
	end
	return nil
end

-- the first ARTWORK texture of a frame (the tour's totem slot keeps its icon in a local)
local function FirstArtwork(f)
	for i = 1, select("#", f:GetRegions()) do
		local r = select(i, f:GetRegions())
		if r and IsTexture(r) and r:GetDrawLayer() == "ARTWORK" then return r end
	end
	return nil
end

local PreviewWalk
local function PreviewChildren(rec, family, depth, ...)
	for i = 1, select("#", ...) do PreviewWalk((select(i, ...)), rec, family, depth) end
end
PreviewWalk = function(f, rec, family, depth)
	if type(f) ~= "table" or depth > 8 or Forbidden(f) then return end
	local ok, kind = pcall(f.GetObjectType, f)
	if not ok or not WALK[kind] then return end
	if rawget(f, "gridMock") then family = "grid" end
	if rawget(f, "loadoutMock") then family = "loadout"; rec.loadoutN = 0 end
	-- the tour's totem slot: main button and dropped-totem overlay
	local main, over = rawget(f, "main"), rawget(f, "over")
	if type(main) == "table" and type(over) == "table" and main.GetRegions and over.GetRegions and family == "totembar" then
		local mi = rawget(main, "icon") or FirstArtwork(main)
		if mi then PreviewSkin(rec, main, mi, rec.spot or "tb.boxes", function(s) s.mockBar = true end) end
		local oi = FirstArtwork(over)
		if oi then PreviewSkin(rec, over, oi, rec.spot or "tb.overlay-boxes", function(s) s.mockBar = true end) end
	end
	local icon = rawget(f, "icon")
	if icon and IsTexture(icon) and not skins[icon] then
		local spot = PreviewSpot(rec, family, icon)
		PreviewSkin(rec, f, icon, spot, function(s)
			if rawget(f, "totemIndex") == 0 then s.forceEmpty = true end
			if family == "loadout" then
				s.loadout, s.ck = true, "brand"
				rec.loadoutN = (rec.loadoutN or 0) + 1
				if rec.loadoutN == 1 then s.loadoutAnchor = true else s.loadoutIndex = LoadoutPreviewIndex(rec.loadoutN - 1) end
			end
		end)
	end
	PreviewChildren(rec, family, depth + 1, f:GetChildren())
end

local function PreviewWanted(rec)
	return on or (rec.force and rec.force.boxed ~= nil) or false
end

local function PaintPreview(rec)
	local list = rec.list
	for i = 1, #list do list[i].kFile = false; Paint(list[i]) end
end

-- root: any frame holding mock icons (frames with an .icon texture).
-- spec (optional): a family ("totembar", "cooldownbar", "loadout", "grid",
-- "coverage", "range", "raidcd", "popouts", "estracker", "plates",
-- "shieldcharges"), a spot id ("tb.boxes"), or a table { spot =, family =,
-- boxed = true/false, showAs =, palette =, placed = } that draws the mock in a
-- given look whatever the live theme is (the Themes page's cards). Calling it
-- again for the same root re-reads spec and repaints. Nothing is made while no
-- spot is boxed and nothing is forced.
function SP:ThemeSkinPreview(root, spec)
	if type(root) ~= "table" or not root.GetObjectType then return end
	local rec = previewRoots[root]
	if not rec then
		rec = { list = {} }
		previewRoots[root] = rec
	end
	if type(spec) == "string" then
		if spec:find(".", 1, true) then rec.spot = spec else rec.family = spec end
	elseif type(spec) == "table" then
		rec.spot, rec.family = spec.spot, spec.family or rec.family
		if spec.boxed ~= nil or spec.showAs or spec.palette or spec.placed ~= nil then
			rec.force = rec.force or {}
			rec.force.boxed, rec.force.showAs, rec.force.palette, rec.force.placed = spec.boxed, spec.showAs, spec.palette, spec.placed
		else
			rec.force = nil
		end
		for i = 1, #rec.list do rec.list[i].force = rec.force end
	end
	if not PreviewWanted(rec) then
		if #rec.list > 0 then PaintPreview(rec) end   -- hides what was drawn
		return
	end
	BuildCodes()
	rec.walked = true
	PreviewWalk(root, rec, rec.family or "totembar", 0)
	PaintPreview(rec)
end

-- the setup tour's totem bar mock, once per slot per frame: _style is the
-- mock's style (the skin reads it itself), activeNow its totem is down
-- (nothing down = the dark box, as on the bar)
function SP:ThemeMockSlot(slot, _style, activeNow)
	local mIcon = slot and slot.mIcon
	if not mIcon then return end
	local s = skins[mIcon]
	if not s then
		if not on then return end   -- never on: nothing made
		local rec = previewRoots[slot] or { list = {} }
		previewRoots[slot] = rec
		BuildCodes()
		s = PreviewSkin(rec, slot.main, mIcon, "tb.boxes", function(x) x.mockBar = true end)
		if not s then return end
	end
	local placed = activeNow and true or false
	if s.placed ~= placed then s.placed = placed; s.kFile = false end
	Paint(s)
end

-- the settings window's live preview, as it is mounted now
local function ConfigPane()
	local cfg = Named("ShamanPowerConfigUIFrame")
	local pane = cfg and rawget(cfg, "preview")
	local host = pane and rawget(pane, "mockHost")
	if not (host and host:IsVisible()) then return end
	local family = "totembar"
	local spec = rawget(pane, "mockSpec")
	local first = spec and spec.mocks and spec.mocks[1]
	if first and first.build == "BuildCooldownBarStep" then family = "cooldownbar"
	elseif first and first.build == "BuildLoadoutBarPane" then family = "loadout" end
	SP:ThemeSkinPreview(host, family)
end

-- ---------------------------------------------------------------------------
-- Scan, repaint, "nothing down"
-- ---------------------------------------------------------------------------
local function Scan()
	if not on then return end
	BuildCodes()
	TotemBar()
	CooldownBar()
	LoadoutBar()
	PopOuts()
	Coverage()
	RangeTracker()
	ESTracker()
	ShieldCharges()
	RaidCooldowns()
	Plates()
	Reminders()
end

local RefreshPlaced
local function RepaintAll()
	for i = 1, #realList do
		local s = realList[i]
		s.kFile = false   -- a full paint
		Paint(s)
	end
	for root, rec in pairs(previewRoots) do
		if type(root) == "table" and root.IsVisible and root:IsVisible() then
			-- a mock built while nothing was boxed gets its skins now (once: a
			-- rebuilt mock is a new root, and its builder's hook skins it)
			if not rec.walked and PreviewWanted(rec) then
				rec.walked = true
				PreviewWalk(root, rec, rec.family or "totembar", 0)
			end
			PaintPreview(rec)
		end
	end
	if RefreshPlaced then RefreshPlaced() end
end

-- scans are coalesced: many hooks fire together (a bar rebuild) and one walk does
local scanQueued = false
local function ScanNow()
	scanQueued = false
	if not on then return end
	Scan()
	ConfigPane()
	RepaintAll()
end
local function QueueScan()
	if not on or scanQueued then return end
	scanQueued = true
	C_Timer.After(0.2, ScanNow)
end

-- the totem buttons: bright while the element has a totem down, the dark box
-- while not (Grid shows every totem at once: no dark boxes there)
RefreshPlaced = function()
	if not on then return end
	local grid = GridOn()
	for element = 1, 4 do
		local s = mainSkins[element]
		if s then
			local want = nil
			if not grid and SP.GetElementTotemInfo then
				local have = SP:GetElementTotemInfo(element)
				if secret(have) then want = s.placed else want = have and true or false end
			end
			if want ~= s.placed then
				s.placed = want
				s.kFile = false
				Paint(s)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- On / off: hooks are made once, the first time a spot is boxed
-- ---------------------------------------------------------------------------
local hooked, previewHooked = false, false
local function after(tbl, name, fn)
	if type(tbl) == "table" and type(tbl[name]) == "function" then hooksecurefunc(tbl, name, fn) end
end

-- the tour's and the settings window's mock builders: skin what they drew
local WIZARD_BUILDERS = {
	BuildTotemBarStep = "totembar", BuildDurationBarsStep = "totembar", BuildPartyBuffStep = "totembar",
	BuildCooldownBarStep = "cooldownbar", BuildESTrackerStep = "estracker", BuildShieldChargesStep = "shieldcharges",
	BuildCoverageStep = "coverage", BuildRaidCDStep = "raidcd", BuildRangeStep = "range", BuildTotemPlatesStep = "plates",
}
local function EnsurePreviewHooks()
	if previewHooked then return end
	local W = SP.Wizard
	local cfg = rawget(_G, "ShamanPowerConfig")
	if type(W) ~= "table" and type(cfg) ~= "table" then return end
	previewHooked = true
	if type(W) == "table" then
		for name, family in pairs(WIZARD_BUILDERS) do
			after(W, name, function(_, host)
				if on and type(host) == "table" then SP:ThemeSkinPreview(host, family) end
			end)
		end
	end
	if type(cfg) == "table" then
		after(cfg, "UpdatePreviewPane", function() if on then ConfigPane() end end)
	end
end

local Apply
local function EnsureHooks()
	if hooked then return end
	hooked = true
	-- surfaces built or rebuilt: skin what is new
	for _, name in ipairs({
		"CreateTotemButtons", "CreateTotemFlyout", "UpdateMiniTotemBar", "CreateCooldownBar", "UpdateCooldownBarLayout",
		"CreateWeaponImbueButton", "CreateShieldFlyout", "CreateWeaponImbueFlyout", "CreateEarthShieldButton",
		"CreateESActiveOverlay", "UpdateOrCreateESFlyoutButton", "CreateLoadoutBar", "UpdateLoadoutBar",
		"CreatePopOutFrame", "PopOutSingleTotem", "PopOutElementWithFlyout", "PopOutCooldownItem", "PopOutEarthShield",
		"PopOutDropAll", "ReturnPopOutToBar", "CreateCoverageFrame", "CoverageTotemCell", "CreateSPRangeFrame",
		"CreateSPRangeTotemButton", "CreateESTrackerButton", "CreateShieldChargeDisplays", "CreateCallerButtonFrame",
		"BuildCallerMTButton", "TotemPlatesDemo", "ApplyCompactStyle", "ApplyCompactButtonLayout", "SetGridStyle",
		"SetTotemBarStyle", "RefreshBlizzardTotemBar", "CreateRangeCounterText", "UpdateTotemProgressBarPositions",
	}) do
		after(SP, name, QueueScan)
	end
	-- surfaces whose icon is made lazily while painting: a narrow look, no walk
	after(SP, "UpdateShieldChargeDisplays", function() if on then ShieldCharges() end end)
	after(SP, "UpdateActiveTotemOverlays", function()
		if not on then return end
		for element = 1, 4 do
			local ov = SP.activeTotemOverlays and SP.activeTotemOverlays[element]
			if ov and ov.icon and not skins[ov.icon] then
				local s = SkinSpot(ov.icon, "tb.overlay-boxes", element)
				if s then Paint(s) end
			end
		end
		RefreshPlaced()
	end)
	after(SP, "OnTotemPlateUnitAdded", function(_, unit)
		if not on or not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
		local ok, np = pcall(C_NamePlate.GetNamePlateForUnit, unit)
		if ok and type(np) == "table" and not Forbidden(np) then
			local f = rawget(np, "totemPlateFrame")
			PlateFrame(f)
			local s = f and rawget(f, "icon") and skins[f.icon]
			if s then s.kFile = false; Paint(s) end
		end
	end)
	-- reminders and alerts made mid-fight: skinned and painted at once
	for _, name in ipairs({
		"CreateReadyReminderFrame", "TremorReminderShow", "TremorReminderTest", "TremorDemo",
		"CreateReactiveTotemFrame", "CreateAllReactiveFrames", "ProcessAlertQueue",
	}) do
		after(SP, name, function() if on then Reminders() end end)
	end
	-- the unassigned slot's faded art (WoW: Forever) comes and goes without the icon
	after(SP, "ShowEmptySlotArt", function(_, element)
		local s = on and mainSkins[element]
		if s then s.kFile = false; Paint(s) end
	end)
	-- the Appearance palette feeds every colour that follows today's palette
	after(SP, "ApplyElementColors", function() if on then RepaintAll() end end)
	-- the engine's sweep bar (WoW: Forever) gets its look back on every feed
	if IS_MAINLINE then
		local function fed(_, btn)
			local s = on and btn and rawget(btn, "icon") and skins[btn.icon]
			if s then EngineSweep(s, true) end
		end
		after(SP, "FeedEngineCooldown", fed)
		after(SP, "FeedEngineBarCooldown", fed)
	end
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_TOTEM_UPDATE")
	ev:RegisterEvent("PLAYER_REGEN_ENABLED")
	ev:RegisterEvent("GROUP_ROSTER_UPDATE")
	ev:RegisterEvent("PLAYER_ENTERING_WORLD")
	ev:RegisterEvent("ADDON_LOADED")
	ev:SetScript("OnEvent", function(_, event, name)
		if event == "ADDON_LOADED" then
			if name == "ShamanPower_Config" then EnsurePreviewHooks() end
			return
		end
		if not on then return end
		if event == "PLAYER_TOTEM_UPDATE" then RefreshPlaced(); MinimapPins()   -- (the minimap builds its pins on a first drop)
		elseif event == "PLAYER_REGEN_ENABLED" then
			if pendingCombat then pendingCombat = false; QueueScan() end
		else QueueScan() end
	end)
	EnsurePreviewHooks()
end

local firstOn = true
Apply = function()
	local was = on
	on = AnyOn()
	if not (on or was) then
		-- nothing boxed and nothing was: only a forced preview may need a repaint
		for root, rec in pairs(previewRoots) do
			if rec.force and type(root) == "table" and root.IsVisible and root:IsVisible() then PaintPreview(rec) end
		end
		return
	end
	if on then
		EnsureHooks()
		if not was then
			-- turned on: look for every icon (a theme change never makes new ones,
			-- and a colour picker drag changes the theme every frame)
			Scan()
			ConfigPane()
		end
		if firstOn then
			firstOn = false
			C_Timer.After(2, QueueScan)   -- windows the modules build a moment later
		end
	end
	RepaintAll()
end

-- SP:ThemeBoxesRefresh(): look for new icons and repaint every box
function SP:ThemeBoxesRefresh()
	Apply()
	if on then Scan(); RepaintAll() end
end

if SP.OnThemeChanged then SP:OnThemeChanged(function() Apply() end) end

-- ---------------------------------------------------------------------------
-- The Effects' Shake / Pop / Thud move the icon texture; the box covers it, so
-- it moves with it. ShamanPowerCues.lua and ShamanPowerThemeEffects.lua call
-- this with the same arguments.
-- ---------------------------------------------------------------------------
local function motionGroup(s, key, region, n, kind)
	local groups = s[key]
	if not groups then groups = {}; s[key] = groups end
	local g = groups[region]
	if not g then
		g = region:CreateAnimationGroup()
		for i = 1, n do
			local a = g:CreateAnimation(kind)
			a:SetOrder(i)
			g[i] = a
		end
		groups[region] = g
	end
	return g
end
function SP.ThemeIconMotion(icon, style, h, extra)
	if icon == SP then icon, style, h = style, h, extra end   -- called as SP:ThemeIconMotion(...)
	local s = icon and skins[icon]
	if not (s and s.visible) then return end
	h = h or icon:GetHeight() or 26
	local regions = s.regions
	for i = 1, #regions do
		local region = regions[i]
		if style == "shake" then
			local g = motionGroup(s, "mShake", region, 4, "Translation")
			local d = max(2, h * 0.09)
			g[1]:SetOffset(d, 0); g[1]:SetDuration(0.04)
			g[2]:SetOffset(-2 * d, 0); g[2]:SetDuration(0.07)
			g[3]:SetOffset(2 * d, 0); g[3]:SetDuration(0.07)
			g[4]:SetOffset(-d, 0); g[4]:SetDuration(0.05)
			g:Stop(); g:Play()
		elseif style == "thud" then
			local g = motionGroup(s, "mThud", region, 2, "Translation")
			local d = max(2, h * 0.08)
			g[1]:SetOffset(0, -d); g[1]:SetDuration(0.06)
			g[2]:SetOffset(0, d); g[2]:SetDuration(0.16)
			g:Stop(); g:Play()
		elseif style == "pop" then
			local g = motionGroup(s, "mPop", region, 2, "Scale")
			if g[1].SetScaleFrom then
				g[1]:SetScaleFrom(1, 1); g[1]:SetScaleTo(1.3, 1.3)
				g[2]:SetScaleFrom(1.3, 1.3); g[2]:SetScaleTo(1, 1)
			else
				g[1]:SetScale(1.3, 1.3); g[2]:SetScale(1 / 1.3, 1 / 1.3)
			end
			g[1]:SetDuration(0.12); g[1]:SetSmoothing("OUT")
			g[2]:SetDuration(0.25); g[2]:SetSmoothing("IN_OUT")
			g:Stop(); g:Play()
		end
	end
end
