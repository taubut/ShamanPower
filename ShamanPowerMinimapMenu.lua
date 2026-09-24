-- ============================================================================
-- Minimap icon right-click menu: the everyday switches without the settings
-- window (totem bar style, loadouts, assignments, Unlock UI, keybind mode,
-- What's New, setup, settings). Built on first use and only then; nothing runs
-- while it is closed.
-- ============================================================================

local SP = ShamanPower
if not SP then return end

local ROW_H, PAD, WIDTH = 20, 8, 220
local menu, catcher
local rows = {}

local function isShaman() return select(2, UnitClass("player")) == "SHAMAN" end

local function build()
	menu = CreateFrame("Frame", "ShamanPowerMinimapMenu", UIParent, "BackdropTemplate")
	menu:SetFrameStrata("DIALOG")
	menu:SetClampedToScreen(true)
	menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	menu:SetBackdropColor(0.07, 0.08, 0.10, 0.97)
	menu:SetBackdropBorderColor(0.0, 0.44, 0.87, 1)
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
	r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(r); r.bg:SetColorTexture(0, 0.44, 0.87, 0.35); r.bg:Hide()
	r.check = r:CreateTexture(nil, "ARTWORK"); r.check:SetSize(14, 14); r.check:SetPoint("LEFT", r, "LEFT", 4, 0)
	r.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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

-- items: { text, fn, checked, header, disabled }
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
		r.text:SetText(it.text)
		if it.header then
			r.text:SetTextColor(1, 0.82, 0)
			r.text:SetPoint("LEFT", r, "LEFT", 4, 0)
		else
			r.text:SetPoint("LEFT", r, "LEFT", 22, 0)
			if it.disabled then r.text:SetTextColor(0.5, 0.5, 0.5) else r.text:SetTextColor(0.92, 0.93, 0.95) end
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
	add({ text = "Fonts", fn = function() SP:OpenConfigWindow({ "settings", "settings_fonts" }) end })
	if SP.ShowWhatsNew then add({ text = "What's New", fn = function() SP:ShowWhatsNew(true) end }) end
	add({ text = "Setup Tour", fn = function() if SP.Wizard and SP.Wizard.Open then SP.Wizard:Open() end end })
	add({ text = "Open Settings", fn = function() SP:OpenConfigWindow() end })
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
