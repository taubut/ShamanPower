-- ============================================================================
-- Minimap icon right-click menu: the everyday switches without the settings
-- window (totem bar style, loadouts, assignments, Unlock UI, keybind mode,
-- What's New, setup, settings). Built on first use and only then; nothing runs
-- while it is closed.
--
-- The look (D33 "Branded", menus_glowup_mock.py style C): the settings window's
-- family. Its soft 1.5 px edge with a thin stripe of the four elements on top,
-- the totem graphic beside the ShamanPower wordmark, each section headed by a
-- strip tinted toward its element (its tiny totem box, its name in small caps),
-- the current choice lit like the settings sidebar's open page, hover the plain
-- row hover. Without the brand file (an update before a full restart) the
-- stripe, graphic and boxes are left out and the elements fall back to logo blue.
-- ============================================================================

local SP = ShamanPower
if not SP then return end

-- the mock's numbers: rows 22; edge 1.5; stripe 2; the tiny totem box 10 at 11 in;
-- the text 28 in; the lockup 40 tall under the stripe (the graphic 24 tall at 12 in,
-- 8 before the name); 4 after each section and 4 more under the last
local ROW_H, EDGE, STRIPE_H, WIDTH = 22, 1.5, 2, 220
local BOX, BOX_X, TEXT_X, RIGHT_PAD = 10, 11, 28, 16
local LOCKUP_H, GRAPHIC_H, LOCKUP_X, LOCKUP_GAP = 40, 24, 12, 8
local SECTION_GAP = 4
local STRIP_BG = { 32 / 255, 37 / 255, 46 / 255 }   -- Config's stripBg: the base of a section card's strip
local menu, catcher
local rows = {}

local function isShaman() return select(2, UnitClass("player")) == "SHAMAN" end

-- an element's color (SP.Brand); logo blue when the brand file is missing
local function elementRGB(key)
	if SP.BrandElementRGB then return SP:BrandElementRGB(key) end
	return 0.247, 0.663, 0.961
end

local function textWidth(fs)
	return (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth()
end

-- a horizontal gradient on either texture API
local function hGradient(tex, r1, g1, b1, r2, g2, b2)
	tex:SetColorTexture(1, 1, 1, 1)
	if CreateColor then
		if pcall(tex.SetGradient, tex, "HORIZONTAL", CreateColor(r1, g1, b1, 1), CreateColor(r2, g2, b2, 1)) then return end
	end
	if tex.SetGradientAlpha then tex:SetGradientAlpha("HORIZONTAL", r1, g1, b1, 1, r2, g2, b2, 1) return end
	tex:SetColorTexture(r1, g1, b1, 1)
end

local function build()
	menu = CreateFrame("Frame", "ShamanPowerMinimapMenu", UIParent)
	menu:SetFrameStrata("DIALOG")
	menu:SetFrameLevel(10)
	menu:SetClampedToScreen(true)
	local level = menu:GetFrameLevel()
	local bg = menu:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(menu)
	bg:SetColorTexture(SP:SPColor("sidebarBg", 0.97))
	menu:Hide()
	tinsert(UISpecialFrames, "ShamanPowerMinimapMenu")   -- Escape closes it
	-- a click anywhere else closes it
	catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("DIALOG")
	catcher:SetFrameLevel(1)
	catcher:RegisterForClicks("AnyUp")
	catcher:SetScript("OnClick", function() menu:Hide() end)
	catcher:Hide()
	menu:SetScript("OnHide", function() catcher:Hide() end)

	-- the lockup: the totem graphic (drawn only by the brand kit) beside the wordmark,
	-- "Shaman" in logo blue and "Power" in white
	local x = LOCKUP_X
	if SP.CreateTotemGraphic then
		local graphic = SP:CreateTotemGraphic(menu)
		graphic:SetGraphicHeight(GRAPHIC_H)
		graphic:SetPoint("TOPLEFT", menu, "TOPLEFT", LOCKUP_X, -(STRIPE_H + (LOCKUP_H - GRAPHIC_H) / 2))
		x = x + GRAPHIC_H * 650 / 682 + LOCKUP_GAP
	end
	local name = menu:CreateFontString(nil, "OVERLAY")
	name:SetFontObject(SP.SPDialogFonts.title)
	name:SetPoint("LEFT", menu, "TOPLEFT", x, -(STRIPE_H + LOCKUP_H / 2))
	name:SetText("|cff3FA9F5Shaman|r|cffFFFFFFPower|r")
	menu.name, menu.nameX = name, x

	-- the soft edge and the four elements along the top, over the rows
	local edge = CreateFrame("Frame", nil, menu)
	edge:SetAllPoints(menu)
	edge:SetFrameLevel(level + 10)
	SP:SPMakeBorder(edge, "border", EDGE)
	if SP.CreateElementStripe then
		local stripe = SP:CreateElementStripe(menu)
		stripe:SetStripeHeight(STRIPE_H)
		stripe:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, 0)
		stripe:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, 0)
		stripe:SetFrameLevel(level + 11)
	end
end

local function row(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, menu)
	r:SetHeight(ROW_H)
	-- a section's strip: 16% of its element over the strip navy
	r.strip = r:CreateTexture(nil, "BACKGROUND", nil, 0)
	r.strip:SetAllPoints(r)
	r.hover = r:CreateTexture(nil, "BACKGROUND", nil, 1)
	r.hover:SetAllPoints(r)
	r.hover:SetColorTexture(SP:SPColor("rowHover"))
	r.hover:Hide()
	-- the current choice: the element's light fading right and a 3 px element bar
	r.lit = r:CreateTexture(nil, "BACKGROUND", nil, 2)
	r.lit:SetAllPoints(r)
	r.bar = r:CreateTexture(nil, "ARTWORK")
	r.bar:SetWidth(3)
	r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
	r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
	if SP.CreateElementBox then
		r.box = SP:CreateElementBox(r, BOX)
		r.box:SetPoint("LEFT", r, "LEFT", BOX_X - EDGE, 0)
	end
	r.text = r:CreateFontString(nil, "OVERLAY")
	r.text:SetFontObject(SP.SPDialogFonts.text)
	r.text:SetPoint("LEFT", r, "LEFT", TEXT_X - EDGE, 0)
	r.text:SetPoint("RIGHT", r, "RIGHT", -6, 0)
	r.text:SetJustifyH("LEFT")
	-- the lit row stays as it is under the mouse (the settings sidebar's open page)
	r:SetScript("OnEnter", function(self) if self.fn and not self.current then self.hover:Show() end end)
	r:SetScript("OnLeave", function(self) self.hover:Hide() end)
	r:SetScript("OnClick", function(self)
		local fn = self.fn
		menu:Hide()
		if fn then fn() end
	end)
	rows[i] = r
	return r
end

-- items: { text, fn, checked, header, element (a header's), disabled, action }
local function fill(items)
	for _, r in ipairs(rows) do r:Hide() end
	local tr, tg, tb = SP:SPColor("text")
	local hr, hg, hb = SP:SPColor("rowHover")
	local y, widest = STRIPE_H + LOCKUP_H, menu.nameX + textWidth(menu.name) + LOCKUP_X
	local key = "spirit"
	local er, eg, eb = elementRGB(key)
	for i, it in ipairs(items) do
		local r = row(i)
		if it.header then
			if i > 1 then y = y + SECTION_GAP end
			key = it.element or "spirit"
			er, eg, eb = elementRGB(key)
		end
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", menu, "TOPLEFT", EDGE, -y)
		r:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -EDGE, -y)
		r.fn = (not it.header and not it.disabled) and it.fn or nil
		r.current = (not it.header and it.checked) and true or false
		r.hover:Hide()
		r.strip:SetShown(it.header and true or false)
		r.lit:SetShown(r.current)
		r.bar:SetShown(r.current)
		if r.box then
			r.box:SetShown(it.header or r.current)
			r.box:SetElement(key)
			if it.disabled then r.box:SetShade(0.5) else r.box:SetShade(1) end
		end
		if it.header then
			local sr, sg, sb = STRIP_BG[1], STRIP_BG[2], STRIP_BG[3]
			r.strip:SetColorTexture(er * 0.16 + sr * 0.84, eg * 0.16 + sg * 0.84, eb * 0.16 + sb * 0.84, 1)
			r.text:SetFontObject(SP.SPDialogFonts.group)
			r.text:SetText(strupper(it.text))
			r.text:SetTextColor(er * 0.55 + tr * 0.45, eg * 0.55 + tg * 0.45, eb * 0.55 + tb * 0.45)
		else
			r.text:SetFontObject(SP.SPDialogFonts.text)
			r.text:SetText(it.text)
			if it.disabled then
				r.text:SetTextColor(SP:SPColor("textMute"))
			elseif it.action then
				r.text:SetTextColor(SP:SPColor("accentHi"))   -- blue: a thing you click (D33)
			else
				r.text:SetTextColor(tr, tg, tb)
			end
			if r.current then
				-- 28% of the element over rowHover, fading to rowHover (painted once per element)
				if r.litKey ~= key then
					r.litKey = key
					hGradient(r.lit, er * 0.28 + hr * 0.72, eg * 0.28 + hg * 0.72, eb * 0.28 + hb * 0.72, hr, hg, hb)
					r.bar:SetColorTexture(er, eg, eb, 1)
				end
			end
		end
		r:Show()
		-- as wide as the longest line: nothing is ever cut off
		widest = math.max(widest, TEXT_X + textWidth(r.text) + RIGHT_PAD)
		y = y + ROW_H
	end
	menu:SetSize(math.max(WIDTH, widest), y + SECTION_GAP * 2)
end

local function items()
	local list = {}
	local function add(t) list[#list + 1] = t end
	local combat = InCombatLockdown()
	-- Switched off: the icon stays for this one way back
	if SP.IsOff and SP:IsOff() then
		add({ text = "ShamanPower", header = true, element = "air" })
		add({ text = "ShamanPower is off", disabled = true })
		add({ text = "Turn ShamanPower Back On", action = true, fn = function() SP:SetOff(false) end })
		return list
	end
	-- Windfury-only mode keeps the icon for this one way back to everything else
	if not isShaman() and SP.WindfuryOnly and SP:WindfuryOnly() then
		add({ text = "ShamanPower", header = true, element = "air" })
		add({ text = "Windfury-only mode is on", disabled = true })
		add({ text = "Turn On Other Features", fn = function() SP:SetWindfuryOnly(false) end })
		return list
	end
	-- the elements (D33): both totem bar sections Earth, ShamanPower Air (General's)
	if isShaman() then
		if SP.TotemBarStyleList and SP.GetTotemBarStyle then
			add({ text = "Totem Bar Style", header = true, element = "earth" })
			local cur = SP:GetTotemBarStyle()
			for _, st in ipairs(SP:TotemBarStyleList()) do
				local key = st.key
				add({ text = st.label, checked = (cur == key), disabled = combat, fn = function() SP:SetTotemBarStyle(key) end })
			end
		end
		local loadouts = ShamanPower_TotemLoadouts
		add({ text = "Loadouts", header = true, element = "earth" })
		if type(loadouts) == "table" and #loadouts > 0 then
			for i, lo in ipairs(loadouts) do
				local idx = i
				add({ text = lo.name or ("Loadout " .. i), checked = (SP.opt.activeLoadout == i), disabled = combat, fn = function() SP:ApplyLoadout(idx) end })
			end
		else
			add({ text = "No loadouts saved yet", disabled = true })
		end
		add({ text = "ShamanPower", header = true, element = "air" })
		add({ text = "Totem Assignments", fn = function() SP:ToggleAssignmentWindow() end })
		if SP.ToggleMasterUnlock then add({ text = "Unlock UI (move everything)", disabled = combat, fn = function() SP:ToggleMasterUnlock() end }) end
		local kb = SP.ToggleKeybindMode or SP.StartKeybindMode
		if kb then add({ text = "Keybind Mode", disabled = combat, fn = function() kb(SP) end }) end
	else
		add({ text = "ShamanPower", header = true, element = "air" })
		add({ text = "Totem Range Overlay", fn = function()
			SP:InitSPRange()
			if not SP.spRangeFrame then SP:CreateSPRangeFrame() end
			SP:ShowSPRangeConfig()
		end })
		if SP.SetWindfuryOnly and not SPCompat.FOREVER then
			add({ text = "Windfury-Only Mode", checked = SP:WindfuryOnly(), fn = function() SP:SetWindfuryOnly(not SP:WindfuryOnly()) end })
		end
	end
	if SP.ShowWhatsNew then add({ text = "What's New", fn = function() SP:ShowWhatsNew(true) end }) end
	-- OpenConfigWindow() with no page toggles: an open window would close
	add({ text = "Open Settings", action = true, fn = function()
		local win = _G["ShamanPowerConfigUIFrame"]
		if win and win:IsShown() then win:Raise() else SP:OpenConfigWindow() end
	end })
	return list
end

function SP:ShowMinimapMenu(anchor)
	if not menu then build() end
	if menu:IsShown() then menu:Hide() return end
	fill(items())
	menu:ClearAllPoints()
	local scale = UIParent:GetEffectiveScale()
	local x, y = GetCursorPosition()
	menu:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	catcher:Show()
	menu:Show()
	menu:Raise()
end
