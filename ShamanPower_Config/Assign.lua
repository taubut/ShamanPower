-- ShamanPower_Config :: Assign
-- The totem assignment window, rebuilt in pure Lua on the Core/Widgets kit.
-- Replaces the legacy XML assignment window. Nothing here is secure, so the
-- window may be built, shown and redrawn in combat; only the actions that
-- reach macros / secure bars are gated, and the engine already gates those.
--
-- Engine boundary: this file never writes ShamanPower_Assignments. Cells call
-- ShamanPower:PerformCycle / PerformCycleBackwards; every other write mirrors
-- the exact sequence the XML window used (spec §3.4, §3.5, §3.8).

local ADDON, ns = ...
local Core    = ns.Core
local Widgets = ns.Widgets

local Assign = {}
ns.Assign = Assign
_G.ShamanPowerAssign = Assign

local SP = ShamanPower

-- Geometry -------------------------------------------------------------------
local PAD        = 14
local NAME_W     = 150
local ES_W       = 56
local CELL_W     = 84
local CELL_H     = 50
local CELL_GAP   = 6
local ROW_H      = 58
local ROW_GAP    = 4
local HEADER_H   = 52
local COLHEAD_H  = 26
local FOOTER_H   = 48
local MAX_ROWS   = 10   -- rows visible before the body scrolls

local WIN_W = PAD + NAME_W + ES_W + 4 * CELL_W + 3 * CELL_GAP + PAD

local ELEMENTS = {
	{ label = "Earth", r = 0.72, g = 0.52, b = 0.32 },
	{ label = "Fire",  r = 1.00, g = 0.36, b = 0.22 },
	{ label = "Water", r = 0.42, g = 0.58, b = 1.00 },
	{ label = "Air",   r = 0.86, g = 0.88, b = 0.98 },
}

local function CellX(e)
	return NAME_W + ES_W + (e - 1) * (CELL_W + CELL_GAP)
end

local frame
local rows = {}

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
local function Opt()
	return SP and SP.opt or {}
end

local function Tooltips()
	local o = Opt()
	return o.ShowTooltips ~= false
end

local function MarkDirty()
	if frame then frame._dirty = true end
end
Assign.MarkDirty = MarkDirty

local function ClassHex(class)
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if not c then return "|cffffffff" end
	return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

-- The engine gates these itself and returns silently; the window says why.
local function CombatBlocked()
	if InCombatLockdown() then
		if UIErrorsFrame then
			UIErrorsFrame:AddMessage("Can't change assignments in combat", 1, 0.25, 0.25)
		end
		return true
	end
	return false
end

local function NotifyOptions()
	local reg = LibStub and LibStub("AceConfigRegistry-3.0", true)
	if reg then reg:NotifyChange("ShamanPower") end
end

-- Pill switch matching the config UI toggle.
local function MakePill(parent)
	local track = CreateFrame("Button", nil, parent)
	track:SetSize(38, 18)
	track.tex = track:CreateTexture(nil, "BACKGROUND")
	track.tex:SetAllPoints(track)
	Core:MakeBorder(track, "border")
	track.knob = track:CreateTexture(nil, "OVERLAY")
	track.knob:SetSize(12, 12)
	track.knob:SetColorTexture(0.95, 0.96, 0.98, 1)
	function track:Paint(on)
		self.tex:SetColorTexture(Core:ColorIf(on, "accent", "off"))
		self.knob:ClearAllPoints()
		if on then
			self.knob:SetPoint("RIGHT", self, "RIGHT", -3, 0)
		else
			self.knob:SetPoint("LEFT", self, "LEFT", 3, 0)
		end
	end
	track:Paint(false)
	return track
end

-- Small square checkbox.
local function MakeCheck(parent, labelText)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(14, 14)
	Core:SolidTex(b, "windowBg", "BACKGROUND")
	Core:MakeBorder(b, "border")
	b.fill = b:CreateTexture(nil, "ARTWORK")
	b.fill:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
	b.fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
	b.fill:SetColorTexture(Core:Color("accentHi"))
	b.label = b:CreateFontString(nil, "OVERLAY")
	b.label:SetFontObject(Core.fonts.rowDim)
	b.label:SetPoint("LEFT", b, "RIGHT", 5, 0)
	b.label:SetText(labelText)
	-- Let the label be part of the hit area.
	b:SetHitRectInsets(0, -(b.label:GetStringWidth() + 8), 0, 0)
	function b:Paint(on)
		self.fill:SetShown(on and true or false)
		Core:SetBorderColor(self, on and "accent" or "border")
	end
	b:Paint(false)
	return b
end

local function FooterButton(parent, text, width, primary)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(26)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(b)
	bg:SetColorTexture(Core:Color("accent", primary and 0.30 or 0.12))
	Core:MakeBorder(b, primary and "accent" or "border")
	local t = b:CreateFontString(nil, "OVERLAY")
	t:SetFontObject(Core.fonts.button)
	t:SetPoint("CENTER")
	t:SetText(text)
	t:SetTextColor(Core:Color(primary and "accentHi" or "text"))
	b:SetWidth(math.max(width, t:GetStringWidth() + 28))
	b:SetScript("OnEnter", function() bg:SetColorTexture(Core:Color("accent", primary and 0.48 or 0.26)) end)
	b:SetScript("OnLeave", function() bg:SetColorTexture(Core:Color("accent", primary and 0.30 or 0.12)) end)
	b.text = t
	return b
end

-- ---------------------------------------------------------------------------
-- Group roster (for the Earth Shield picker) -- mirrors the XML dropdown
-- ---------------------------------------------------------------------------
local function GroupMembers()
	local members = {}
	local inRaid = IsInRaid()
	if inRaid then
		for i = 1, GetNumGroupMembers() do
			local name, _, subgroup, _, _, class = GetRaidRosterInfo(i)
			if name then
				table.insert(members, { name = name, class = class, subgroup = subgroup or 1 })
			end
		end
	elseif IsInGroup() then
		table.insert(members, { name = UnitName("player"), class = select(2, UnitClass("player")), subgroup = 1 })
		for i = 1, GetNumSubgroupMembers() do
			local unit = "party" .. i
			local name = UnitName(unit)
			if name then
				table.insert(members, { name = name, class = select(2, UnitClass(unit)), subgroup = 1 })
			end
		end
	else
		table.insert(members, { name = UnitName("player"), class = select(2, UnitClass("player")), subgroup = 1 })
	end
	table.sort(members, function(a, b)
		if a.subgroup ~= b.subgroup then return a.subgroup < b.subgroup end
		return a.name < b.name
	end)
	return members, inRaid
end

-- Exact write sequence of the old dropdown (spec §3.4).
local function SetEarthShieldTarget(shaman, target)
	ShamanPower_EarthShieldAssignments = ShamanPower_EarthShieldAssignments or {}
	ShamanPower_EarthShieldAssignments[shaman] = target
	SP:SendMessage("ESASSIGN " .. shaman .. " " .. (target or "NONE"))
	SP:UpdateLayout()
	if target then
		SP:UpdateMiniTotemBar()
		SP:UpdateEarthShieldButton()
	end
	if shaman == SP.player then
		SP:UpdateEarthShieldMacroButton()
	end
	MarkDirty()
end

local function ShowEarthShieldPicker(anchor, shaman)
	local members, inRaid = GroupMembers()
	local items = { { key = false, text = "|cff8A94A6None|r" } }
	for _, m in ipairs(members) do
		local prefix = inRaid and ("|cff5A6678G" .. m.subgroup .. "|r  ") or ""
		table.insert(items, { key = m.name, text = prefix .. ClassHex(m.class) .. m.name .. "|r" })
	end
	local current = ShamanPower_EarthShieldAssignments and ShamanPower_EarthShieldAssignments[shaman] or false
	Widgets:ShowPopup(anchor, items, current, function(key)
		SetEarthShieldTarget(shaman, key or nil)
	end, { width = 180 })
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------
local function CellOnClick(cell, button)
	local row = cell.row
	if not row or not row.name then return end
	if CombatBlocked() then return end
	if not SP:CanControl(row.name) then return end
	if button == "RightButton" then
		SP:PerformCycleBackwards(row.name, cell.element)
	else
		SP:PerformCycle(row.name, cell.element)
	end
	MarkDirty()
end

local function CellOnWheel(cell, delta)
	if delta < 0 then
		CellOnClick(cell, "LeftButton")
	else
		CellOnClick(cell, "RightButton")
	end
end

local function CellTooltip(cell)
	if not Tooltips() then return end
	local row = cell.row
	if not row or not row.name then return end
	local a = ShamanPower_Assignments and ShamanPower_Assignments[row.name]
	local idx = a and a[cell.element] or 0
	local names = SP.TotemNames and SP.TotemNames[cell.element]
	local title = (idx and idx > 0 and names and names[idx]) or "Unassigned"
	GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
	GameTooltip:SetClampedToScreen(true)
	GameTooltip:AddLine(title, 1, 1, 1)
	GameTooltip:AddLine(ELEMENTS[cell.element].label .. " totem for " .. row.name, 0.6, 0.65, 0.72)
	if SP:CanControl(row.name) then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Left-click / wheel down: next totem", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Right-click / wheel up: previous totem", 0.8, 0.8, 0.8)
	else
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Leader or assist only", 1, 0.3, 0.3)
	end
	GameTooltip:Show()
end

local function MakeCell(row, e)
	local el = ELEMENTS[e]
	local cell = CreateFrame("Button", nil, row)
	cell:SetSize(CELL_W, CELL_H)
	cell:SetPoint("LEFT", row, "LEFT", CellX(e), 0)
	cell.row = row
	cell.element = e

	cell.bg = cell:CreateTexture(nil, "BACKGROUND")
	cell.bg:SetAllPoints(cell)
	cell.bg:SetColorTexture(el.r, el.g, el.b, 0.10)
	Core:MakeBorder(cell, "borderSoft")

	cell.icon = cell:CreateTexture(nil, "ARTWORK")
	cell.icon:SetSize(36, 36)
	cell.icon:SetPoint("CENTER")
	cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	cell.empty = cell:CreateFontString(nil, "OVERLAY")
	cell.empty:SetFontObject(Core.fonts.row)
	cell.empty:SetPoint("CENTER")
	cell.empty:SetText("–")
	cell.empty:SetTextColor(Core:Color("textMute"))

	cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	cell:EnableMouseWheel(true)
	cell:SetScript("OnClick", CellOnClick)
	cell:SetScript("OnMouseWheel", CellOnWheel)
	cell:SetScript("OnEnter", function(self)
		if self._control then
			for _, t in pairs(self.spBorder) do t:SetColorTexture(el.r, el.g, el.b, 0.9) end
			self.bg:SetColorTexture(el.r, el.g, el.b, 0.22)
		end
		CellTooltip(self)
	end)
	cell:SetScript("OnLeave", function(self)
		Core:SetBorderColor(self, "borderSoft")
		self.bg:SetColorTexture(el.r, el.g, el.b, 0.10)
		GameTooltip:Hide()
	end)
	return cell
end

local function TwistOnClick(check)
	local row = check.row
	local name = row and row.name
	if not name then return end
	-- Self always; others only with control (the receiver enforces this too).
	if name ~= SP.player and not SP:CanControl(name) then return end
	ShamanPower_TwistAssignments = ShamanPower_TwistAssignments or {}
	local checked = not (ShamanPower_TwistAssignments[name] or false)
	ShamanPower_TwistAssignments[name] = checked
	SP:SendMessage("TWIST " .. name .. " " .. (checked and "1" or "0"))
	if name == SP.player then
		SP.opt.enableTotemTwisting = checked
		SP:UpdateMiniTotemBar()
		SP:UpdateSPMacros()
		NotifyOptions()
		if checked then SP:SetupTwistTimer() else SP:HideTwistTimer() end
	end
	MarkDirty()
end

local function EsOnClick(btn, button)
	local row = btn.row
	if not row or not row.name then return end
	if CombatBlocked() then return end
	if not SP:CanControl(row.name) then return end
	local info = SP.AllShamans and SP.AllShamans[row.name]
	if not (info and info.hasEarthShield) then return end
	if button == "RightButton" then
		SetEarthShieldTarget(row.name, nil)
	else
		ShowEarthShieldPicker(btn, row.name)
	end
end

local function MakeRow(parent, index)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(WIN_W - PAD * 2, ROW_H - ROW_GAP)
	Core:RowBg(row)

	row.selfBar = row:CreateTexture(nil, "ARTWORK")
	row.selfBar:SetWidth(2)
	row.selfBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.selfBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	row.selfBar:SetColorTexture(Core:Color("accent"))

	row.nameFS = row:CreateFontString(nil, "OVERLAY")
	row.nameFS:SetFontObject(Core.fonts.row)
	row.nameFS:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -10)
	row.nameFS:SetWidth(NAME_W - 20)
	row.nameFS:SetJustifyH("LEFT")

	row.twist = MakeCheck(row, "Twist")
	row.twist:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 12, 10)
	row.twist.row = row
	row.twist:SetScript("OnClick", TwistOnClick)
	row.twist:SetScript("OnEnter", function(self)
		if not Tooltips() then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Totem Twisting", 1, 1, 1)
		local partner = SP.GetTwistTotemName and SP:GetTwistTotemName() or "Grace of Air"
		GameTooltip:AddLine("Enable Air totem twisting (Windfury + " .. partner .. ")", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	row.twist:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Earth Shield target
	local es = CreateFrame("Button", nil, row)
	es:SetSize(44, CELL_H)
	es:SetPoint("LEFT", row, "LEFT", NAME_W + 4, 0)
	es.row = row
	es.bg = es:CreateTexture(nil, "BACKGROUND")
	es.bg:SetAllPoints(es)
	es.bg:SetColorTexture(0.30, 0.65, 0.35, 0.10)
	Core:MakeBorder(es, "borderSoft")
	es.icon = es:CreateTexture(nil, "ARTWORK")
	es.icon:SetSize(26, 26)
	es.icon:SetPoint("TOP", es, "TOP", 0, -4)
	es.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	es.icon:SetTexture(SP.EarthShield and SP.EarthShield.icon or "Interface\\Icons\\Spell_Nature_SkinOfEarth")
	es.text = es:CreateFontString(nil, "OVERLAY")
	es.text:SetFontObject(Core.fonts.tiny)
	es.text:SetPoint("BOTTOM", es, "BOTTOM", 0, 4)
	es.text:SetWidth(ES_W - 6)
	es.text:SetJustifyH("CENTER")
	es:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	es:SetScript("OnClick", EsOnClick)
	es:SetScript("OnEnter", function(self)
		if self._control then Core:SetBorderColor(self, "on") end
		if not Tooltips() then return end
		local target = ShamanPower_EarthShieldAssignments and ShamanPower_EarthShieldAssignments[self.row.name]
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Earth Shield", 1, 1, 1)
		GameTooltip:AddLine(target and ("Target: " .. target) or "No target assigned", 0.6, 0.65, 0.72)
		if self._control then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Left-click: choose target", 0.8, 0.8, 0.8)
			GameTooltip:AddLine("Right-click: clear", 0.8, 0.8, 0.8)
		end
		GameTooltip:Show()
	end)
	es:SetScript("OnLeave", function(self)
		Core:SetBorderColor(self, "borderSoft")
		GameTooltip:Hide()
	end)
	row.es = es

	row.cells = {}
	for e = 1, 4 do
		row.cells[e] = MakeCell(row, e)
	end
	return row
end

local function ConfigureRow(row, name, index, inCombat)
	row.name = name
	local isSelf = (name == SP.player)
	local control = SP:CanControl(name)
	local leader = SP:CheckLeader(name)

	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", frame.body, "TOPLEFT", 0, -((index - 1) * ROW_H))
	row.selfBar:SetShown(isSelf)

	row.nameFS:SetText(name)
	if control then
		row.nameFS:SetTextColor(Core:Color("text"))
	elseif leader then
		row.nameFS:SetTextColor(Core:Color("on"))
	else
		row.nameFS:SetTextColor(Core:Color("warn"))
	end

	-- Twist
	local twisting = ShamanPower_TwistAssignments and ShamanPower_TwistAssignments[name] or false
	row.twist:Paint(twisting)
	row.twist.label:SetTextColor(Core:ColorIf(twisting, "text", "textDim"))

	-- Earth Shield
	local info = SP.AllShamans and SP.AllShamans[name]
	local hasES = info and info.hasEarthShield
	row.es._control = control and not inCombat
	if hasES then
		row.es:Show()
		local target = ShamanPower_EarthShieldAssignments and ShamanPower_EarthShieldAssignments[name]
		if target then
			row.es.text:SetText(Ambiguate and Ambiguate(target, "short") or target)
			row.es.text:SetTextColor(Core:Color("on"))
			row.es.icon:SetDesaturated(false)
		else
			row.es.text:SetText("assign")
			row.es.text:SetTextColor(Core:Color("textMute"))
			row.es.icon:SetDesaturated(true)
		end
		row.es:SetAlpha(row.es._control and 1 or 0.55)
	else
		row.es:Hide()
	end

	-- Cells
	local a = ShamanPower_Assignments and ShamanPower_Assignments[name] or {}
	for e = 1, 4 do
		local cell = row.cells[e]
		local idx = a[e] or 0
		local icon = idx > 0 and SP.TotemIcons and SP.TotemIcons[e] and SP.TotemIcons[e][idx]
		if icon then
			cell.icon:SetTexture(icon)
			cell.icon:Show()
			cell.empty:Hide()
		else
			cell.icon:Hide()
			cell.empty:Show()
		end
		cell._control = control and not inCombat
		cell:SetAlpha(cell._control and 1 or 0.55)
	end
	row:Show()
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------
local function SavePosition()
	local o = Opt()
	local point, _, relPoint, x, y = frame:GetPoint(1)
	if point then
		o.assignWindowPos = { point = point, relPoint = relPoint, x = x, y = y }
	end
end

local function RestorePosition()
	local pos = Opt().assignWindowPos
	frame:ClearAllPoints()
	if pos and pos.point then
		frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
end

local function BuildFrame()
	if frame then return frame end

	frame = CreateFrame("Frame", "ShamanPowerAssignFrame", UIParent)
	frame:SetSize(WIN_W, HEADER_H + COLHEAD_H + ROW_H + FOOTER_H)
	-- Saved position is in frame units: apply the saved scale before it.
	frame:SetScale(Opt().configscale or 0.9)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	frame:Hide()
	tinsert(UISpecialFrames, "ShamanPowerAssignFrame")

	Core:SolidTex(frame, "windowBg", "BACKGROUND", nil, true)
	-- 2px accent frame so the two windows read as separate panels when overlapped.
	Core:MakeBorder(frame, "accent", 2)

	-- Header band -----------------------------------------------------------
	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
	header:SetHeight(HEADER_H)
	Core:SolidTex(header, "sidebarBg", "BACKGROUND", nil, true)

	local brand = header:CreateFontString(nil, "OVERLAY")
	brand:SetFontObject(Core.fonts.brand)
	brand:SetPoint("LEFT", header, "LEFT", PAD, 6)
	brand:SetText("|cff0070ddShaman|r|cffE6EAF0Power|r")

	local sub = header:CreateFontString(nil, "OVERLAY")
	sub:SetFontObject(Core.fonts.tiny)
	sub:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 1, -2)
	sub:SetText("TOTEM ASSIGNMENTS")

	local glow = Core:AccentGlow(frame, 2)
	glow:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -(HEADER_H + 1))
	glow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -(HEADER_H + 1))

	-- Close
	local close = CreateFrame("Button", nil, frame)
	close:SetSize(22, 22)
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
	Core:MakeBorder(close, "border")
	local closeTxt = close:CreateFontString(nil, "OVERLAY")
	closeTxt:SetFontObject(Core.fonts.row)
	closeTxt:SetPoint("CENTER")
	closeTxt:SetText("X")
	closeTxt:SetTextColor(Core:Color("textDim"))
	close:SetScript("OnEnter", function()
		Core:SetBorderColor(close, "warn"); closeTxt:SetTextColor(Core:Color("warn"))
	end)
	close:SetScript("OnLeave", function()
		Core:SetBorderColor(close, "border"); closeTxt:SetTextColor(Core:Color("textDim"))
	end)
	close:SetScript("OnClick", function() Assign:Hide() end)

	-- Free Assignment
	local pill = MakePill(header)
	pill:SetPoint("RIGHT", close, "LEFT", -18, -6)
	local pillLabel = header:CreateFontString(nil, "OVERLAY")
	pillLabel:SetFontObject(Core.fonts.rowDim)
	pillLabel:SetPoint("RIGHT", pill, "LEFT", -8, 0)
	pillLabel:SetText(SHAMANPOWER_FREEASSIGN or "Free Assignment")
	pill:SetScript("OnClick", function(self)
		local o = Opt()
		o.freeassign = not o.freeassign
		local me = SP.AllShamans and SP.AllShamans[SP.player]
		if o.freeassign then
			SP:SendMessage("FREEASSIGN YES")
			if me then me.freeassign = true end
		else
			SP:SendMessage("FREEASSIGN NO")
			if me then me.freeassign = false end
		end
		self:Paint(o.freeassign)
		MarkDirty()
	end)
	Core:AttachTooltip(pill, SHAMANPOWER_FREEASSIGN or "Free Assignment",
		SHAMANPOWER_FREEASSIGN_DESC or "Allow others to change your assignments without leader/assist")
	frame.pill = pill

	-- Column headers --------------------------------------------------------
	local colhead = CreateFrame("Frame", nil, frame)
	colhead:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEADER_H + 4))
	colhead:SetSize(WIN_W - PAD * 2, COLHEAD_H)

	local shamanLbl = colhead:CreateFontString(nil, "OVERLAY")
	shamanLbl:SetFontObject(Core.fonts.section)
	shamanLbl:SetPoint("BOTTOMLEFT", colhead, "BOTTOMLEFT", 12, 6)
	shamanLbl:SetText("SHAMAN")

	local esLbl = colhead:CreateFontString(nil, "OVERLAY")
	esLbl:SetFontObject(Core.fonts.section)
	esLbl:SetPoint("BOTTOM", colhead, "BOTTOMLEFT", NAME_W + 4 + 22, 6)
	esLbl:SetText("ES")

	for e = 1, 4 do
		local el = ELEMENTS[e]
		local l = colhead:CreateFontString(nil, "OVERLAY")
		l:SetFontObject(Core.fonts.section)
		l:SetPoint("BOTTOM", colhead, "BOTTOMLEFT", CellX(e) + CELL_W / 2, 6)
		l:SetText(strupper(el.label))
		l:SetTextColor(el.r, el.g, el.b)
	end

	local rule = colhead:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	rule:SetPoint("BOTTOMLEFT", colhead, "BOTTOMLEFT", 0, 0)
	rule:SetPoint("BOTTOMRIGHT", colhead, "BOTTOMRIGHT", 0, 0)
	rule:SetColorTexture(Core:Color("border", 0.6))

	-- Body (scrolls past MAX_ROWS) ---------------------------------------------
	local scroll = CreateFrame("ScrollFrame", nil, frame)
	scroll:SetPoint("TOPLEFT", colhead, "BOTTOMLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, FOOTER_H)
	local body = CreateFrame("Frame", nil, scroll)
	body:SetSize(WIN_W - PAD * 2, ROW_H)
	scroll:SetScrollChild(body)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local maxS = math.max(0, body:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.max(0, math.min(maxS, self:GetVerticalScroll() - delta * ROW_H)))
	end)
	frame.scroll, frame.body = scroll, body
	Core:AttachScrollbar(scroll, body, { offset = 4 })

	local empty = body:CreateFontString(nil, "OVERLAY")
	empty:SetFontObject(Core.fonts.rowDim)
	empty:SetPoint("CENTER", scroll, "CENTER", 0, 0)
	empty:Hide()
	frame.empty = empty

	-- Footer ----------------------------------------------------------------
	local footRule = frame:CreateTexture(nil, "ARTWORK")
	footRule:SetHeight(1)
	footRule:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, FOOTER_H)
	footRule:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, FOOTER_H)
	footRule:SetColorTexture(Core:Color("border"))

	local tools = FooterButton(frame, "Tools", 70, false)
	tools:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 11)
	tools:SetScript("OnClick", function(self)
		Widgets:ShowPopup(self, {
			{ key = "range",   text = "Totem Range" },
			{ key = "raidcd",  text = "Raid CDs" },
			{ key = "es",      text = "ES Tracker" },
			{ key = "options", text = "Options" },
		}, nil, function(key)
			if key == "range" then
				if SP.InitSPRange then SP:InitSPRange() end
				if SP.CreateSPRangeFrame then SP:CreateSPRangeFrame() end
				if SP.ShowSPRangeConfig then SP:ShowSPRangeConfig() end
			elseif key == "raidcd" then
				if SP.ToggleRaidCooldownPanel then SP:ToggleRaidCooldownPanel() end
			elseif key == "es" then
				if SP.ToggleESTracker then SP:ToggleESTracker() end
			elseif key == "options" then
				if ns.SPConfig and ns.SPConfig.Toggle then ns.SPConfig:Toggle() else SP:OpenConfigWindow() end
			end
		end, { above = true, width = 160 })
	end)
	Core:AttachTooltip(tools, "Tools", "Trackers and options")

	local auto = FooterButton(frame, "Auto-Assign", 100, true)
	auto:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 11)
	auto:SetScript("OnClick", function()
		if CombatBlocked() then return end
		SP:AutoAssign()
		MarkDirty()
	end)
	Core:AttachTooltip(auto, "Auto-Assign", (SHAMANPOWER_AUTOASSIGN_DESC or "") .. "\nLeader or assist only when grouped.")

	local clear = FooterButton(frame, "Clear", 70, false)
	clear:SetPoint("RIGHT", auto, "LEFT", -8, 0)
	clear:SetScript("OnClick", function()
		if CombatBlocked() then return end
		ShamanPower_ClearAssignments()
		MarkDirty()
	end)
	Core:AttachTooltip(clear, "Clear", SHAMANPOWER_CLEAR_DESC)

	local refresh = FooterButton(frame, "Refresh", 76, false)
	refresh:SetPoint("RIGHT", clear, "LEFT", -8, 0)
	refresh:SetScript("OnClick", function()
		ShamanPower_RefreshAssignments()
		MarkDirty()
	end)
	Core:AttachTooltip(refresh, "Refresh", SHAMANPOWER_REFRESH_DESC)

	local combat = frame:CreateFontString(nil, "OVERLAY")
	combat:SetFontObject(Core.fonts.tiny)
	combat:SetTextColor(Core:Color("warn"))
	combat:SetPoint("LEFT", tools, "RIGHT", 14, 0)
	combat:SetText("Locked in combat")
	combat:Hide()
	frame.combat = combat

	-- Refresh: one throttled poll while shown, plus immediate redraw whenever
	-- the engine's "state changed" hook fires. The poll is what catches the
	-- writers that never call UpdateLayout (dynamic mode, respec validation).
	frame:SetScript("OnUpdate", function(self, elapsed)
		self._t = (self._t or 0) + elapsed
		if self._dirty or self._t >= 0.25 then
			self._t = 0
			self._dirty = false
			Assign:Redraw()
		end
	end)
	frame:SetScript("OnShow", function(self) self._dirty = true end)
	frame:SetScript("OnHide", function() Widgets:HidePopup() end)

	return frame
end

-- ---------------------------------------------------------------------------
-- Redraw
-- ---------------------------------------------------------------------------
function Assign:Redraw()
	if not frame or not frame:IsShown() then return end
	local o = Opt()
	local list = SP.SyncList or {}
	local n = #list
	local inCombat = InCombatLockdown()

	Core:SyncOpacity()
	local scale = o.configscale or 0.9
	if math.abs(frame:GetScale() - scale) > 0.001 then
		SP:SetFrameScaleKeepCenter(frame, scale)
		SavePosition()
	end

	for i, name in ipairs(list) do
		local row = rows[i]
		if not row then
			row = MakeRow(frame.body, i)
			rows[i] = row
		end
		ConfigureRow(row, name, i, inCombat)
	end
	for i = n + 1, #rows do
		rows[i]:Hide()
		rows[i].name = nil
	end

	local visible = math.max(1, math.min(n, MAX_ROWS))
	frame.body:SetHeight(math.max(n, 1) * ROW_H)
	frame:SetHeight(HEADER_H + 4 + COLHEAD_H + 4 + visible * ROW_H + FOOTER_H + 2)
	if n <= MAX_ROWS then frame.scroll:SetVerticalScroll(0) end

	if n == 0 then
		frame.empty:SetText(SP.player and "No shamans in your group" or "Not ready yet")
		frame.empty:Show()
	else
		frame.empty:Hide()
	end

	frame.pill:Paint(o.freeassign and true or false)
	frame.combat:SetShown(inCombat)
end

-- ---------------------------------------------------------------------------
-- Open / close
-- ---------------------------------------------------------------------------
function Assign:Show()
	BuildFrame()
	RestorePosition()
	if SP.ScanSpells then SP:ScanSpells() end
	if IsInGroup() then
		SP:SendSelf()
		SP:SendMessage("REQ")
	end
	frame:Show()
	frame:Raise()
	self:Redraw()
	if SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_OPEN then PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN) end
end

function Assign:Hide()
	if not frame then return end
	frame:Hide()
	if SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_CLOSE then PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE) end
end

function Assign:Toggle()
	if frame and frame:IsShown() then self:Hide() else self:Show() end
end

function Assign:IsShown()
	return frame and frame:IsShown() or false
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
-- Every entry point (minimap click, /sp totems, drag-handle click, keybind)
-- calls this global at call time, so defining it here routes them all to
-- this window.
function ShamanPower_ToggleAssignments()
	ShamanPowerAssign:Toggle()
end

-- Immediate redraw on the engine's de-facto state-changed hook.
if SP and type(SP.UpdateLayout) == "function" then
	hooksecurefunc(SP, "UpdateLayout", function() MarkDirty() end)
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
watcher:SetScript("OnEvent", function() MarkDirty() end)

SLASH_SHAMANPOWERASSIGN1 = "/spa"
SLASH_SHAMANPOWERASSIGN2 = "/spassign"
SlashCmdList["SHAMANPOWERASSIGN"] = function() Assign:Toggle() end

return Assign
