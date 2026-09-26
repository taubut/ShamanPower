-- ============================================================================
-- Minimap icon right-click menu: the everyday switches without the settings
-- window (totem bar style, loadouts, assignments, Unlock UI, keybind mode,
-- What's New, setup, settings). Built on first use and only then; nothing runs
-- while it is closed.
-- ============================================================================

local SP = ShamanPower
if not SP then return end

local ROW_H, PAD, WIDTH = 22, 8, 220
local menu, catcher
local rows = {}

local function isShaman() return select(2, UnitClass("player")) == "SHAMAN" end

local function build()
	-- the settings window's popup list: sidebarBg, 1px accent border
	menu = CreateFrame("Frame", "ShamanPowerMinimapMenu", UIParent)
	menu:SetFrameStrata("DIALOG")
	menu:SetClampedToScreen(true)
	local bg = menu:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(menu)
	bg:SetColorTexture(SP:SPColor("sidebarBg", 0.97))
	SP:SPMakeBorder(menu, "accent")
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
	menu:SetFrameLevel(10)
end

local function row(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, menu)
	r:SetHeight(ROW_H)
	r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(r); r.bg:SetColorTexture(SP:SPColor("rowHover")); r.bg:Hide()
	-- the check: the settings window's checkbox when on (a box with an accentHi fill)
	r.check = CreateFrame("Frame", nil, r); r.check:SetSize(14, 14); r.check:SetPoint("LEFT", r, "LEFT", 4, 0)
	local box = r.check:CreateTexture(nil, "BACKGROUND"); box:SetAllPoints(r.check); box:SetColorTexture(SP:SPColor("windowBg"))
	SP:SPMakeBorder(r.check, "accent")
	local tick = r.check:CreateTexture(nil, "ARTWORK"); tick:SetPoint("TOPLEFT", 3, -3); tick:SetPoint("BOTTOMRIGHT", -3, 3)
	tick:SetColorTexture(SP:SPColor("accentHi"))
	r.text = r:CreateFontString(nil, "OVERLAY")
	r.text:SetFontObject(SP.SPDialogFonts.text)
	r.text:SetPoint("LEFT", r, "LEFT", 22, 0); r.text:SetPoint("RIGHT", r, "RIGHT", -6, 0)
	r.text:SetJustifyH("LEFT")
	r:SetScript("OnEnter", function(self) if self.fn then self.bg:Show() end end)
	r:SetScript("OnLeave", function(self) self.bg:Hide() end)
	r:SetScript("OnClick", function(self)
		local fn = self.fn
		menu:Hide()
		if fn then fn() end
	end)
	rows[i] = r
	return r
end

-- items: { text, fn, checked, header, disabled, gold }
local function fill(items)
	for _, r in ipairs(rows) do r:Hide() end
	local y, widest = -PAD, 0
	for i, it in ipairs(items) do
		local r = row(i)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", menu, "TOPLEFT", PAD, y)
		r:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -PAD, y)
		r.fn = (not it.header and not it.disabled) and it.fn or nil
		r.check:SetShown(it.checked and true or false)
		if it.header then
			-- the settings sidebar's group headers
			r.text:SetFontObject(SP.SPDialogFonts.group)
			r.text:SetText(strupper(it.text))
			r.text:SetTextColor(SP:SPColor("accentHi"))
			r.text:SetPoint("LEFT", r, "LEFT", 4, 0)
		else
			r.text:SetFontObject(SP.SPDialogFonts.text)
			r.text:SetText(it.text)
			if it.gold and not it.disabled then
				r.text:SetTextColor(1, 0.82, 0)   -- the gold of /sp help's commands: easy to spot
			else
				r.text:SetTextColor(SP:SPColor(it.disabled and "textMute" or "text"))
			end
			r.text:SetPoint("LEFT", r, "LEFT", 22, 0)
		end
		r:Show()
		local w = (r.text.GetUnboundedStringWidth and r.text:GetUnboundedStringWidth()) or r.text:GetStringWidth()
		widest = math.max(widest, w + (it.header and 4 or 22) + 8)
		y = y - ROW_H
	end
	-- as wide as the longest line: nothing is ever cut off
	menu:SetSize(math.max(WIDTH, widest + PAD * 2), -y + PAD)
end

local function items()
	local list = {}
	local function add(t) list[#list + 1] = t end
	local combat = InCombatLockdown()
	-- Switched off: the icon stays for this one way back
	if SP.IsOff and SP:IsOff() then
		add({ text = "ShamanPower", header = true })
		add({ text = "ShamanPower is off", disabled = true })
		add({ text = "Turn ShamanPower Back On", gold = true, fn = function() SP:SetOff(false) end })
		return list
	end
	-- Windfury-only mode keeps the icon for this one way back to everything else
	if not isShaman() and SP.WindfuryOnly and SP:WindfuryOnly() then
		add({ text = "ShamanPower", header = true })
		add({ text = "Windfury-only mode is on", disabled = true })
		add({ text = "Turn On Other Features", fn = function() SP:SetWindfuryOnly(false) end })
		return list
	end
	if isShaman() then
		if SP.TotemBarStyleList and SP.GetTotemBarStyle then
			add({ text = "Totem Bar Style", header = true })
			local cur = SP:GetTotemBarStyle()
			for _, st in ipairs(SP:TotemBarStyleList()) do
				local key = st.key
				add({ text = st.label, checked = (cur == key), disabled = combat, fn = function() SP:SetTotemBarStyle(key) end })
			end
		end
		local loadouts = ShamanPower_TotemLoadouts
		add({ text = "Loadouts", header = true })
		if type(loadouts) == "table" and #loadouts > 0 then
			for i, lo in ipairs(loadouts) do
				local idx = i
				add({ text = lo.name or ("Loadout " .. i), checked = (SP.opt.activeLoadout == i), disabled = combat, fn = function() SP:ApplyLoadout(idx) end })
			end
		else
			add({ text = "No loadouts saved yet", disabled = true })
		end
		add({ text = "ShamanPower", header = true })
		add({ text = "Totem Assignments", fn = function() SP:ToggleAssignmentWindow() end })
		if SP.ToggleMasterUnlock then add({ text = "Unlock UI (move everything)", disabled = combat, fn = function() SP:ToggleMasterUnlock() end }) end
		local kb = SP.ToggleKeybindMode or SP.StartKeybindMode
		if kb then add({ text = "Keybind Mode", disabled = combat, fn = function() kb(SP) end }) end
	else
		add({ text = "ShamanPower", header = true })
		add({ text = "Totem Range Overlay", fn = function()
			SP:InitSPRange()
			if not SP.spRangeFrame then SP:CreateSPRangeFrame() end
			SP:ShowSPRangeConfig()
		end })
		if SP.SetWindfuryOnly then
			add({ text = "Windfury-Only Mode", checked = SP:WindfuryOnly(), fn = function() SP:SetWindfuryOnly(not SP:WindfuryOnly()) end })
		end
	end
	if SP.ShowWhatsNew then add({ text = "What's New", fn = function() SP:ShowWhatsNew(true) end }) end
	-- OpenConfigWindow() with no page toggles: an open window would close
	add({ text = "Open Settings", gold = true, fn = function()
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
