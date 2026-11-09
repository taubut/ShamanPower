-- ShamanPower_Config / SupportersPage.lua
-- Settings > Supporters: the people who support ShamanPower on Patreon. Earthen Ring
-- (the top tier) first, its names in gold, then every supporter. The names are kept
-- here and updated with each release (each one the name its supporter asked for).
-- Drawn from the design system's own primitives (Core.lua), like PatchNotesPage.lua.
local _, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not (SP and Core) then return end

local floor, max, ceil = math.floor, math.max, math.ceil
local GOLD = { 1, 0.82, 0 }   -- WoW's own gold (NORMAL_FONT_COLOR)
local PATREON = "https://www.patreon.com/cw/ShamanPower"

-- the names, A to Z within each list (updated with each release)
ns.SUPPORTERS = {
	earthenRing = {},
	supporters = {
		"Afren",
		"Zegma",
	},
}

-- the page: an option group under General (like Patch Notes), so the sidebar search
-- and SPConfig:Open({ "settings", "settings_supporters" }) find it; Window.lua draws
-- this page in place of the group's rows
do
	local settings = SP.options and SP.options.args and SP.options.args.settings
	if settings and settings.args and not settings.args.settings_supporters then
		settings.args.settings_supporters = {
			order = 100, type = "group", inline = true, name = "Supporters",
			args = {
				intro = { order = 1, type = "description", name = "The people who support ShamanPower on Patreon.",
					desc = "supporters patreon thanks credits earthen ring donate support" },
			},
		}
	end
end

local Page = {}
ns.SupportersPage = Page

local store, shown = {}, {}
local page = {}

local function Keep(key, make)
	local f = store[key]
	if not f then
		f = make()
		store[key] = f
	end
	f:SetParent(page.body)
	f:ClearAllPoints()
	f:Show()
	shown[#shown + 1] = f
	return f
end

local function Text(parent, font, colorKey)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(Core.fonts[font])
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(true)
	if colorKey then fs:SetTextColor(Core:Color(colorKey)) end
	return fs
end

local function Sorted(list)
	local out = {}
	for i, n in ipairs(list or {}) do out[i] = n end
	table.sort(out, function(a, b) return a:lower() < b:lower() end)
	return out
end

-- a small-caps section label with a rule to the right (EARTHEN RING / SUPPORTERS)
local function Label(key, y, W, text)
	local f = Keep("label:" .. key, function()
		local l = CreateFrame("Frame", nil, page.body)
		l.text = Text(l, "section", "accentHi"); l.text:SetPoint("LEFT", l, "LEFT", 0, 0); l.text:SetWordWrap(false)
		l.line = l:CreateTexture(nil, "ARTWORK"); l.line:SetHeight(1); l.line:SetColorTexture(Core:Color("border"))
		l.line:SetPoint("LEFT", l.text, "RIGHT", 8, 0); l.line:SetPoint("RIGHT", l, "RIGHT", 0, 0)
		return l
	end)
	f.text:SetText(text)
	f:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
	f:SetSize(W, 14)
	return 22
end

-- the names in columns inside a card, the four elements along its top; gold: the
-- Earthen Ring card (its names in WoW's gold). A name too long for its column wraps
-- onto more lines (never "...", even one long word) and its row grows to fit it.
local function Names(key, y, W, names, gold)
	local cols, rowH = 4, 20
	local card = Keep("card:" .. key, function()
		local c = CreateFrame("Frame", nil, page.body)
		c.bg = c:CreateTexture(nil, "BACKGROUND"); c.bg:SetAllPoints(c)
		Core:MakeBorder(c, "borderSoft")
		c.stripe = {}
		local els = SP.Brand.elements
		for i, el in ipairs({ "earth", "fire", "water", "air" }) do
			local t = c:CreateTexture(nil, "ARTWORK"); t:SetHeight(2)
			t:SetColorTexture(els[el][1], els[el][2], els[el][3], 1)
			c.stripe[i] = t
		end
		c.names = {}
		return c
	end)
	card:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
	card.bg:SetColorTexture(Core:Color("rowBg"))
	for i, t in ipairs(card.stripe) do
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", card, "TOPLEFT", (i - 1) * W / 4, 0)
		t:SetWidth(W / 4)
	end
	local colW = floor((W - 32) / cols)
	local top, tallest = 14, rowH                         -- this row's top, and its tallest name so far
	for i, name in ipairs(names) do
		local fs = card.names[i]
		if not fs then
			fs = Text(card, "row"); fs:SetNonSpaceWrap(true)
			card.names[i] = fs
		end
		if gold then fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) else fs:SetTextColor(Core:Color("text")) end
		local col = (i - 1) % cols
		if col == 0 and i > 1 then top, tallest = top + tallest, rowH end
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", card, "TOPLEFT", 16 + col * colW, -top)
		fs:SetWidth(colW - 8)
		fs:SetText(name)
		fs:Show()
		tallest = max(tallest, ceil(fs:GetStringHeight()) + 6)
	end
	for i = #names + 1, #card.names do card.names[i]:Hide() end
	local h = top + tallest + 10
	card:SetSize(W, h)
	return h
end

-- one line in a card (an empty list, or the lead)
local function Line(key, y, W, text, colorKey)
	local f = Keep("line:" .. key, function()
		local l = CreateFrame("Frame", nil, page.body)
		l.text = Text(l, "rowDim"); l.text:SetPoint("TOPLEFT", l, "TOPLEFT", 0, 0)
		return l
	end)
	f.text:SetWidth(W)
	f.text:SetText(text)
	f.text:SetTextColor(Core:Color(colorKey or "textDim"))
	f:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
	f:SetSize(W, max(16, ceil(f.text:GetStringHeight())))
	return f:GetHeight()
end

function Page:Render(body, W)
	page.body = body
	self:Release()
	local list = ns.SUPPORTERS or {}
	local ring, all = Sorted(list.earthenRing), Sorted(list.supporters)
	local y = 0

	-- the lead and the Patreon button beside it
	local btn = Keep("btn:patreon", function()
		local b = Core:MakeButton(page.body, "Support on Patreon", 160, true)
		b:SetScript("OnClick", function()
			SP:ShowSPDialog({ key = "patreonLink", title = "Support ShamanPower on Patreon", editText = PATREON,
				text = "Press |cffFFD100Ctrl+C|r to copy it, then paste it into your browser." })
		end)
		return b
	end)
	btn:SetPoint("TOPRIGHT", body, "TOPLEFT", W, -y)
	y = y + max(Line("lead", y, W - 180, "ShamanPower is free for every shaman, and it always will be. These people"
		.. " support it on Patreon and keep it going. Thank you!", "text"), 26) + 18

	-- Earthen Ring: the top tier, first, its names in gold (only once someone is in it)
	if #ring > 0 then
		y = y + Label("ring", y, W, "EARTHEN RING")
		y = y + Names("ring", y, W, ring, true) + 18
	end

	-- every other supporter; with nobody at all, the one empty line
	if #all > 0 then
		y = y + Label("all", y, W, "SUPPORTERS")
		y = y + Names("all", y, W, all, false) + 10
	elseif #ring == 0 then
		y = y + Label("all", y, W, "SUPPORTERS")
		y = y + Line("allNone", y, W, "No supporters yet. You could be the first.") + 10
	end
	return y
end

function Page:Release()
	for i = #shown, 1, -1 do
		shown[i]:Hide()
		shown[i] = nil
	end
end

function Page:IsShown()
	return #shown > 0
end
