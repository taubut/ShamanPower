-- Loadout icon selection on the settings dialog kit. Clicks stage a choice;
-- only Okay calls the original loadout callback. The core keeps its fallback.
local _, ns = ...
local SP, Core, Widgets = ShamanPower, ns.Core, ns.Widgets
if not SP or not Core or not Widgets then return end

local secret = issecretvalue or function() return false end
local COLUMNS, ICON_SIZE, CELL, ROWS = 10, 36, 40, 8
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local dialog, catalogue
local names, filtered = {}, {}
local query, pendingIcon, callback = "", nil, nil

local function IconName(icon)
	local filename = icon
	if type(icon) == "number" then
		filename = nil
		-- Static file IDs only. FILE4637274.bin: SecretArguments = AllowedWhenUntainted.
		if C_Texture and C_Texture.GetFilenameFromFileDataID then
			local ok, value = pcall(C_Texture.GetFilenameFromFileDataID, icon)
			if ok and not secret(value) and type(value) == "string" and value ~= "" then filename = value end
		end
	end
	if type(filename) == "string" then
		return filename:match("([^\\/]+)$") or filename
	end
	return "Icon " .. tostring(icon)
end

local function BuildCatalogue()
	if catalogue then return end
	catalogue = {}
	for _, icon in ipairs(SP:GetLoadoutIconChoices()) do
		if not secret(icon) and (type(icon) == "number" or type(icon) == "string") then
			local name = IconName(icon)
			local search = name:lower()
			if type(icon) == "number" then search = search .. " " .. icon end
			local entry = { icon = icon, name = name, search = search }
			catalogue[#catalogue + 1] = entry
			names[icon] = name
		end
	end
end

local function RenderGrid()
	local firstRow = math.floor(dialog.scroll:GetVerticalScroll() / CELL)
	for index, button in ipairs(dialog.buttons) do
		local itemIndex = firstRow * COLUMNS + index
		local entry = filtered[itemIndex]
		button.entry = entry
		if entry then
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", dialog.child, "TOPLEFT", ((index - 1) % COLUMNS) * CELL,
				-(firstRow + math.floor((index - 1) / COLUMNS)) * CELL)
			button.icon:SetTexture(entry.icon)
			Core:SetBorderColor(button, entry.icon == pendingIcon and "accentHi" or "border")
			button.spTipTitle = entry.name
			button:Show()
		else
			button.spTipTitle = nil
			button:Hide()
		end
	end
end

local function FilterIcons()
	local search = query:lower()
	for index = #filtered, 1, -1 do filtered[index] = nil end
	for _, entry in ipairs(catalogue) do
		if search == "" or entry.search:find(search, 1, true) then filtered[#filtered + 1] = entry end
	end
	dialog.child:SetHeight(math.max(1, math.ceil(#filtered / COLUMNS) * CELL))
	dialog.scroll:SetVerticalScroll(0)
	dialog.count:SetText(#filtered .. " icons")
	dialog.empty:SetShown(#filtered == 0)
	RenderGrid()
	if dialog.scroll.spScrollbarUpdate then dialog.scroll.spScrollbarUpdate() end
end

local function UpdateSelection()
	dialog.selected:SetTexture(pendingIcon or QUESTION)
	dialog.selectedName:SetText(pendingIcon and (names[pendingIcon] or IconName(pendingIcon)) or "Choose an icon")
	if pendingIcon then dialog.okay:Enable() else dialog.okay:Disable() end
	RenderGrid()
end

local function PickIcon(button)
	if not button.entry then return end
	pendingIcon = button.entry.icon
	UpdateSelection()
end

local function ConfirmSelection()
	local selected, apply = pendingIcon, callback
	dialog:Hide() -- clears the session before a callback can reopen the picker
	if selected and apply then apply(selected) end
end

local function CancelSelection()
	dialog:Hide()
end

local function ClearSession()
	callback, pendingIcon = nil, nil
	dialog.search.box:ClearFocus()
end

local function SearchChanged(box)
	query = box:GetText()
	FilterIcons()
end

local function SetQuery(value)
	query = value
	FilterIcons()
end

local function GetQuery()
	return query
end

local function ScrollGrid(scroll, delta)
	local limit = math.max(0, dialog.child:GetHeight() - scroll:GetHeight())
	scroll:SetVerticalScroll(math.max(0, math.min(limit, scroll:GetVerticalScroll() - delta * CELL * 3)))
end

local function CreatePicker()
	if dialog then return end
	dialog = Core:CreateDialog({ name = "ShamanPowerConfigIconPicker", width = 456, height = 598,
		title = "Choose an Icon", subtitle = "select a loadout icon", footer = 48,
		strata = "FULLSCREEN_DIALOG", special = true })
	local body = dialog.body
	dialog.search = Widgets:Input(body, { label = "Search Icons", width = 428, get = GetQuery, set = SetQuery,
		desc = "Filter by icon filename or file ID. Selection is applied only when you press Okay." })
	dialog.search.box:SetWidth(260)
	dialog.search.box:SetScript("OnTextChanged", SearchChanged)
	dialog.search.box:SetScript("OnEscapePressed", CancelSelection)
	local selected = body:CreateTexture(nil, "ARTWORK")
	selected:SetSize(64, 64)
	selected:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -48)
	dialog.selected = selected
	local selectedName = body:CreateFontString(nil, "OVERLAY")
	selectedName:SetFontObject(Core.fonts.row)
	selectedName:SetPoint("LEFT", selected, "RIGHT", 14, 0)
	selectedName:SetWidth(340)
	selectedName:SetJustifyH("LEFT")
	selectedName:SetWordWrap(true)
	dialog.selectedName = selectedName
	local scroll = CreateFrame("ScrollFrame", nil, body)
	scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -136)
	scroll:SetSize(COLUMNS * CELL, ROWS * CELL)
	scroll:EnableMouseWheel(true)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(COLUMNS * CELL, 1)
	scroll:SetScrollChild(child)
	dialog.scroll, dialog.child, dialog.buttons = scroll, child, {}
	-- Recycle the visible rows plus one clipped buffer row, independent of list size.
	for index = 1, COLUMNS * (ROWS + 1) do
		local button = CreateFrame("Button", nil, child)
		button:SetSize(ICON_SIZE, ICON_SIZE)
		Core:MakeBorder(button, "border")
		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", 1, -1); icon:SetPoint("BOTTOMRIGHT", -1, 1)
		button.icon = icon
		local highlight = button:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints(); highlight:SetColorTexture(1, 1, 1, 0.2)
		Core:AttachTooltip(button, "", nil)
		button:SetScript("OnClick", PickIcon)
		dialog.buttons[index] = button
	end
	local count = body:CreateFontString(nil, "OVERLAY")
	count:SetFontObject(Core.fonts.tiny)
	count:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -6)
	dialog.count = count
	local empty = body:CreateFontString(nil, "OVERLAY")
	empty:SetFontObject(Core.fonts.rowDim)
	empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
	empty:SetText("No matching icons.")
	empty:Hide()
	dialog.empty = empty
	scroll:SetScript("OnVerticalScroll", RenderGrid)
	scroll:SetScript("OnMouseWheel", ScrollGrid)
	Core:AttachScrollbar(scroll, child)
	local okay = Core:MakeButton(dialog, "Okay", 92, true)
	okay:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -14, 12)
	okay:SetScript("OnClick", ConfirmSelection)
	dialog.okay = okay
	local cancel = Core:MakeButton(dialog, "Cancel", 92, false)
	cancel:SetPoint("RIGHT", okay, "LEFT", -8, 0)
	cancel:SetScript("OnClick", CancelSelection)
	dialog.spOnHide = ClearSession
end

function SP:OpenConfigIconPicker(loadoutIndex, onSelected)
	BuildCatalogue()
	CreatePicker()
	callback, pendingIcon, query = nil, nil, ""
	local loadout = loadoutIndex and ShamanPower_TotemLoadouts and ShamanPower_TotemLoadouts[loadoutIndex]
	local current = loadoutIndex and loadout and loadout.icon or (not loadoutIndex and self._newLoadoutIcon)
	if not secret(current) and (type(current) == "number" or type(current) == "string") then pendingIcon = current end
	callback = onSelected
	dialog.search.box:SetText("")
	FilterIcons()
	UpdateSelection()
	dialog:ClearAllPoints()
	local settings = _G.ShamanPowerConfigUIFrame
	if settings and settings:IsShown() then dialog:SetPoint("TOPLEFT", settings, "TOPRIGHT", -2, 0)
	else dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
	dialog:Show()
end
