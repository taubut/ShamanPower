-- ============================================================================
-- Mana tint: a totem or cooldown you cannot afford right now is tinted, the way
-- Blizzard's action bars show it (opt.manaTint, off by default; the colour is
-- opt.manaTintColor). Event-driven: the game says when a spell's usability
-- changes (SPELL_UPDATE_USABLE), and the buttons are re-checked then and when
-- their spells change. Nothing runs while nothing changes.
-- ============================================================================

local SP = ShamanPower
if not SP then return end
if select(2, UnitClass("player")) ~= "SHAMAN" then return end

local secret = issecretvalue or function() return false end
local IsSpellUsable = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell

SP.MANA_TINT_DEFAULT = { r = 0.45, g = 0.45, b = 1.0 }   -- Blizzard's "not enough mana" blue

-- The buttons cast by name, which is the highest rank known, while the spell
-- IDs they carry are rank 1: ask about the name, or a button you cannot afford
-- at your rank stays untinted while rank 1 is still affordable. A spell whose
-- name the client cannot read (Tranquil Air Totem on Forever) is asked about
-- by its ID, as before. (GetSpellInfo by ID is cached per ID on Forever, so
-- this makes no garbage.)
local function castName(spellID)
	return spellID and (GetSpellInfo(spellID) or spellID) or nil
end

-- true = not enough mana, false = can cast, nil = unknown (hidden in combat) or no spell
local function lacksMana(spell)
	if not spell or not IsSpellUsable then return nil end
	local ok, usable, noMana = pcall(IsSpellUsable, spell)
	if not ok or secret(usable) or secret(noMana) then return nil end
	return noMana and true or false
end

-- colour one icon; tinted[icon] remembers which icons we coloured, so turning
-- the option off (or getting the mana back) restores exactly those
local tinted = setmetatable({}, { __mode = "k" })
local function paint(icon, spell, on)
	if not icon then return end
	local noMana = on and lacksMana(spell)
	if noMana then
		local c = SP.opt.manaTintColor or SP.MANA_TINT_DEFAULT
		icon:SetVertexColor(c.r or 0.45, c.g or 0.45, c.b or 1)
		tinted[icon] = true
	elseif noMana == false or not on then
		if tinted[icon] then icon:SetVertexColor(1, 1, 1); tinted[icon] = nil end
	end
	-- nil (hidden right now): leave the icon as it is until the game says more
end

function SP:UpdateManaTint()
	if not self.opt then return end
	local on = self.opt.manaTint == true
	-- the totem bar: each element's assigned totem
	local assign = ShamanPower_Assignments and self.player and ShamanPower_Assignments[self.player]
	for element = 1, 4 do
		local idx = assign and assign[element] or 0
		local spell = castName(idx and idx > 0 and self:GetTotemSpell(element, idx) or nil)
		local btn = self.totemButtons and self.totemButtons[element]
		paint(btn and btn.icon, spell, on)
		paint(_G["ShamanPowerAutoTotem" .. element .. "Icon"], spell, on)
		-- that element's flyout
		local flyout = self.totemFlyouts and self.totemFlyouts[element]
		if flyout and flyout.buttons then
			for _, fb in ipairs(flyout.buttons) do paint(fb.icon, castName(fb.spellID), on) end
		end
	end
	-- the cooldown bar
	if self.cooldownButtons then
		for i = 1, #self.cooldownButtons do
			local b = self.cooldownButtons[i]
			paint(b and b.icon, b and castName(b.spellID), on)
		end
	end
end

local f = CreateFrame("Frame")
if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(f, "Mana Tint") end
f:RegisterEvent("SPELL_UPDATE_USABLE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_TOTEM_UPDATE")
f:SetScript("OnEvent", function()
	if SP:IsOff() then return end   -- switched off: the buttons are down (re-tinted by ButtonsUpdate on switch-on)
	if SP.opt and (SP.opt.manaTint == true or next(tinted)) then SP:UpdateManaTint() end
end)

-- the buttons' spells change with assignments and rebuilt bars
for _, name in ipairs({ "ButtonsUpdate", "UpdateDynamicTotemIcons", "RecreateCooldownBar" }) do
	if type(SP[name]) == "function" then
		hooksecurefunc(SP, name, function() if SP.opt and SP.opt.manaTint == true and not SP:IsOff() then SP:UpdateManaTint() end end)
	end
end

-- Settings: Appearance > Textures & Colors (Status Colors)
do
	local sec = SP.options and SP.options.args.fluffy and SP.options.args.fluffy.args.color_section
	if sec and sec.args then
		sec.args.manaTint = {
			order = 50, type = "toggle", name = "Tint Totems You Cannot Afford", width = "full",
			desc = "Colour a totem or cooldown button blue while you do not have the mana for it, like Blizzard's action bars. Changes the moment your mana crosses the cost.",
			get = function() return SP.opt.manaTint == true end,
			set = function(_, v) SP.opt.manaTint = v or nil; SP:UpdateManaTint() end,
		}
		sec.args.manaTintColor = {
			order = 51, type = "color", name = "Tint Colour",
			disabled = function() return SP.opt.manaTint ~= true end,
			get = function() local c = SP.opt.manaTintColor or SP.MANA_TINT_DEFAULT; return c.r, c.g, c.b end,
			set = function(_, r, g, b) SP.opt.manaTintColor = { r = r, g = g, b = b }; SP:UpdateManaTint() end,
		}
	end
end
