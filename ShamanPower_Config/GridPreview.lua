-- Settings-pane Grid copies only. Never borrow or inspect the secure row frames.
-- Other styles still use the unchanged wizard builders; the wizard never calls these.
local _, ns = ...
local Core, SP = ns.Core, ShamanPower
if not Core or not SP then return end
ns.PaneBuilders = ns.PaneBuilders or {}

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local NAMES = { "Earth", "Fire", "Water", "Air" }
local COLORS = { { 0.72, 0.52, 0.32 }, { 1, 0.36, 0.22 }, { 0.42, 0.58, 1 }, { 0.86, 0.88, 0.98 } }
local CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local SIZE, GAP = 28, 8

local function Label(parent, text)
	local label = parent:CreateFontString(nil, "OVERLAY")
	label:SetFontObject(Core.fonts.tiny)
	label:SetText(text)
	return label
end

local function Choices(element)
	local choices = {}
	local flyout = SP.totemFlyouts and SP.totemFlyouts[element]
	if flyout and (flyout.allButtons or flyout.buttons) then
		-- These are learned choices plus prebuilt talent choices. Mirror Grid's
		-- filters using Lua metadata, never attributes or protected geometry.
		for _, button in ipairs(flyout.allButtons or flyout.buttons) do
			local index = button.totemIndex
			local popped = SP.IsSingleTotemPoppedOut and SP:IsSingleTotemPoppedOut(element, index)
			local talentKnown = not button.talentSpellID or IsSpellKnown and IsSpellKnown(button.talentSpellID)
			if index ~= nil and not button.isDisabledInFlyout and talentKnown and not popped then
				choices[#choices + 1] = index
			end
		end
		return choices, false
	end
	-- No live flyout yet: show explicitly illustrative client-supported choices,
	-- not a claim about spells learned by this character.
	local limit = SP.GetTotemIndexLimit and SP:GetTotemIndexLimit(element) or 3
	for index = 1, limit do
		if not SP.TotemExistsOnClient or SP:TotemExistsOnClient(element, index) then
			choices[#choices + 1] = index
			if #choices == 3 then break end
		end
	end
	return choices, true
end

local function Icon(parent, element, index)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(SIZE, SIZE)
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
	icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
	local texture = index and index > 0 and SP:GetTotemIcon(element, index)
	icon:SetTexture(texture or SP.ElementIcons and SP.ElementIcons[element] or QUESTION)
	Core:MakeBorder(frame, "border")
	frame.icon, frame.totemIndex = icon, index
	if index == 0 then
		icon:SetAlpha(0.3)
		Label(frame, "-"):SetPoint("CENTER", frame, "CENTER", 0, 0)
	end
	return frame
end

local function Duration(frame, element)
	local opt = SP.opt
	local position = opt.durationBarPosition or "bottom"
	local vertical = position == "left" or position == "right"
		or position == "top_vert" or position == "bottom_vert"
	local size = opt.durationBarHeight or 3
	local host = CreateFrame("Frame", nil, frame)
	host:SetSize(vertical and size or SIZE, vertical and SIZE or size)
	if position == "top" or position == "top_vert" then
		host:SetPoint("BOTTOM", frame, "TOP", 0, 1)
	elseif position == "left" then
		host:SetPoint("RIGHT", frame, "LEFT", -1, 0)
	elseif position == "right" then
		host:SetPoint("LEFT", frame, "RIGHT", 1, 0)
	else
		host:SetPoint("TOP", frame, "BOTTOM", 0, -1)
	end
	if position ~= "none" then
		local bg = host:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(host)
		bg:SetColorTexture(0, 0, 0, 0.65)
		local fill = host:CreateTexture(nil, "ARTWORK")
		local color = SP.DurationBarColors and SP.DurationBarColors[element] or COLORS[element]
		fill:SetColorTexture(color[1], color[2], color[3], 0.95)
		fill:SetSize(vertical and size or SIZE * 0.6, vertical and SIZE * 0.6 or size)
		fill:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
	end
	local location = opt.durationTextLocation or "none"
	if location ~= "none" then
		local label = Label(frame, "45")
		label:SetFont("Fonts\\FRIZQT__.TTF", opt.durationTextSize or 8, "OUTLINE")
		if location == "icon" then label:SetPoint("CENTER", frame, "CENTER", 0, 0)
		elseif location == "inside_top" then label:SetPoint("TOP", host, "TOP", 0, -1)
		elseif location == "inside_bottom" then label:SetPoint("BOTTOM", host, "BOTTOM", 0, 1)
		elseif location == "above" then
			if position == "left" then label:SetPoint("RIGHT", host, "LEFT", -1, 0)
			elseif position == "right" then label:SetPoint("LEFT", host, "RIGHT", 1, 0)
			else label:SetPoint("BOTTOM", host, "TOP", 0, 1) end
		elseif position == "left" then label:SetPoint("LEFT", host, "RIGHT", 1, 0)
		elseif position == "right" then label:SetPoint("RIGHT", host, "LEFT", -1, 0)
		else label:SetPoint("TOP", host, "BOTTOM", 0, -1) end
	end
	frame.sampleDuration = host
end

local function PartyDots(frame)
	if not SP.opt.showPartyRangeDots then return end
	local size = SP.opt.partyDotSize or 5
	local position = SP.opt.partyDotPosition or "corners"
	local span = 4 * size + 6
	for index, corner in ipairs(CORNERS) do
		local dot = frame:CreateTexture(nil, "OVERLAY")
		dot:SetSize(size, size)
		local along = (index - 1) * (size + 2)
		if position == "above" then dot:SetPoint("BOTTOMLEFT", frame, "TOP", along - span / 2, 2)
		elseif position == "below" then dot:SetPoint("TOPLEFT", frame, "BOTTOM", along - span / 2, -2)
		elseif position == "left" then dot:SetPoint("TOPRIGHT", frame, "LEFT", -2, span / 2 - along)
		elseif position == "right" then dot:SetPoint("TOPLEFT", frame, "RIGHT", 2, span / 2 - along)
		else dot:SetPoint(corner, frame, corner, 0, 0) end
		dot:SetColorTexture(index == 4 and 1 or 0.2, index == 4 and 0.2 or 1, 0.2, 1)
	end
end

local function BuildGrid(inner)
	local opt, rows = SP.opt, {}
	local split = opt.gridSplit == true
	local assignments = ShamanPower_Assignments and SP.player and ShamanPower_Assignments[SP.player]
	local root = CreateFrame("Frame", nil, inner)
	root:SetPoint("CENTER", inner, "CENTER", 0, 0)
	root:SetScale(opt.buffscale or 0.9)
	local illustrative = false
	for element = 1, 4 do
		if not SP.IsElementShown or SP:IsElementShown(element) then
			local choices, fallback = Choices(element)
			illustrative = illustrative or fallback
			local vertical = split and opt.gridOrientation and opt.gridOrientation[element] == "vertical"
			if not split then vertical = opt.layout == "Vertical" or opt.layout == "VerticalLeft" end
			local row = CreateFrame("Frame", nil, root)
			row.element, row.vertical, row.choices = element, vertical, choices
			row:SetSize(vertical and SIZE + 16 or (SIZE + GAP) * (#choices + 1) + 8,
				vertical and (SIZE + GAP) * (#choices + 1) + 26 or SIZE + 34)
			if split then
				local color = SP.ElementColors and SP.ElementColors[element]
				local fallbackColor = COLORS[element]
				for _, edge in pairs(Core:MakeBorder(row, "border")) do
					edge:SetColorTexture(color and color.r or fallbackColor[1], color and color.g or fallbackColor[2],
						color and color.b or fallbackColor[3], 0.9)
				end
			end
			Label(row, NAMES[element]):SetPoint("TOPLEFT", row, "TOPLEFT", 6, -4)
			local assigned = assignments and assignments[element] or 0
			local main = Icon(row, element, assigned)
			main:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -20)
			PartyDots(main)
			row.main, row.buttons = main, {}
			local activeIndex
			for index, totemIndex in ipairs(choices) do
				if totemIndex > 0 then activeIndex = index; break end
			end
			for index, totemIndex in ipairs(choices) do
				local button = Icon(row, element, totemIndex)
				button:SetPoint("TOPLEFT", main, "TOPLEFT", vertical and 0 or index * (SIZE + GAP),
					vertical and -index * (SIZE + GAP) or 0)
				if totemIndex == assigned then
					local glow = button:CreateTexture(nil, "OVERLAY")
					glow:SetAllPoints(button)
					glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
					glow:SetBlendMode("ADD")
					local color = SP.ElementColors and SP.ElementColors[element]
					local fallbackColor = COLORS[element]
					glow:SetVertexColor(color and color.r or fallbackColor[1], color and color.g or fallbackColor[2],
						color and color.b or fallbackColor[3], 1)
					button.assigned = true
				end
				if index == activeIndex then Duration(button, element) end
				row.buttons[#row.buttons + 1] = button
			end
			rows[#rows + 1] = row
		end
	end
	local width, height = 0, 0
	-- Split placement is illustrative; never read/reparent the real pop-out frames.
	local verticalLayout = opt.layout == "Vertical" or opt.layout == "VerticalLeft"
	local columns = split and 2 or verticalLayout and #rows or 1
	local columnWidth, rowHeight = 0, 0
	for _, row in ipairs(rows) do
		columnWidth = math.max(columnWidth, row:GetWidth())
		rowHeight = math.max(rowHeight, row:GetHeight())
	end
	for index, row in ipairs(rows) do
		local column = (index - 1) % columns
		local line = math.floor((index - 1) / columns)
		row:SetPoint("TOPLEFT", root, "TOPLEFT", column * (columnWidth + GAP), -line * (rowHeight + GAP))
		width = math.max(width, column * (columnWidth + GAP) + row:GetWidth())
		height = math.max(height, line * (rowHeight + GAP) + row:GetHeight())
	end
	root:SetSize(math.max(width, 220), math.max(height, 40) + 30)
	local note = #rows == 0 and "No elements enabled or learned." or "Sample lifetime / party dots; glow = assigned."
	if illustrative then note = "Illustrative choices; no live flyout yet." end
	if split then note = note .. " Split positions illustrative." end
	local caption = Label(root, note)
	caption:SetPoint("BOTTOM", root, "BOTTOM", 0, 0)
	caption:SetWidth(root:GetWidth())
	inner.gridMock, root.rows = root, rows
end

-- The setup tour's Totem Bar step mounts the same mock for its Grid style.
ns.PaneBuilders.BuildGridMock = BuildGrid

function ns.PaneBuilders.BuildTotemBarPane(card, inner, y)
	if SP.GridActive and SP:GridActive() then return BuildGrid(inner) end
	return SP.Wizard.BuildTotemBarStep(card, inner, y)
end

function ns.PaneBuilders.BuildDurationBarsPane(card, inner, y)
	if SP.GridActive and SP:GridActive() then return BuildGrid(inner) end
	return SP.Wizard.BuildDurationBarsStep(card, inner, y)
end
