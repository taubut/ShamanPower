-- Settings-pane copies only: never borrow the secure loadout anchor/buttons.
-- These builders are deliberately separate from the first-run wizard.
local _, ns = ...
local Core, SP = ns.Core, ShamanPower
if not Core or not SP then return end
ns.PaneBuilders = ns.PaneBuilders or {}

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local SHAMAN = "Interface\\Icons\\ClassIcon_Shaman"
local SUMMON = { 66842, 66843, 66844 }
local PAGE_NAMES = { "Elements", "Ancestors", "Spirits" }
local ELEMENT_ORDER = { 2, 1, 3, 4 } -- Blizzard's Fire / Earth / Water / Air slots.
local CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local LOCATIONS = { { "BOTTOM", "TOP" }, { "BOTTOMLEFT", "TOPRIGHT" }, { "LEFT", "RIGHT" } }
local SAMPLES = {
	{ name = "Sample 1", 2, 2, 1, 1 },
	{ name = "Sample 2", 1, 2, 2, 2 },
	{ name = "Sample 3", 2, 5, 1, 4 },
}

local function HasSets()
	return WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and SP.HasTotemBar and SP:HasTotemBar()
end

local function TotemIcon(element, index)
	if not index or index <= 0 then return QUESTION end
	if SP.TotemExistsOnClient and not SP:TotemExistsOnClient(element, index) then return QUESTION end
	return SP:GetTotemIcon(element, index) or QUESTION
end

local function LoadoutIcon(loadout)
	if not loadout then return SHAMAN end
	if loadout.icon then return loadout.icon end
	for element = 1, 4 do
		if (loadout[element] or 0) > 0 then return TotemIcon(element, loadout[element]) end
	end
	return SHAMAN
end

local function Label(parent, text, font)
	local label = parent:CreateFontString(nil, "OVERLAY")
	label:SetFontObject(font or Core.fonts.row)
	label:SetText(text)
	return label
end

local function Icon(parent, texture, size)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(size, size)
	local border = frame:CreateTexture(nil, "BORDER")
	border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	border:SetSize(size * 52 / 32, size * 52 / 32)
	border:SetPoint("CENTER", frame, "CENTER", 0, -1)
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(frame)
	icon:SetTexture(texture)
	frame.icon = icon
	return frame
end

local function PageTag(frame, page)
	if page ~= 2 and page ~= 3 then return end
	local tag = Label(frame, tostring(page), Core.fonts.button)
	tag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
	tag:SetTextColor(1, 0.82, 0)
	frame.pageTag = tag
end

local function MiniTotems(frame, loadout)
	frame.icon:SetAlpha(0.3)
	for element = 1, 4 do
		local icon = frame:CreateTexture(nil, "OVERLAY")
		icon:SetSize(13, 13)
		local corner = CORNERS[element]
		icon:SetPoint(corner, frame, corner, element % 2 == 1 and 3 or -3, element <= 2 and -3 or 3)
		icon:SetTexture(TotemIcon(element, loadout[element]))
	end
end

local function BuildLoadout(parent, loadout, anchor, hasSets)
	local frame = Icon(parent, LoadoutIcon(loadout), 32)
	if loadout and ((anchor and SP.opt.loadoutBarShowTotems) or (not anchor and not loadout.icon)) then
		MiniTotems(frame, loadout)
	end
	if not SP.opt.loadoutBarHideNames then
		local label = Label(frame, loadout and loadout.name or "", Core.fonts.row)
		label:SetPoint("LEFT", frame, "RIGHT", 4, 0)
		label:SetJustifyH("LEFT")
	end
	if loadout and hasSets then PageTag(frame, loadout.setPage) end
	return frame
end

function ns.PaneBuilders.BuildLoadoutBarPane(_, inner)
	local opt = SP.opt
	if not opt then return end
	local root = CreateFrame("Frame", nil, inner)
	root:SetSize(260, 130)
	root:SetPoint("CENTER", inner, "CENTER", 0, 0)
	root:SetScale(opt.loadoutBarScale or 1)
	root:SetAlpha(opt.loadoutBarOpacity or 1)
	local loadouts = ShamanPower_TotemLoadouts or {}
	local active = loadouts[opt.activeLoadout]
	local hasSets = HasSets()
	local anchor = BuildLoadout(root, active, true, hasSets)
	anchor:SetPoint("CENTER", root, "CENTER", -42, -16)
	local shown = 0
	for index, loadout in ipairs(loadouts) do
		-- Same visible candidates as the live flyout; a bound active loadout
		-- still has a button because the anchor is only a hover handle.
		local bound = hasSets and SP.BoundLoadoutSummon and SP:BoundLoadoutSummon(index)
		if index ~= opt.activeLoadout or bound then
			shown = shown + 1
			local button = BuildLoadout(root, loadout, false, hasSets)
			button:SetPoint(LOCATIONS[shown][1], anchor, LOCATIONS[shown][2], 0, 0)
			if shown == 3 then break end
		end
	end
	for i = shown + 1, 3 do
		local button = BuildLoadout(root, SAMPLES[i], false, false)
		button:SetPoint(LOCATIONS[i][1], anchor, LOCATIONS[i][2], 0, 0)
	end
	local note = Label(root, "Sample flyout (always open here)", Core.fonts.tiny)
	note:SetPoint("BOTTOM", root, "BOTTOM", 0, 0)
	inner.loadoutMock = root
end

function ns.PaneBuilders.BuildLoadoutSetsPane(_, inner)
	if not SP.opt or not HasSets() then return end
	local root = CreateFrame("Frame", nil, inner)
	root:SetSize(342, 160)
	root:SetPoint("CENTER", inner, "CENTER", 0, 0)
	local assignments = ShamanPower_Assignments and SP.player and ShamanPower_Assignments[SP.player]
	local exclude = { SP.opt.excludeEarthFromDropAll, SP.opt.excludeFireFromDropAll,
		SP.opt.excludeWaterFromDropAll, SP.opt.excludeAirFromDropAll }
	local loadouts = ShamanPower_TotemLoadouts or {}
	for page = 1, 3 do
		local source = page == 1 and assignments or nil
		if page > 1 then
			for _, loadout in ipairs(loadouts) do
				if loadout.setPage == page then source = loadout; break end
			end
		end
		local spellTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
		local icon = spellTexture and spellTexture(SUMMON[page]) or QUESTION
		local call = Icon(root, icon, 32)
		call:SetPoint("TOP", root, "TOPLEFT", (page - 1) * 114 + 57, -12)
		local name = Label(root, PAGE_NAMES[page], Core.fonts.row)
		name:SetPoint("TOP", call, "BOTTOM", 0, -8)
		for slot, element in ipairs(ELEMENT_ORDER) do
			local index = source and source[element] or 0
			if page == 1 and exclude[element] then index = 0 end
			local cell = Icon(root, index > 0 and TotemIcon(element, index) or nil, 22)
			cell:SetPoint("TOPLEFT", root, "TOPLEFT", (page - 1) * 114 + 10 + (slot - 1) * 24, -76)
		end
		local caption = Label(root, page == 1 and "Assignments" or source and source.name or "Unbound", Core.fonts.tiny)
		caption:SetPoint("TOP", root, "TOPLEFT", (page - 1) * 114 + 57, -106)
		caption:SetWidth(106)
		caption:SetJustifyH("CENTER")
		if page > 1 and source then
			local loadout = Icon(root, LoadoutIcon(source), 20)
			loadout:SetPoint("TOP", caption, "BOTTOM", 0, -6)
			PageTag(loadout, page)
		end
	end
	inner.loadoutSetsMock = root
end
