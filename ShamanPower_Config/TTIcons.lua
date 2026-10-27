-- ShamanPower_Config :: TTIcons
-- Target Tracker's Spells row (D43 / D45, 2026-10-02): Flame Shock, Frost Shock and
-- Stormstrike (your debuffs on your target) and, a step apart, Purge (your target's
-- Magic buffs), as 36 px spell icons on thin plates in Ready Reminders' look
-- (ReadyIcons.lua). Not learned: dark; hidden: gray and dim; a small accentHi corner
-- marks a spell with settings of its own. Left-click: show or hide it. Right-click:
-- its settings in ns.ContextMenu, grouped (When and Look; each debuff's Missing
-- Warning and Every Nameplate; Purge's Show On, Long Buffs, Watch Bosses and Every
-- Nameplate: v2, the same options for every spell), with sliders in the rows (D41 A),
-- Copy / Paste / Copy To, Hide and Reset.
--
-- Every value is read and written through the module's SP:TT_* functions
-- (ShamanPower_TargetTracker loads after this file, or not at all): without them the
-- row draws nothing and the page says the module is not loaded.
local _, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not (Core and SP) then return end

local floor, max, ceil = math.floor, math.max, math.ceil

local ICON         = 36    -- the spell icon
local PLATE        = 40    -- its plate, 2 px round it
local PITCH        = 44    -- plate to plate: 4 px apart
local PURGE_GAP    = 14    -- Purge a step apart: it reads your target's buffs, not your debuffs
local PAD_X        = 12    -- the settings rows' inner padding (plus a card's inset: Widgets.CARD_INSET)
local PAD_TOP      = 10
local CAPTION_GAP  = 10
local PAD_BOTTOM   = 12
local ROW_GAP      = 6     -- the settings rows' gap (Widgets.ROW_GAP)
local CORNER       = 11
local HIDDEN_SHADE = 0.5   -- a hidden spell: gray and half as bright
local NOT_LEARNED_SHADE = 0.3   -- a spell not learned yet: gray and dark
-- (the words that say what to do in the settings' blue, so a player sees them first)
local CAPTION = "|cff3FA9F5CLICK|r a spell to show or hide it. |cff3FA9F5RIGHT-CLICK|r it to set it up: when and where it shows, how it"
	.. " looks, and more. |cff3FA9F5Dark|r: you haven't learned it yet (set it up now, it shows once you learn it)."

local Row = { buttons = {}, list = {}, byKey = {} }
ns.CustomRows.ttIcons = Row

-- ---------------------------------------------------------------------------
-- The module
-- ---------------------------------------------------------------------------
local function Loaded() return type(SP.TT_Get) == "function" and type(SP.TT_SPELLS) == "table" end

-- one of the module's functions, if it has it (nil when it does not)
local function TT(name, ...)
	local fn = SP[name]
	if type(fn) ~= "function" then return nil end
	return fn(SP, ...)
end

-- what a value shows as when the module answers nil (its own defaults are the truth)
local FALLBACK = {
	shown = true, show = "always", timeLeft = true, sweep = "radial", charges = true, missing = false,
	everyPlate = false, showOn = "screen", glow = true, buffPicture = true, skipLong = true, longerThan = 2,
	watchBosses = true, missLook = "edge", border = "thin",
}
local function Get(key, opt)
	local v = TT("TT_Get", key, opt)
	if v ~= nil then return v end
	if opt == "size" then
		if key == "purge" then return 64 end
		return 36
	end
	return FALLBACK[opt]
end
-- every spell starts everywhere
local function Where(key, kind)
	local v = TT("TT_GetWhere", key, kind)
	if v == nil then return true end
	return v and true or false
end
local function Shown(key) return Get(key, "shown") ~= false end
local function Known(key)
	if type(SP.TT_Known) ~= "function" then return true end
	return SP:TT_Known(key) and true or false
end
local function HasOwn(key) return TT("TT_HasOwn", key) and true or false end

local function SpellOf(key)
	for _, s in ipairs(SP.TT_SPELLS) do
		if s.key == key then return s end
	end
	return nil
end
local function Texture(s)
	if s.icon then return s.icon end
	local id = s.ids and s.ids[1]
	if id then
		if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
		if GetSpellTexture then return GetSpellTexture(id) end
	end
	return 134400   -- the question mark
end

-- one watcher for both of the page's rows (this one and TTRules.lua's): the module may
-- keep only one
local WATCH_ROWS = { "ttIcons", "ttRules" }
function ns.TargetTrackerWatch()
	if ns.ttWatching or type(SP.TT_Watch) ~= "function" then return end
	ns.ttWatching = true
	SP:TT_Watch(function()
		for _, k in ipairs(WATCH_ROWS) do
			local r = ns.CustomRows[k]
			if r and r.OnSettingsChanged then r:OnSettingsChanged() end
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Picture hints (3.0.9, Icon Screens): `pic` on a menu row is the picture the icon's own
-- screen draws for that choice (IconScreen.lua), `words` the line after a card's title.
-- Data only: the right-click menu and the Old Settings Look ignore them. The ones every
-- spell shares, made once; a spell's own (its edge color, the shock it swaps to) are
-- made with its menu.
-- ---------------------------------------------------------------------------
local PIC = {
	plain   = { kind = "plain" },
	none    = { kind = "none" },
	gray    = { kind = "gray" },
	size    = { kind = "size" },
	count   = { kind = "count" },
	sweep   = { kind = "sweep" },
	ticking = { kind = "number", text = "8" },          -- a debuff's time left on the icon: Show Time Left
	charges = { kind = "number", text = "2" },          -- Stormstrike's charges
	-- Icon Edge: Thin Black (1 px), Thick Black (3 px), Dotted (1 px dashes), as the tracker draws them
	black       = { kind = "edge", color = { 0, 0, 0 }, thick = 1 },
	thickBlack  = { kind = "edge", color = { 0, 0, 0 }, thick = 3 },
	dottedBlack = { kind = "edge", color = { 0, 0, 0 }, thick = 1, dotted = true },
	-- Purge's Show The Buff's Picture: the settings preview's pretend Magic buff
	buffPicture = { kind = "swap", icon = "Interface\\Icons\\Spell_Shadow_RagingScream" },
	-- Next Shock: the shock Flame Shock's icon swaps to (the module's own icons)
	SHOCK = { earth = "Interface\\Icons\\Spell_Nature_EarthShock", frost = "Interface\\Icons\\Spell_Frost_FrostShock" },
	ELEMENT = { fs = "fire", frs = "water", ss = "air" },
}
-- WoW's own colors, as the module reads them: its red (missing), its gold (Purge's glow, the cast
-- edge) and Magic's blue
do
	local function RGB(c, r, g, b)
		if type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b end
		return r, g, b
	end
	local red  = { RGB(_G.RED_FONT_COLOR, 1, 0.125, 0.125) }
	local gold = { RGB(_G.NORMAL_FONT_COLOR, 1, 0.82, 0) }
	PIC.magic    = { RGB(_G.DebuffTypeColor and _G.DebuffTypeColor.Magic, 0.2, 0.6, 1) }
	PIC.redEdge  = { kind = "edge", color = red, thick = 2 }           -- Red Edge (the module's 2 px ring)
	PIC.redDots  = { kind = "edge", color = red, thick = 2, dotted = true }   -- Dotted Red Edge
	PIC.redGlow  = { kind = "glow", color = red, shape = "default" }
	PIC.redTint  = { kind = "tint", color = red }
	PIC.faded    = { kind = "faded", alpha = 0.45 }                    -- Just Faded (the module's 0.45)
	PIC.goldEdge = { kind = "edge", color = gold, thick = 2, dotted = true }  -- Gold Dotted Edge (its gold dashes)
	PIC.goldGlow = { kind = "glow", color = gold, shape = "default" }  -- Purge's Glow
end
-- Icon Edge's Spell Color: the element's brand color, Purge's Magic blue (as the module draws it)
function PIC.SpellEdge(key)
	local r, g, b = 1, 1, 1
	if key == "purge" then
		r, g, b = PIC.magic[1], PIC.magic[2], PIC.magic[3]
	elseif PIC.ELEMENT[key] and SP.BrandElementRGB then
		r, g, b = SP:BrandElementRGB(PIC.ELEMENT[key])
	end
	return { kind = "edge", color = { r, g, b }, thick = 1 }
end
-- Next Shock: Flame Shock's icon with the other shock in its place
function PIC.Shock(which)
	return { kind = "swap", icon = PIC.SHOCK[which] or PIC.SHOCK.earth }
end

-- ---------------------------------------------------------------------------
-- Labels
-- ---------------------------------------------------------------------------
-- (the saved values stay the same: "always" is in and out of combat; the places below can still turn it off)
local SHOW_CHOICES = { { "always", "Always", pic = PIC.plain },
	{ "combat", "Only In Combat", pic = PIC.none }, { "nocombat", "Only Out Of Combat", pic = PIC.none } }
local WHERE_CHOICES = {
	{ "world", "Open World" }, { "dungeon", "Dungeons" }, { "raid", "Raids" }, { "bg", "Battlegrounds" }, { "arena", "Arenas" },
}
local WHERE_TIPS = { world = "Questing, duels and world PvP." }
local SWEEP_CHOICES = { { "radial", "Clock Sweep", pic = PIC.sweep },
	{ "greys", "Gray Fills In", pic = PIC.gray }, { "fills", "Color Fills In", pic = PIC.none },
	{ "none", "None", pic = PIC.plain } }
local DIRECTION_CHOICES = { { "top", "From The Top", pic = PIC.none }, { "bottom", "From The Bottom", pic = PIC.none } }
local SHOWON_CHOICES = { { "screen", "Anywhere on Screen", pic = PIC.none },
	{ "plate", "Your Target's Nameplate", pic = PIC.none }, { "frame", "Under The Target Frame", pic = PIC.none } }
-- (pictures: a slashed, outlined or pulsing edge can't be drawn yet)
local MISS_CHOICES = { { "edge", "Red Border", pic = PIC.redEdge }, { "dotted", "Dotted Red Border", pic = PIC.redDots },
	{ "faded", "Faded", pic = PIC.faded }, { "glow", "Red Glow", pic = PIC.redGlow },
	{ "tint", "Red Tint", pic = PIC.redTint }, { "slash", "Red Slash", pic = PIC.none },
	{ "outline", "Empty Outline", pic = PIC.none }, { "pulse", "Pulsing Border", pic = PIC.none } }
-- Next Shock's cast-it look (Flame Shock's menu): WoW's gold dotted edge, or one of the Missing looks
local CAST_CHOICES = { { "gold", "Gold Dotted Edge", pic = PIC.goldEdge } }
for _, c in ipairs(MISS_CHOICES) do CAST_CHOICES[#CAST_CHOICES + 1] = c end
-- (Spell Color has no picture of its own: the row's fallback is the spell's own color, PIC.SpellEdge)
local EDGE_CHOICES = { { "thin", "Thin Black", pic = PIC.black }, { "none", "None", pic = PIC.plain },
	{ "thick", "Thick Black", pic = PIC.thickBlack }, { "dotted", "Dotted", pic = PIC.dottedBlack }, { "spell", "Spell Color" } }

local function OnOff(v) if v then return "On" end return "Off" end
local function LabelOf(list, v)
	for _, c in ipairs(list) do if c[1] == v then return c[2] end end
	return list[1][2]
end

-- ---------------------------------------------------------------------------
-- The icons
-- ---------------------------------------------------------------------------
local function TooltipBody(s)
	if not Known(s.key) then return "You haven't learned this yet. You can still set it up." end
	if HasOwn(s.key) then return "It has settings of its own (right-click to see them)." end
	return "It uses the default settings (right-click to change them)."
end

local function PaintButton(b)
	local s = b.spell
	if not s then return end
	local on, learned = Shown(s.key), Known(s.key)
	local shade = 1
	if not learned then shade = NOT_LEARNED_SHADE elseif not on then shade = HIDDEN_SHADE end
	b.icon:SetTexture(Texture(s))
	b.icon:SetDesaturated(not (on and learned))
	b.icon:SetVertexColor(shade, shade, shade)
	b.corner:SetShown(HasOwn(s.key))
	b.openEdge:SetShown(Row.openKey == s.key)
	Core:AttachTooltip(b, s.name, TooltipBody(s), "Click: show or hide it\nRight-click: its settings")
end

local function ButtonClick(b, button)
	local s = b.spell
	if not s then return end
	if button == "RightButton" then
		Row:OpenMenu(s.key)
		return
	end
	-- the icon screens (IconScreen.lua, held for 3.1.0 and not loaded until then): the spell's own screen
	if ns.IconScreen and ns.IconScreen:Wants(Row) then
		ns.IconScreen:Open(Row, s.key)
		return
	end
	TT("TT_Set", s.key, "shown", not Shown(s.key))
	Row:Changed(false)
end

local function NewButton(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(PLATE, PLATE)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local plate = SP.Brand and SP.Brand.plate or { 5 / 255, 7 / 255, 10 / 255 }   -- #05070A, the totem boxes' plate
	b.plate = b:CreateTexture(nil, "BACKGROUND")
	b.plate:SetAllPoints(b)
	b.plate:SetColorTexture(plate[1], plate[2], plate[3], 1)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(ICON, ICON)
	b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- hover: the plate's edge turns accent, as a control's border does
	b.hoverEdge = CreateFrame("Frame", nil, b)
	b.hoverEdge:SetAllPoints(b)
	b.hoverEdge:SetFrameLevel(b:GetFrameLevel() + 1)
	Core:MakeBorder(b.hoverEdge, "accent", 1)
	b.hoverEdge:Hide()
	-- its menu is open: a 2 px accentHi outline
	b.openEdge = CreateFrame("Frame", nil, b)
	b.openEdge:SetAllPoints(b)
	b.openEdge:SetFrameLevel(b:GetFrameLevel() + 2)
	Core:MakeBorder(b.openEdge, "accentHi", 2)
	b.openEdge:Hide()
	-- settings of its own: an accentHi square in the plate's top right corner, edged in plate black
	b.corner = CreateFrame("Frame", nil, b)
	b.corner:SetSize(CORNER, CORNER)
	b.corner:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
	b.corner:SetFrameLevel(b:GetFrameLevel() + 3)
	local edge = b.corner:CreateTexture(nil, "ARTWORK")
	edge:SetAllPoints(b.corner)
	edge:SetColorTexture(plate[1], plate[2], plate[3], 1)
	local fill = b.corner:CreateTexture(nil, "OVERLAY")
	fill:SetPoint("TOPLEFT", b.corner, "TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMRIGHT", b.corner, "BOTTOMRIGHT", -1, 1)
	fill:SetColorTexture(Core:Color("accentHi"))
	b.corner:Hide()
	b:SetScript("OnClick", ButtonClick)
	b:SetScript("OnEnter", function(self) self.hoverEdge:Show() end)
	b:SetScript("OnLeave", function(self) self.hoverEdge:Hide() end)
	return b
end

-- the spells this game version has, in the module's order (learned or not)
local function Usable(out)
	wipe(out)
	for _, s in ipairs(SP.TT_SPELLS) do
		if TT("TT_Usable", s.key) ~= false then out[#out + 1] = s end
	end
	return out
end

local scratch = {}
function Row:ListChanged()
	Usable(scratch)
	if #scratch ~= #self.list then return true end
	for i = 1, #scratch do if scratch[i] ~= self.list[i] then return true end end
	return false
end

function Row:Repaint()
	for _, b in ipairs(self.buttons) do
		if b:IsShown() then PaintButton(b) end
	end
end

-- what the page's own rows show or hide by (ShamanPowerOptions.lua): where your debuffs
-- show and each one's Every Nameplate (the Nameplates section), Purge's Show On (Move Purge)
local LAYOUT_DEBUFFS = { "fs", "frs", "ss" }
local function LayoutKey()
	local k = tostring(TT("TT_GetPage", "showOn")) .. "|" .. tostring(Get("purge", "showOn"))
	for _, key in ipairs(LAYOUT_DEBUFFS) do k = k .. "|" .. tostring(Get(key, "everyPlate")) end
	return k
end

-- a setting changed here: the icons repainted now, then the page (the preview).
-- keepMenu: the menu stays open, even if the page lays itself out again (it opens
-- again on the same rows)
function Row:Changed(keepMenu)
	self:Repaint()
	local fn = self.onChanged
	if not fn then return end
	self.writing = keepMenu and true or false
	local ok, err = pcall(fn)
	self.writing = false
	if not ok then geterrorhandler()(err) end
	self.layoutKey = LayoutKey()   -- (the page has seen it)
end

-- a setting changed anywhere (Unlock UI, an import, a rule's list, a test): SP:TT_Watch
function Row:OnSettingsChanged()
	if not (self.frame and self.frame:IsVisible()) then return end
	if self:ListChanged() then   -- a spell new to the list: the page lays itself out again
		local cfg = _G.ShamanPowerConfig
		if cfg and cfg.RefreshCurrent then cfg:RefreshCurrent() end
		return
	end
	self:Repaint()
	local k = LayoutKey()
	if k ~= self.layoutKey then
		-- changed outside the page (e.g. Every Nameplate turned on by a test): the page shows
		-- or hides its rows for it (it is laid out again only if they change; an open menu
		-- opens again on the same rows)
		self.layoutKey = k
		self:Changed(true)
	end
	if self.openKey and ns.ContextMenu:IsOpen() then ns.ContextMenu:Refresh() end
end

-- ---------------------------------------------------------------------------
-- The menu (D43): every setting of the spell, grouped
-- ---------------------------------------------------------------------------
-- a choice: saved as the spell's own, the menu stays open and is drawn again
local function Set(key, opt, value)
	TT("TT_Set", key, opt, value)
	Row:Changed(true)
	return true
end
-- a slider's value: only saved (the icons and the open menu are drawn again by the
-- module's watcher, the preview follows); never a redraw of the page under a drag
local function SliderSet(key, opt, value)
	TT("TT_Set", key, opt, value)
	Row:Repaint()
	local cfg = _G.ShamanPowerConfig
	if cfg and cfg.PreviewChanged then cfg:PreviewChanged() end
end

-- pic: the picture a choice without one of its own gets
local function ChoiceRow(key, text, opt, list, pic)
	return {
		text = text,
		pic = pic,
		value = function() return LabelOf(list, Get(key, opt)), false end,
		sub = function()
			local cur = Get(key, opt)
			local items = {}
			for _, c in ipairs(list) do
				local v = c[1]
				items[#items + 1] = { text = c[2], selected = cur == v, pic = c.pic,
					onClick = function() return Set(key, opt, v) end }
			end
			return items
		end,
	}
end
-- pic: the picture when it's On
local function OnOffRow(key, text, opt, pic)
	return {
		text = text,
		pic = pic,
		value = function() return OnOff(Get(key, opt)), false end,
		sub = function()
			local on = Get(key, opt) and true or false
			return {
				{ text = "On", selected = on, onClick = function() return Set(key, opt, true) end },
				{ text = "Off", selected = not on, onClick = function() return Set(key, opt, false) end },
			}
		end,
	}
end
local function SliderRow(key, text, opt, lo, hi, step, format, pic)
	return {
		text = text,
		pic = pic,
		slider = {
			min = lo, max = hi, step = step,
			get = function() return tonumber(Get(key, opt)) or lo end,
			set = function(v) SliderSet(key, opt, v) end,
			format = format,
		},
	}
end
-- where it shows: one place on or off
local function WhereRow(key, text, kind)
	local function pick(v)
		TT("TT_SetWhere", key, kind, v)
		Row:Changed(true)
		return true
	end
	return {
		text = text,
		tip = WHERE_TIPS[kind],
		pic = PIC.plain,   -- on: it shows there as usual
		value = function() return OnOff(Where(key, kind)), false end,
		sub = function()
			local on = Where(key, kind)
			return {
				{ text = "On", selected = on, onClick = function() return pick(true) end },
				{ text = "Off", selected = not on, onClick = function() return pick(false) end },
			}
		end,
	}
end
-- the last line of a group: these settings of this spell on every other spell
local function CopyGroupRow(key, group, which)
	return { text = "Copy " .. group .. " To All Spells", onClick = function()
		TT("TT_CopyGroupToAll", key, which)
		Row:Changed(true)
		return true
	end }
end
-- words: the line after the card's title on the icon's screen
local function Group(text, rows, words)
	return { text = text, words = words, sub = function() return rows() end }
end

-- the places it shows in, one switch each; the copy row takes Show (in or out of combat) along
local function PlaceRows(key)
	local t = {}
	for _, w in ipairs(WHERE_CHOICES) do t[#t + 1] = WhereRow(key, w[2], w[1]) end
	t[#t + 1] = { separator = true }
	t[#t + 1] = { text = "Copy Show Settings To All Spells", onClick = function()
		TT("TT_CopyGroupToAll", key, "when")
		Row:Changed(true)
		return true
	end }
	return t
end

local function AppearanceRows(key)
	local t
	if key == "purge" then
		t = {
			SliderRow(key, "Size", "size", 32, 128, 1, nil, PIC.size),
			OnOffRow(key, "Show Buff Icon", "buffPicture", PIC.buffPicture),
		}
		t[2].tip = "Show the buff you can Purge. Turn off to use the Purge icon."
		local edge = ChoiceRow(key, "Border", "border", EDGE_CHOICES, PIC.SpellEdge(key))
		edge.tip = "The border around Purge's icon. Spell Color: WoW's Magic blue."
		t[#t + 1] = edge
	else
		t = {
			SliderRow(key, "Size", "size", 16, 64, 1, nil, PIC.size),
			OnOffRow(key, "Show Time Left", "timeLeft", PIC.ticking),
			ChoiceRow(key, "Sweep", "sweep", SWEEP_CHOICES, PIC.plain),
		}
		t[2].tip = "The seconds your debuff has left, on its icon."
		t[3].tip = "How the icon counts down. Clock Sweep: the clock sweep. Grays Out: gray covers the icon as the time runs"
			.. " out. Fills Back In: the icon starts gray and its color comes back as the time runs out."
		local sweep = Get(key, "sweep")
		if sweep == "greys" or sweep == "fills" then
			local direction = ChoiceRow(key, "Sweep Direction", "sweepDirection", DIRECTION_CHOICES, PIC.none)
			direction.tip = "Where the gray starts for Grays Out, or the color starts for Fills Back In."
			t[#t + 1] = direction
		end
		if key == "ss" then t[#t + 1] = OnOffRow(key, "Show Charges", "charges", PIC.charges) end
		local edge = ChoiceRow(key, "Border", "border", EDGE_CHOICES, PIC.SpellEdge(key))
		edge.tip = "The border around this spell's icon. Spell Color: the spell's element color."
		t[#t + 1] = edge
	end
	t[#t + 1] = { separator = true }
	t[#t + 1] = CopyGroupRow(key, "Appearance", "look")   -- (the module's "look" group: its glow and missing look too)
	return t
end

-- When It's Missing: the warning while your debuff is not on your target, and its look
local function MissingRows(key)
	local name = (SpellOf(key) or {}).name or "it"
	local missing = OnOffRow(key, "Warn When Debuff Is Missing", "missing", PIC.gray)
	missing.tip = "While you're targeting an enemy without your " .. name .. " on it, a gray " .. name
		.. " with a red edge shows where yours would be, so you know to cast it again."
	local miss = ChoiceRow(key, "Warning Style", "missLook", MISS_CHOICES, PIC.gray)
	miss.tip = "How the gray warning looks while your " .. name .. " isn't on your target."
	if not Get(key, "missing") then
		miss.disabled = true
		miss.tip = "Turn on Warn When It's Missing to use this. " .. miss.tip
	end
	return { missing, miss }
end

-- Next Shock (Flame Shock's menu): its settings live under Target Tracker's "ns"
local function SpellName(id, fallback)
	local n = SPCompat and SPCompat.SpellLabel and SPCompat.SpellLabel(id, fallback)
	return (type(n) == "string" and n ~= "") and n or fallback
end
local function NextShockRows()
	local t = {}
	local on = OnOffRow("ns", "Show Next Shock", "on", PIC.Shock(Get("ns", "whenOn")))
	on.tip = "While your Flame Shock is on an enemy, its Flame Shock icon shows " .. SpellName(8042, "Earth Shock")
		.. " (or " .. SpellName(8056, "Frost Shock") .. ") instead, with Flame Shock's time left, so you know which"
		.. " shock to press. Each enemy goes by its own Flame Shock: your target's icon, and with Show On Every"
		.. " Enemy's Nameplate, every enemy's. Without your Flame Shock, Warn When It's Missing shows Flame Shock."
	t[#t + 1] = on
	if Get("ns", "on") then
		local shock = ChoiceRow("ns", "While Flame Shock Is Active", "whenOn",
			{ { "earth", SpellName(8042, "Earth Shock"), pic = PIC.Shock("earth") },
				{ "frost", SpellName(8056, "Frost Shock"), pic = PIC.Shock("frost") } }, PIC.Shock("earth"))
		shock.tip = "The shock the icon shows while your Flame Shock is on that enemy."
		t[#t + 1] = shock
		local again = SliderRow("ns", "Show Flame Shock Below (Seconds)", "refresh", 0, 6, 1,
			function(v)
				v = floor((v or 0) + 0.5)
				if v == 0 then return "Never" end
				return v .. " s left"
			end, PIC.count)
		again.tip = "When your Flame Shock on that enemy has this many seconds left, the icon shows Flame Shock again,"
			.. " in the look below, so you can cast it before it runs out. Never: it keeps the other shock until it ends."
		t[#t + 1] = again
		local look = ChoiceRow("ns", "Recast Warning Style", "castLook", CAST_CHOICES, PIC.plain)
		look.tip = "How Flame Shock looks in its last seconds."
		t[#t + 1] = look
	end
	return t
end

-- Purge: skip a buff that lasts longer than this (Longer Than only while it skips); on the
-- first level of the menu, so it's plain to see when it's on
local function LongRows(key, t)
	local skip = OnOffRow(key, "Ignore Long Buffs", "skipLong", PIC.none)
	skip.tip = "Purge doesn't light up for buffs that last longer than the limit below, like Arcane Intellect (30 minutes)."
		.. " Turn it off to light up for every buff you can remove."
	t[#t + 1] = skip
	if Get(key, "skipLong") then
		local long = SliderRow(key, "Ignore Buffs Longer Than", "longerThan", 1, 10, 1,
			function(v) return string.format("%d min", floor((v or 0) + 0.5)) end)
		long.tip = "A buff that lasts longer than this counts as long."
		t[#t + 1] = long
	end
end

local function CopyItems(key)
	local items = {}
	for _, s in ipairs(Row.list) do
		if s.key ~= key then
			local to = s.key
			items[#items + 1] = { text = s.name, icon = Texture(s),
				onClick = function() TT("TT_CopyTo", key, to); Row:Changed(false) end }
		end
	end
	if #items > 0 then
		items[#items + 1] = { separator = true }
		items[#items + 1] = { text = "All Spells", onClick = function() TT("TT_CopyTo", key, "all"); Row:Changed(false) end }
	end
	return items
end

-- every setting of the spell, in the order every icon menu shares (3.0.9): the icon itself, when
-- and where it shows, Appearance, its moments (When It's Missing; Purge: When A Buff Can Be
-- Removed), where it sits, Copy / Paste / Reset (each row's tooltip says what it does)
local function OffPlaces(key)
	local off = {}
	for _, w in ipairs(WHERE_CHOICES) do
		if not Where(key, w[1]) then off[#off + 1] = w[2] end
	end
	if #off == 0 then return nil end
	if #off == 1 then return off[1] end
	return table.concat(off, ", ", 1, #off - 1) .. " and " .. off[#off]
end
-- the spell of a key: its drawn icon's, or the list's (the Old Settings Look draws no icons)
local function SpellByKey(key)
	local b = Row.byKey[key]
	if b and b.spell then return b.spell end
	for _, s in ipairs(Row.list) do
		if s.key == key then return s end
	end
	return nil
end

local function MenuItems(key)
	local spell = SpellByKey(key)
	if not spell then return {} end
	local name = spell.name
	local items = {}
	-- the icon itself
	items[#items + 1] = { text = "Show", label = true }
	local on = Shown(key)
	items[#items + 1] = { text = on and "Hide This Icon" or "Show This Icon",
		onClick = function() TT("TT_Set", key, "shown", not on); Row:Changed(false) end }
	items[#items + 1] = { separator = true }
	-- when and where it shows
	local show = ChoiceRow(key, "Show", "show", SHOW_CHOICES, PIC.plain)
	show.tip = "Choose whether the icon appears in combat, out of combat, or both. Show In can still keep it off in a kind of place."
	items[#items + 1] = show
	local places = Group("Show In", function() return PlaceRows(key) end, "the kinds of place it shows in")
	places.tip = "Turn it on or off in each kind of place: the open world, dungeons, raids, Battlegrounds and Arenas."
	items[#items + 1] = places
	if key == "purge" then
		items[#items + 1] = { separator = true }
		items[#items + 1] = { text = "Behavior", label = true }
		LongRows(key, items)
		local bosses = OnOffRow(key, "Check Every Boss", "watchBosses", PIC.none)
		bosses.tip = "In a boss fight, Purge also lights up when any boss has a buff you can remove, not only your target."
		if not (Where(key, "raid") or Where(key, "dungeon")) then
			bosses.tip = bosses.tip .. " Purge is off in Raids and Dungeons (Show In), so it can't light up for bosses there."
		end
		items[#items + 1] = bosses
	elseif key == "fs" then
		items[#items + 1] = { separator = true }
		local nextShock = Group("Next Shock", NextShockRows, "which shock to press next, on Flame Shock's icon")
		nextShock.value = function() return OnOff(Get("ns", "on")), false end
		nextShock.tip = "Flame Shock's icon shows which shock to press next, on each enemy by its own Flame Shock."
		items[#items + 1] = nextShock
	end
	items[#items + 1] = { separator = true }
	-- how it looks
	items[#items + 1] = Group("Appearance", function() return AppearanceRows(key) end,
		key == "purge" and "size, the buff's picture, border" or "size, time left, sweep, charges, border")
	items[#items + 1] = { separator = true }
	-- what it does at its moments
	if key == "purge" then
		items[#items + 1] = Group("When You Can Purge", function()
			local g = OnOffRow(key, "Glow", "glow", PIC.goldGlow)
			g.tip = "Purge's icon glows while your target has a buff you can remove."
			return { g }
		end, "the glow when your target has one")
	else
		local missing = Group("Missing Debuff", function() return MissingRows(key) end, "the warning while your " .. name .. " isn't on your target")
		missing.value = function() return OnOff(Get(key, "missing")), false end
		items[#items + 1] = missing
	end
	items[#items + 1] = { separator = true }
	-- where it sits
	if key == "purge" then
		items[#items + 1] = { text = "Position & Keys", label = true }
		local pos = ChoiceRow(key, "Position", "showOn", SHOWON_CHOICES, PIC.none)
		pos.tip = "Where Purge shows: a spot you place on your screen (Move Purge on this page), on your target's"
			.. " nameplate, or under the target frame."
		items[#items + 1] = pos
	end
	local off = OffPlaces(key)
	local plates = OnOffRow(key, "Show On Every Enemy's Nameplate", "everyPlate", PIC.plain)
	if key == "purge" then
		plates.tip = "Not only your target: Purge lights up on the nameplate of every enemy with a buff you can remove."
			.. " Skip Long Buffs counts there too. WoW's enemy nameplates need to be on."
	else
		plates.tip = "Not only your target: your " .. name .. " and its time left show on the nameplate of every enemy"
			.. " that has it. With Warn When It's Missing on, an enemy without it shows the gray warning. WoW's enemy"
			.. " nameplates need to be on."
	end
	if off then plates.tip = plates.tip .. " It's off in " .. off .. " (Show In)." end
	items[#items + 1] = plates
	items[#items + 1] = { separator = true }
	-- copy and reset
	items[#items + 1] = { text = "Copy & Reset", label = true }
	items[#items + 1] = { text = "Copy Settings", onClick = function() TT("TT_Copy", key); return true end }
	local from = TT("TT_ClipboardFrom")
	local fromSpell = from and SpellOf(from)
	items[#items + 1] = { text = fromSpell and ("Paste Settings  (from " .. fromSpell.name .. ")") or "Paste Settings",
		disabled = not fromSpell or from == key,
		onClick = function()
			TT("TT_Paste", key)
			Row:Changed(true)
			return true
		end }
	items[#items + 1] = { text = "Copy Settings To...", disabled = #Row.list < 2, subMaxHeight = 420,
		words = "every setting of this spell onto another", sub = function() return CopyItems(key) end }
	items[#items + 1] = { text = "Reset This Icon", disabled = not HasOwn(key),
		onClick = function() TT("TT_Reset", key); Row:Changed(false) end }
	return items
end

-- path: the submenus to open again (after the page laid itself out)
function Row:OpenMenu(key, path)
	local b = self.byKey[key]
	if not (b and b.spell and b:IsVisible()) then return end
	local s = b.spell
	self.openKey = key
	PaintButton(b)
	ns.ContextMenu:Open(b, {
		header = { text = s.name, icons = { Texture(s) } },
		items = function() return MenuItems(key) end,
		onClose = function()
			if Row.openKey == key then Row.openKey = nil end
			Row:Repaint()
		end,
	})
	if path and #path > 0 then ns.ContextMenu:ShowPath(path) end
end

-- ---------------------------------------------------------------------------
-- The row (ns.CustomRows: drawn by Window.lua's page packer, released on every redraw)
-- ---------------------------------------------------------------------------
local function OpenQueued()
	local q = Row.queued
	Row.queued = nil
	if q then Row:OpenMenu(q.key, q.path) end
end

function Row:Render(body, x, y, width, onChanged)
	if not Loaded() then return nil, 0 end
	self.onChanged = onChanged
	ns.TargetTrackerWatch()
	-- the menu closes with the settings window (hooked once: never SetScript on it)
	if not self.hooked and _G.ShamanPowerConfigUIFrame then
		self.hooked = true
		_G.ShamanPowerConfigUIFrame:HookScript("OnHide", function()
			Row.reopen = nil
			if Row.openKey and ns.ContextMenu:IsOpen() then ns.ContextMenu:Close() end
		end)
	end

	local f = self.frame
	if not f then
		f = CreateFrame("Frame", nil, body)
		f.caption = f:CreateFontString(nil, "OVERLAY")
		f.caption:SetFontObject(Core.fonts.caption)
		f.caption:SetJustifyH("LEFT")
		f.caption:SetWordWrap(true)
		f.spNoCull = true   -- (redrawn by its own watcher, which skips a hidden row)
		self.frame = f
	end
	f:SetParent(body)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", body, "TOPLEFT", x or 0, -(y or 0))
	f:SetWidth(width)
	f:Show()

	local list = Usable(self.list)
	wipe(self.byKey)
	local padX = PAD_X + (ns.Widgets and tonumber(ns.Widgets.CARD_INSET) or 0)   -- in line with the rows' labels
	for i, s in ipairs(list) do
		local b = self.buttons[i] or NewButton(f)
		self.buttons[i] = b
		b.spell = s
		b:ClearAllPoints()
		local gap = (s.key == "purge") and PURGE_GAP or 0
		b:SetPoint("TOPLEFT", f, "TOPLEFT", padX + (i - 1) * PITCH + gap, -PAD_TOP)
		b:Show()
		self.byKey[s.key] = b
	end
	for i = #list + 1, #self.buttons do
		local b = self.buttons[i]
		b.spell = nil
		b:Hide()
	end
	f.caption:ClearAllPoints()
	f.caption:SetPoint("TOPLEFT", f, "TOPLEFT", padX, -(PAD_TOP + PLATE + CAPTION_GAP))
	f.caption:SetWidth(width - padX * 2)
	f.caption:SetText(CAPTION)
	local h = PAD_TOP + PLATE + CAPTION_GAP + ceil(f.caption:GetStringHeight()) + PAD_BOTTOM
	f:SetHeight(h)
	self:Repaint()
	self.layoutKey = LayoutKey()   -- (the page is laid out for it)

	-- a menu open before the page laid itself out after one of its own choices: open it
	-- again on the same rows. Next frame: the icons are placed.
	local r = self.reopen
	self.reopen = nil
	if r and (not r.at or GetTime() - r.at < 2) and self.byKey[r.key] then
		self.queued = r
		C_Timer.After(0, OpenQueued)
	end
	return f, h + ROW_GAP
end

function Row:Release()
	if self.openKey and ns.ContextMenu:IsOpen() then
		-- a redraw made by one of the menu's own choices: open it again when drawn
		if self.writing then self.reopen = { key = self.openKey, path = ns.ContextMenu:OpenPath() } end
		ns.ContextMenu:Close()
	elseif self.queued then
		self.reopen = self.queued   -- drawn twice in one go (D42's gray page): it still opens after the second
	end
	self.openKey, self.queued = nil, nil
	if self.frame then self.frame:Hide() end
	for _, b in ipairs(self.buttons) do
		Core:HideTooltipFor(b)
		b.hoverEdge:Hide()
	end
end

-- Use the Old Settings Look (ListLook.lua, 3.0.8): this row as plain rows built from the
-- same menus. The shared icon row's def fields it reads, for this row's own copy.
Row.listDef = {
	hint = "Click: show or hide it\nRight-click: its settings",
	list = function(out)
		if not Loaded() then return end
		for _, s in ipairs(Usable(Row.list)) do out[#out + 1] = s end
	end,
	shown = function(s) return Shown(s.key) end,
	learned = function(s) return Known(s.key) end,
	toggle = function(s) TT("TT_Set", s.key, "shown", not Shown(s.key)) end,
	menu = function(s) return MenuItems(s.key) end,
	textures = function(s, out) out[1] = Texture(s) return 1 end,   -- (3.0.9: the icon's own screen draws it)
}

-- ===========================================================================
-- Party Buff Tracker > Party Strip: the Totems row (owner, 2026-10-06: "allow for
-- multiple totems, not just a single one", drawn like this page's Spells row: the
-- same plates, icons, shades, corner and caption). One icon per totem buff this game
-- version has (ShamanPower_PartyRange's list), in element order, a step apart between
-- the elements. Left-click shows or hides that totem on the strip. Dark: not learned
-- yet (it can still be picked; the strip shows it once it is learned). The accentHi
-- corner: it's on the strip (on a dark one too). No menu.
-- ===========================================================================
do
	local ELEMENT_GAP = 14   -- between the elements (as Purge's step above)
	local STRIP_CAPTION = "|cff3FA9F5CLICK|r a totem to show or hide it on the strip. A blue corner: it's on the strip. |cff3FA9F5Dark|r: you"
		.. " haven't learned it yet (pick it now, it shows once you learn it)."
	local Strip = { buttons = {} }
	ns.CustomRows.stripTotems = Strip

	local function StripLoaded()
		return type(SP.PartyStripTotems) == "function" and type(SP.PartyStripSetPicked) == "function"
	end
	local function TotemTexture(e)
		local tex
		if C_Spell and C_Spell.GetSpellTexture then tex = C_Spell.GetSpellTexture(e.totem)
		elseif GetSpellTexture then tex = GetSpellTexture(e.totem) end
		if not tex and SP.GetTotemIcon then tex = SP:GetTotemIcon(e.element, e.index) end
		return tex or 134400   -- the question mark
	end
	local function TipBody(picked, learned)
		if not learned then
			if picked then return "You haven't learned this yet. It shows on the strip once you learn it." end
			return "You haven't learned this yet. You can still pick it: it shows on the strip once you learn it."
		end
		if picked then return "It's on the strip." end
		return "It's not on the strip."
	end

	local function PaintStripButton(b)
		local e = b.totem
		if not e then return end
		local picked = SP:PartyStripPicked(e.key) and true or false
		local learned = SP:PartyStripTotemLearned(e) and true or false
		local shade = 1
		if not learned then shade = NOT_LEARNED_SHADE elseif not picked then shade = HIDDEN_SHADE end
		b.icon:SetTexture(TotemTexture(e))
		b.icon:SetDesaturated(not (picked and learned))
		b.icon:SetVertexColor(shade, shade, shade)
		b.corner:SetShown(picked)
		b.openEdge:Hide()
		Core:AttachTooltip(b, SP:PartyStripTotemName(e), TipBody(picked, learned),
			picked and "Click: take it off the strip" or "Click: show it on the strip")
	end

	function Strip:Repaint()
		for _, b in ipairs(self.buttons) do
			if b:IsShown() then PaintStripButton(b) end
		end
	end

	-- a pick saved (the strip follows it; in a fight, when the fight ends), then the page
	-- (rows that show or hide with the picks) and its preview
	local function StripClick(b)
		local e = b.totem
		if not e then return end
		SP:PartyStripSetPicked(e.key, not SP:PartyStripPicked(e.key))
		Strip:Repaint()
		local fn = Strip.onChanged
		if fn then
			local ok, err = pcall(fn)
			if not ok then geterrorhandler()(err) end
		end
	end

	local function NewStripButton(parent)
		local b = NewButton(parent)   -- (the Spells row's look)
		b:RegisterForClicks("LeftButtonUp")
		b:SetScript("OnClick", StripClick)
		return b
	end

	function Strip:Render(body, x, y, width, onChanged)
		if not StripLoaded() then return nil, 0 end
		self.onChanged = onChanged
		local f = self.frame
		if not f then
			f = CreateFrame("Frame", nil, body)
			f.caption = f:CreateFontString(nil, "OVERLAY")
			f.caption:SetFontObject(Core.fonts.caption)
			f.caption:SetJustifyH("LEFT")
			f.caption:SetWordWrap(true)
			self.frame = f
		end
		f:SetParent(body)
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", body, "TOPLEFT", x or 0, -(y or 0))
		f:SetWidth(width)
		f:Show()

		local list = SP:PartyStripTotems() or {}
		local padX = PAD_X + (ns.Widgets and tonumber(ns.Widgets.CARD_INSET) or 0)   -- in line with the rows' labels
		local px, py, last = padX, PAD_TOP, nil
		for i, e in ipairs(list) do
			local b = self.buttons[i] or NewStripButton(f)
			self.buttons[i] = b
			b.totem = e
			if last and e.element ~= last then px = px + ELEMENT_GAP end
			if i > 1 and px + PLATE > width - padX then   -- no room left: the next line
				px, py = padX, py + PITCH
			end
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", f, "TOPLEFT", px, -py)
			b:Show()
			px, last = px + PITCH, e.element
		end
		for i = #list + 1, #self.buttons do
			local b = self.buttons[i]
			b.totem = nil
			b:Hide()
		end
		local iconsH = (py - PAD_TOP) + PLATE
		f.caption:ClearAllPoints()
		f.caption:SetPoint("TOPLEFT", f, "TOPLEFT", padX, -(PAD_TOP + iconsH + CAPTION_GAP))
		f.caption:SetWidth(width - padX * 2)
		f.caption:SetText(STRIP_CAPTION)
		local h = PAD_TOP + iconsH + CAPTION_GAP + ceil(f.caption:GetStringHeight()) + PAD_BOTTOM
		f:SetHeight(h)
		self:Repaint()
		return f, h + ROW_GAP
	end

	function Strip:Release()
		if self.frame then self.frame:Hide() end
		for _, b in ipairs(self.buttons) do
			Core:HideTooltipFor(b)
			b.hoverEdge:Hide()
		end
	end

	-- Use the Old Settings Look (ListLook.lua, 3.0.8): one card per totem with its switch
	Strip.listDef = {
		hint = "Click: show or hide it on the strip",
		list = function(out)
			if not StripLoaded() then return end
			for _, e in ipairs(SP:PartyStripTotems() or {}) do
				out[#out + 1] = { key = e.key, name = SP:PartyStripTotemName(e), totem = e }
			end
		end,
		shown = function(it) return SP:PartyStripPicked(it.totem.key) and true or false end,
		learned = function(it) return SP:PartyStripTotemLearned(it.totem) and true or false end,
		toggle = function(it) SP:PartyStripSetPicked(it.totem.key, not SP:PartyStripPicked(it.totem.key)) end,
	}
end
