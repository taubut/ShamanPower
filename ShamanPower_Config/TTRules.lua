-- ShamanPower_Config :: TTRules
-- Target Tracker's Rules card (D45, 2026-10-02): one line per rule, "In [place]
-- fighting [who] -> [part]", its three dropdowns in the settings rows' look (Widgets'
-- dropdown: navy, 1 px border, "v"; a long name wraps, the line grows) opening the
-- shared list popup (Widgets:ShowPopup), an x that removes the rule, and Add Rule
-- with a note beside it (WoW: Forever only). Picking "A Target You Name..." asks for
-- the name in ShamanPower's own dialog (SP:ShowSPDialog).
--
-- The rules and their lists come from the module (SP:TT_Rules, TT_RulePlaces,
-- TT_RuleWho, TT_RuleParts, TT_RuleText; ShamanPower_TargetTracker loads after this
-- file, or not at all): without them the card draws nothing.
local _, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not (Core and SP) then return end

local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil

local PAD_X       = 12    -- the settings rows' inner padding (plus a card's inset: Widgets.CARD_INSET)
local PAD_TOP     = 10
local PAD_BOTTOM  = 12
local ROW_GAP     = 6     -- the settings rows' gap (Widgets.ROW_GAP)
local CAPTION_GAP = 10
local RULE_H      = 30    -- a rule's line
local RULE_GAP    = 6
local DD_H        = 22    -- a dropdown (Widgets' DROPDOWN_H)
local DD_MAX_W    = 200
local DD_TEXT_PAD = 28    -- its text: 8 in from the left, 20 kept for the "v"
local WORD_GAP    = 10
local X_SIZE      = 16
local ADD_W       = 110
local NOTE_GAP    = 14
local CAPTION = "Turn one of these on or off by itself in a place or against a boss. Example: in Molten Core, fighting"
	.. " Shazzrah, turn the Purge Reminder on."
local NOTE_FOREVER = "On WoW: Forever a boss rule turns on at the pull; a rule that names a target works in the open world."
local NAME_DIALOG = "SPTargetTrackerRuleName"
local FIELDS = { "place", "who", "part" }

local Rules = { rows = {}, sig = nil }
ns.CustomRows.ttRules = Rules

local function Loaded() return type(SP.TT_Rules) == "function" end

-- one of the module's functions, if it has it (nil when it does not)
local function TT(name, ...)
	local fn = SP[name]
	if type(fn) ~= "function" then return nil end
	return fn(SP, ...)
end

local function RuleList()
	local list = TT("TT_Rules")
	if type(list) ~= "table" then return {} end
	return list
end

local function TextOf(items, key)
	if type(items) == "table" then
		for _, it in ipairs(items) do
			if it.key == key then return it.text end
		end
	end
	return nil
end

-- the three texts a rule shows: the module's words, else its lists' names
local function RuleTexts(rule)
	local a, b, c = TT("TT_RuleText", rule)
	if type(a) == "table" then a, b, c = a[1] or a.place, a[2] or a.who, a[3] or a.part end
	if a == nil then a = TextOf(TT("TT_RulePlaces"), rule.place) end
	if b == nil then
		if rule.who == "name" and rule.name and rule.name ~= "" then b = rule.name
		else b = TextOf(TT("TT_RuleWho", rule.place), rule.who) end
	end
	if c == nil then c = TextOf(TT("TT_RuleParts"), rule.part) end
	return tostring(a or rule.place or ""), tostring(b or rule.who or ""), tostring(c or rule.part or "")
end

-- what the card shows, as one string: a change from anywhere else draws it again
local function Signature(list)
	local parts = {}
	for i, r in ipairs(list) do
		parts[i] = tostring(r.place) .. "|" .. tostring(r.who) .. "|" .. tostring(r.name) .. "|" .. tostring(r.part)
	end
	return table.concat(parts, "\n")
end

-- the page lays itself out again: a rule's line can change height, the card's
-- number of lines its length
local function Relayout()
	local cfg = _G.ShamanPowerConfig
	if cfg and cfg.RefreshCurrent then cfg:RefreshCurrent() end
end

local function HideList()
	local p = _G.ShamanPowerConfigDropdownPopup
	if p and p:IsShown() and p.owner and p.owner.spRuleField then p:Hide() end
end
-- the name dialog (if it is up) closes when the list of rules changes under it
local function HideName()
	if SP.HideSPDialog then SP:HideSPDialog(NAME_DIALOG) end
end

-- ---------------------------------------------------------------------------
-- A target you name
-- ---------------------------------------------------------------------------
-- the rule itself is kept, not its line number: a rule removed above it while the dialog
-- is up moves it up the list
local function AskName(i)
	local rule = RuleList()[i]
	if not (rule and SP.ShowSPDialog) then return end
	local text = "Type the name of the enemy this rule is for, as the game shows it. The rule applies while that"
		.. " enemy is your target."
	if SPCompat and SPCompat.FOREVER then
		text = text .. " On WoW: Forever the game hides names in dungeons and raids, so this only works in the open world."
	end
	SP:ShowSPDialog({
		key = NAME_DIALOG,
		title = "A Target You Name",
		text = text,
		input = { text = (rule.who == "name" and rule.name) or "", maxLetters = 60 },
		buttons = {
			{ text = "Save", onClick = function(dialog)
				local name = strtrim(dialog:GetInput() or "")
				if name == "" then return true end   -- nothing typed: the dialog stays
				local at
				for j, r in ipairs(RuleList()) do
					if r == rule then at = j break end
				end
				if not at then return end   -- the rule was removed meanwhile
				TT("TT_SetRule", at, "name", name)
				TT("TT_SetRule", at, "who", "name")
				Relayout()
			end },
			{ text = "Cancel" },
		},
	})
end

-- ---------------------------------------------------------------------------
-- A rule's line
-- ---------------------------------------------------------------------------
local function InList(items, key)
	return TextOf(items, key) ~= nil
end

-- the place list with the general places first (Any Raid, Any Dungeon, Battlegrounds,
-- Arenas, Open World: what most rules use), then every raid and dungeon of the game: the
-- list opens at its top and scrolls by the wheel, and it is 50+ places long. Made once
-- per list the module hands out.
local placeSrc, placeList
local function PlaceItems()
	local src = TT("TT_RulePlaces")
	if type(src) ~= "table" then return nil end
	if src ~= placeSrc or #placeList ~= #src then
		local out = {}
		for pass = 1, 2 do
			for _, it in ipairs(src) do
				local isMap = type(it.key) == "string" and it.key:find("^map:") ~= nil
				if isMap == (pass == 2) then out[#out + 1] = it end
			end
		end
		placeSrc, placeList = src, out
	end
	return placeList
end

local function Pick(i, field, key)
	if field == "who" and key == "name" then
		AskName(i)
		return
	end
	TT("TT_SetRule", i, field, key)
	if field == "place" then
		-- who you fight must be there: a boss of another place becomes Any Boss (or the place's first choice)
		local rule = RuleList()[i]
		local who = TT("TT_RuleWho", key)
		if rule and type(who) == "table" and who[1] and not InList(who, rule.who) then
			TT("TT_SetRule", i, "who", InList(who, "anyboss") and "anyboss" or who[1].key)
		end
	end
	Relayout()
end

local function OpenList(b)
	local p = _G.ShamanPowerConfigDropdownPopup
	if p and p:IsShown() and p.owner == b then p:Hide() return end
	local i = b.row.index
	local rule = RuleList()[i]
	if not rule then return end
	local items, cur
	if b.spRuleField == "place" then items, cur = PlaceItems(), rule.place
	elseif b.spRuleField == "who" then items, cur = TT("TT_RuleWho", rule.place), rule.who
	else items, cur = TT("TT_RuleParts"), rule.part end
	if type(items) ~= "table" or #items == 0 then return end
	local field = b.spRuleField
	ns.Widgets:ShowPopup(b, items, cur, function(key) Pick(i, field, key) end)
end

-- a dropdown button in the kit's look (Widgets CreateDropdown: navy, 1 px border, "v")
local function NewDropdown(row, field)
	local b = CreateFrame("Button", nil, row)
	b:SetHeight(DD_H)
	Core:SolidTex(b, "windowBg", "BACKGROUND")
	Core:MakeBorder(b, "border")
	b.txt = b:CreateFontString(nil, "OVERLAY")
	b.txt:SetFontObject(Core.fonts.row)
	b.txt:SetPoint("LEFT", b, "LEFT", 8, 0)
	b.txt:SetJustifyH("LEFT")
	b.txt:SetWordWrap(true)
	b.txt:SetNonSpaceWrap(true)   -- a single long word breaks, not cuts
	local arrow = b:CreateFontString(nil, "OVERLAY")
	arrow:SetFontObject(Core.fonts.tiny)
	arrow:SetPoint("RIGHT", b, "RIGHT", -7, 0)
	arrow:SetText("v")
	arrow:SetTextColor(Core:Color("textDim"))
	b.row, b.spRuleField = row, field
	b:SetScript("OnEnter", function(self) Core:SetBorderColor(self, "accent") end)
	b:SetScript("OnLeave", function(self) Core:SetBorderColor(self, "border") end)
	b:SetScript("OnClick", OpenList)
	return b
end

local function Word(parent, text)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(Core.fonts.rowDim)
	fs:SetText(text)
	return fs
end

local function NewRuleRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row.inW = Word(row, "In")
	row.fightW = Word(row, "fighting")
	row.arrowW = Word(row, "->")
	row.place = NewDropdown(row, "place")
	row.who = NewDropdown(row, "who")
	row.part = NewDropdown(row, "part")
	row.inW:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.place:SetPoint("LEFT", row.inW, "RIGHT", WORD_GAP, 0)
	row.fightW:SetPoint("LEFT", row.place, "RIGHT", WORD_GAP, 0)
	row.who:SetPoint("LEFT", row.fightW, "RIGHT", WORD_GAP, 0)
	row.arrowW:SetPoint("LEFT", row.who, "RIGHT", WORD_GAP, 0)
	row.part:SetPoint("LEFT", row.arrowW, "RIGHT", WORD_GAP, 0)
	row.x = Core:CloseButton(row, X_SIZE)
	row.x:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.x:SetScript("OnClick", function()
		HideList()
		HideName()
		TT("TT_RemoveRule", row.index)
		Relayout()
	end)
	Core:AttachTooltip(row.x, "Remove This Rule", nil)
	return row
end

-- ---------------------------------------------------------------------------
-- The card (ns.CustomRows: drawn by Window.lua's page packer, released on every redraw)
-- ---------------------------------------------------------------------------
function Rules:OnSettingsChanged()
	if not (self.frame and self.frame:IsVisible()) then return end
	if Signature(RuleList()) ~= self.sig then Relayout() end
end

function Rules:Render(body, x, y, width)
	if not Loaded() then return nil, 0 end
	if ns.TargetTrackerWatch then ns.TargetTrackerWatch() end

	local f = self.frame
	if not f then
		f = CreateFrame("Frame", nil, body)
		f.caption = f:CreateFontString(nil, "OVERLAY")
		f.caption:SetFontObject(Core.fonts.rowDim)
		f.caption:SetJustifyH("LEFT")
		f.caption:SetWordWrap(true)
		f.add = Core:MakeButton(f, "Add Rule", ADD_W, false)
		f.add:SetScript("OnClick", function()
			HideList()
			HideName()
			TT("TT_AddRule")
			Relayout()
		end)
		f.note = f:CreateFontString(nil, "OVERLAY")
		f.note:SetFontObject(Core.fonts.rowDim)
		f.note:SetJustifyH("LEFT")
		f.note:SetWordWrap(true)
		self.frame = f
	end
	f:SetParent(body)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", body, "TOPLEFT", x or 0, -(y or 0))
	f:SetWidth(width)
	f:Show()

	local padX = PAD_X + (ns.Widgets and tonumber(ns.Widgets.CARD_INSET) or 0)   -- in line with the rows' labels
	local inner = width - padX * 2
	f.caption:ClearAllPoints()
	f.caption:SetPoint("TOPLEFT", f, "TOPLEFT", padX, -PAD_TOP)
	f.caption:SetWidth(inner)
	f.caption:SetText(CAPTION)
	local top = PAD_TOP + ceil(f.caption:GetStringHeight()) + CAPTION_GAP

	local list = RuleList()
	self.sig = Signature(list)
	for i, rule in ipairs(list) do
		local row = self.rows[i] or NewRuleRow(f)
		self.rows[i] = row
		row.index = i
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", f, "TOPLEFT", padX, -top)
		row:SetWidth(inner)
		-- three equal dropdowns in what the words and the x leave
		local words = row.inW:GetStringWidth() + row.fightW:GetStringWidth() + row.arrowW:GetStringWidth()
		local free = inner - words - X_SIZE - 6 * WORD_GAP - 8
		local dw = floor(min(DD_MAX_W, free / 3))
		local texts = { RuleTexts(rule) }
		local ddH = DD_H
		for n, field in ipairs(FIELDS) do
			local b = row[field]
			b:SetWidth(dw)
			b.txt:SetWidth(dw - DD_TEXT_PAD)
			b.txt:SetText(texts[n])
			ddH = max(ddH, ceil(b.txt:GetStringHeight()) + 8)   -- a long name wraps: the line grows
		end
		for _, field in ipairs(FIELDS) do row[field]:SetHeight(ddH) end
		local rh = max(RULE_H, ddH + 8)
		row:SetHeight(rh)
		row:Show()
		top = top + rh + RULE_GAP
	end
	for i = #list + 1, #self.rows do self.rows[i]:Hide() end

	f.add:ClearAllPoints()
	f.add:SetPoint("TOPLEFT", f, "TOPLEFT", padX, -(top + 4))
	local below = f.add:GetHeight()
	if SPCompat and SPCompat.FOREVER then
		f.note:ClearAllPoints()
		f.note:SetPoint("LEFT", f.add, "RIGHT", NOTE_GAP, 0)
		f.note:SetWidth(inner - f.add:GetWidth() - NOTE_GAP)
		f.note:SetText(NOTE_FOREVER)
		f.note:Show()
		below = max(below, ceil(f.note:GetStringHeight()))
	else
		f.note:Hide()
	end
	local h = top + 4 + below + PAD_BOTTOM + 2
	f:SetHeight(h)
	return f, h + ROW_GAP
end

function Rules:Release()
	HideList()
	if self.frame then self.frame:Hide() end
	for _, row in ipairs(self.rows) do Core:HideTooltipFor(row.x) end
end
