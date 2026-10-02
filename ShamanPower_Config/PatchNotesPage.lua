-- ShamanPower_Config / PatchNotesPage.lua
-- Settings > Patch Notes: every version's notes (PatchNotes.lua, the same notes
-- the What's New card reads), newest first. Each version folds open and shut;
-- new features get an icon, a few words and a link that opens their setting,
-- changes and fixes are short lines. 2.x is one block holding its versions.
-- Drawn from the design system's own primitives (Core.lua), like Themes.lua.
local _, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not (SP and Core) then return end

local floor, max = math.floor, math.max
local GOLD = { 1, 0.82, 0.15 }
local ICON_TRIM = 0.08
local SHAPES = "Interface\\AddOns\\ShamanPower\\Media\\Textures\\"

-- the page: an option group under General (like Themes), so the sidebar search
-- and SPConfig:Open({ "settings", "settings_patchnotes" }) find it; Window.lua
-- draws this page in place of the group's rows
do
	local settings = SP.options and SP.options.args and SP.options.args.settings
	if settings and settings.args and not settings.args.settings_patchnotes then
		settings.args.settings_patchnotes = {
			order = 99, type = "group", inline = true, name = "Patch Notes",
			args = {
				intro = { order = 1, type = "description", name = "What changed in each version, newest first.",
					desc = "patch notes changelog what's new versions changes fixes history release" },
			},
		}
	end
end

local Page = {}
ns.PatchNotesPage = Page

local state = { open = {}, filter = "all" }   -- this session: which versions are open, the game filter
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

local function Refresh()
	if ns.SPConfig and ns.SPConfig.RefreshCurrent then ns.SPConfig:RefreshCurrent() end
end

-- A version's number in Fira Sans SemiBold (the settings window's titles). The
-- game's font where Fira is missing (a new file loads only after a full restart)
-- or on Chinese and Korean clients (SP:BrandFontPath gives the game's font there).
local function VersionFont(fs, size)
	local path = SP.BrandFontPath and SP:BrandFontPath("semibold")
	local ok, set = false, false
	if path then ok, set = pcall(fs.SetFont, fs, path, size, "") end
	if not (ok and set) then fs:SetFont("Fonts\\FRIZQT__.TTF", size, "") end
end

-- "2026-09-28" -> "Sep 28, 2026"
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local function NiceDate(iso)
	local y, mo, d = tostring(iso or ""):match("^(%d+)%-(%d+)%-(%d+)$")
	if not y then return iso or "" end
	return (MONTHS[tonumber(mo)] or mo) .. " " .. tonumber(d) .. ", " .. y
end
local function MonthYear(iso)
	local y, mo = tostring(iso or ""):match("^(%d+)%-(%d+)")
	if not y then return "" end
	return (MONTHS[tonumber(mo)] or mo) .. " " .. y
end

-- ---------------------------------------------------------------------------
-- What a version shows under the game filter and the page search
-- ---------------------------------------------------------------------------
local function ClientOK(client)
	if state.filter == "forever" then return client ~= "anniversary" end
	if state.filter == "anniversary" then return client ~= "forever" end
	return true
end
local function Matches(query, ...)
	if not query then return true end
	for i = 1, select("#", ...) do
		local s = select(i, ...)
		if type(s) == "string" and s:lower():find(query, 1, true) then return true end
	end
	return false
end
local function LineText(l) if type(l) == "table" then return l.t, l.client end return l, nil end
-- the version's items that show: new, changes, fixes (lists), or nil if none
local function Visible(ver, query)
	local whole = query and Matches(query, ver.v, ver.headline)
	local q = (not whole) and query or nil
	local new, changes, fixes = {}, {}, {}
	for _, it in ipairs(ver.new or {}) do
		if ClientOK(it.client) and (not it.when or it.when()) and Matches(q, it.h, it.b, it.s, it.path) then new[#new + 1] = it end
	end
	for _, l in ipairs(ver.changes or {}) do
		local t, c = LineText(l)
		if ClientOK(c) and Matches(q, t) then changes[#changes + 1] = l end
	end
	for _, l in ipairs(ver.fixes or {}) do
		local t, c = LineText(l)
		if ClientOK(c) and Matches(q, t) then fixes[#fixes + 1] = l end
	end
	if #new + #changes + #fixes == 0 then return nil end
	return new, changes, fixes
end
local function Plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

-- ---------------------------------------------------------------------------
-- Pieces
-- ---------------------------------------------------------------------------
-- a filter chip: the picked one filled with the accent
local function Chip(key, label, on, onClick)
	local c = Keep("chip:" .. key, function()
		local b = CreateFrame("Button", nil, page.body)
		b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(b)
		Core:MakeBorder(b, "border")
		b.text = Text(b, "rowDim"); b.text:SetPoint("CENTER", b, "CENTER", 0, 0); b.text:SetWordWrap(false)
		b.text:SetText(label)
		b:SetScript("OnEnter", function(self) if not self.on then self.bg:SetColorTexture(Core:Color("rowHover")) end end)
		b:SetScript("OnLeave", function(self) if not self.on then self.bg:SetColorTexture(Core:Color("rowBg")) end end)
		return b
	end)
	c.on = on
	c:SetSize(math.ceil(c.text:GetStringWidth()) + 22, 24)
	if on then
		c.bg:SetColorTexture(Core:Color("accent", 0.45))
		Core:SetBorderColor(c, "accentHi")
		c.text:SetTextColor(Core:Color("text"))
	else
		c.bg:SetColorTexture(Core:Color("rowBg"))
		Core:SetBorderColor(c, "border")
		c.text:SetTextColor(Core:Color("textDim"))
	end
	c:SetScript("OnClick", onClick)
	return c
end

-- a small bordered count ("9 new")
local function Count(key, parent, label)
	local c = Keep(key, function()
		local f = CreateFrame("Frame", nil, page.body)
		f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints(f); f.bg:SetColorTexture(Core:Color("windowBg"))
		Core:MakeBorder(f, "borderSoft")
		f.text = Text(f, "tiny", "textDim"); f.text:SetPoint("CENTER", f, "CENTER", 0, 0); f.text:SetWordWrap(false)
		return f
	end)
	c:SetParent(parent)
	c.text:SetText(label)
	c:SetSize(math.ceil(c.text:GetStringWidth()) + 14, 18)
	c:SetFrameLevel(parent:GetFrameLevel() + 1)
	return c
end

-- a version's bar: the chevron, the version, LATEST, the date, the headline and
-- the counts; open, it takes the gold of the What's New banner
local function Header(key, y, W, big, sub, date, headline, counts, isOpen, latest, onClick)
	local h = Keep("head:" .. key, function()
		local b = CreateFrame("Button", nil, page.body)
		b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(b)
		b.glow = b:CreateTexture(nil, "BACKGROUND", nil, 1); b.glow:SetAllPoints(b); b.glow:SetColorTexture(1, 1, 1, 1)
		Core:Gradient(b.glow, "HORIZONTAL", GOLD[1], GOLD[2], GOLD[3], 0.20, GOLD[1], GOLD[2], GOLD[3], 0.02)
		b.rule = b:CreateTexture(nil, "ARTWORK"); b.rule:SetHeight(2)
		b.rule:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0); b.rule:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
		b.rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.85)
		Core:MakeBorder(b, "borderSoft")
		b.lines = {}
		for i = 1, 2 do
			local l = b:CreateLine(nil, "OVERLAY"); l:SetThickness(2); l:SetColorTexture(1, 1, 1, 1)
			b.lines[i] = l
		end
		b.ver = b:CreateFontString(nil, "OVERLAY")
		VersionFont(b.ver, 20)
		b.ver:SetPoint("TOPLEFT", b, "TOPLEFT", 38, -9)
		b.tag = Text(b, "section"); b.tag:SetWordWrap(false); b.tag:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		b.tag:SetPoint("LEFT", b.ver, "RIGHT", 10, 0)
		b.date = Text(b, "rowDim"); b.date:SetWordWrap(false); b.date:SetJustifyH("RIGHT")
		b.date:SetPoint("TOPRIGHT", b, "TOPRIGHT", -14, -11)
		b.head = Text(b, "rowDim"); b.head:SetWordWrap(false)
		b.head:SetPoint("TOPLEFT", b.ver, "BOTTOMLEFT", 0, -5)
		b:SetScript("OnEnter", function(self) if not self.isOpen then self.bg:SetColorTexture(Core:Color("rowHover")) end end)
		b:SetScript("OnLeave", function(self) if not self.isOpen then self.bg:SetColorTexture(Core:Color("rowBg")) end end)
		return b
	end)
	h.isOpen = isOpen
	h:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, -y)
	h:SetSize(W, 58)
	h.bg:SetColorTexture(Core:Color("rowBg"))
	h.glow:SetShown(isOpen); h.rule:SetShown(isOpen)
	-- the chevron: pointing down when open, right when shut
	local a, bb = h.lines[1], h.lines[2]
	local cx, cy = 20, -22
	if isOpen then
		a:SetStartPoint("TOPLEFT", h, cx - 6, cy + 3); a:SetEndPoint("TOPLEFT", h, cx, cy - 3)
		bb:SetStartPoint("TOPLEFT", h, cx, cy - 3); bb:SetEndPoint("TOPLEFT", h, cx + 6, cy + 3)
	else
		a:SetStartPoint("TOPLEFT", h, cx - 3, cy + 6); a:SetEndPoint("TOPLEFT", h, cx + 3, cy)
		bb:SetStartPoint("TOPLEFT", h, cx + 3, cy); bb:SetEndPoint("TOPLEFT", h, cx - 3, cy - 6)
	end
	local lr, lg, lb = GOLD[1], GOLD[2], GOLD[3]
	if not isOpen then lr, lg, lb = Core:Color("textDim") end
	a:SetVertexColor(lr, lg, lb); bb:SetVertexColor(lr, lg, lb)
	VersionFont(h.ver, big and 20 or 17)
	h.ver:SetText(sub)
	if isOpen then h.ver:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) else h.ver:SetTextColor(Core:Color("text")) end
	h.tag:SetText(latest and "LATEST" or "")
	h.date:SetText(date or "")
	h.head:SetText(headline or "")
	if isOpen then h.head:SetTextColor(Core:Color("text")) else h.head:SetTextColor(Core:Color("textDim")) end
	-- the counts, right-aligned on the headline's line
	local x = W - 14
	h.head:SetWidth(max(40, W - 38 - 14))
	for i = #counts, 1, -1 do
		local c = Count("count:" .. key .. ":" .. i, h, counts[i])
		x = x - c:GetWidth()
		c:ClearAllPoints()
		c:SetPoint("TOPLEFT", h, "TOPLEFT", x, -33)
		x = x - 6
	end
	if #counts > 0 then h.head:SetWidth(max(40, x - 38 - 8)) end
	h:SetScript("OnClick", onClick)
	return 58
end

-- a small-caps section label (NEW / CHANGES / FIXES, or a 2.x version inside its block)
local function Label(key, y, x, text, colorKey, gold)
	local fs = Keep("label:" .. key, function()
		local f = CreateFrame("Frame", nil, page.body)
		f.text = Text(f, "section"); f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); f.text:SetWordWrap(false)
		return f
	end)
	fs.text:SetText(text)
	if gold then fs.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) else fs.text:SetTextColor(Core:Color(colorKey or "accentHi")) end
	fs:SetPoint("TOPLEFT", page.body, "TOPLEFT", x, -y)
	fs:SetSize(max(10, math.ceil(fs.text:GetStringWidth())), 14)
	return 18
end

-- the headline feature's picture: the bar in Circle icons with two-tone bars
local ART_ICONS = { "Interface\\Icons\\Spell_Nature_StrengthOfEarthTotem02", "Interface\\Icons\\Spell_Fire_SearingTotem",
	"Interface\\Icons\\Spell_Nature_ManaRegenTotem", "Interface\\Icons\\Spell_Nature_Windfury" }
local ART_COLORS = { { 0.682, 0.494, 0.306 }, { 0.949, 0.341, 0.208 }, { 0.400, 0.553, 0.949 }, { 0.816, 0.835, 0.929 } }
-- (the What's New card draws the same picture in its NEW box)
function ns.BuildLookArt(parent)
		local f = CreateFrame("Frame", nil, parent)
		f:SetSize(4 * 34 + 10, 64)
		local box = f:CreateTexture(nil, "BACKGROUND"); box:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		box:SetSize(4 * 34 + 10, 48); box:SetColorTexture(0, 0, 0, 0.7)
		for i = 1, 4 do
			local x = 5 + (i - 1) * 34
			local ic = f:CreateTexture(nil, "ARTWORK")
			ic:SetSize(30, 30); ic:SetPoint("TOPLEFT", f, "TOPLEFT", x, -5)
			ic:SetTexture(ART_ICONS[i]); ic:SetTexCoord(ICON_TRIM, 1 - ICON_TRIM, ICON_TRIM, 1 - ICON_TRIM)
			local m = f:CreateMaskTexture()
			m:SetAllPoints(ic)
			m:SetTexture(SHAPES .. "Mask_Circle", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			ic:AddMaskTexture(m)
			local c = ART_COLORS[i]
			local ring = f:CreateTexture(nil, "OVERLAY")
			ring:SetAllPoints(ic); ring:SetTexture(SHAPES .. "Ring_Circle_4"); ring:SetVertexColor(c[1], c[2], c[3], 1)
			local bar = f:CreateTexture(nil, "ARTWORK")
			bar:SetSize(30, 4); bar:SetPoint("TOPLEFT", f, "TOPLEFT", x, -39); bar:SetColorTexture(1, 1, 1, 1)
			Core:Gradient(bar, "HORIZONTAL", c[1], c[2], c[3], 1, GOLD[1], GOLD[2], GOLD[3], 1)
		end
		local cap = Text(f, "tiny", "textMute"); cap:SetWordWrap(false); cap:SetJustifyH("CENTER")
		cap:SetPoint("TOP", f, "TOPLEFT", (4 * 34 + 10) / 2, -52)
		cap:SetText("Circle icons, two-tone bars")
		f.cap = cap
		return f
end
local function LookArt(key)
	return Keep("art:" .. key, function() return ns.BuildLookArt(page.body) end)
end

-- one new feature: icon, gold title (and the game it is for), a few words, and
-- its settings path, which opens that page when it has one
local CLIENT_TAG = { forever = "WOW: FOREVER", anniversary = "ANNIVERSARY" }
local function Feature(key, y, x, W, it)
	local f = Keep("feat:" .. key, function()
		local fr = CreateFrame("Frame", nil, page.body)
		fr.icon = fr:CreateTexture(nil, "ARTWORK"); fr.icon:SetSize(32, 32)
		fr.icon:SetPoint("TOPLEFT", fr, "TOPLEFT", 0, -2); fr.icon:SetTexCoord(ICON_TRIM, 1 - ICON_TRIM, ICON_TRIM, 1 - ICON_TRIM)
		fr.title = Text(fr, "row"); fr.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3]); fr.title:SetWordWrap(false)
		fr.title:SetPoint("TOPLEFT", fr, "TOPLEFT", 46, 0)
		fr.tag = Text(fr, "section", "accentHi"); fr.tag:SetWordWrap(false)
		fr.tag:SetPoint("LEFT", fr.title, "RIGHT", 8, 0)
		fr.body = Text(fr, "rowDim")
		fr.body:SetPoint("TOPLEFT", fr.title, "BOTTOMLEFT", 0, -5)
		fr.link = CreateFrame("Button", nil, fr)
		fr.link.text = Text(fr.link, "rowDim"); fr.link.text:SetWordWrap(false)
		fr.link.text:SetPoint("TOPLEFT", fr.link, "TOPLEFT", 0, 0)
		fr.link.line = fr.link:CreateTexture(nil, "ARTWORK"); fr.link.line:SetHeight(1)
		fr.link.line:SetPoint("BOTTOMLEFT", fr.link, "BOTTOMLEFT", 0, 0); fr.link.line:SetPoint("BOTTOMRIGHT", fr.link, "BOTTOMRIGHT", 0, 0)
		fr.link:SetScript("OnEnter", function(self) if self.open then self.text:SetTextColor(Core:Color("white")) end end)
		fr.link:SetScript("OnLeave", function(self) if self.open then self.text:SetTextColor(Core:Color("accentHi")) end end)
		fr.link:SetScript("OnClick", function(self)
			if self.open and ns.SPConfig and ns.SPConfig.Open then ns.SPConfig:Open(self.open) end
		end)
		return fr
	end)
	f:SetPoint("TOPLEFT", page.body, "TOPLEFT", x, -y)
	local art = it.look and LookArt(key) or nil
	local tw = W - 46 - (art and (4 * 34 + 10 + 16) or 0)
	f.icon:SetTexture(it.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	f.title:SetText(it.h or "")
	f.tag:SetText(CLIENT_TAG[it.client] or "")
	f.body:SetWidth(tw)
	f.body:SetText(it.b or "")
	local h = 18 + 5 + math.ceil(f.body:GetStringHeight())
	if it.path then
		f.link:Show()
		f.link.open = it.open
		f.link.text:SetText(it.open and (it.path .. "  >") or it.path)
		f.link.text:SetTextColor(Core:Color("accentHi"))
		f.link.line:SetColorTexture(Core:Color("accentHi", it.open and 0.45 or 0))
		f.link:SetSize(math.ceil(f.link.text:GetStringWidth()), 15)
		f.link:ClearAllPoints()
		f.link:SetPoint("TOPLEFT", f.body, "BOTTOMLEFT", 0, -4)
		f.link:EnableMouse(it.open ~= nil)
		h = h + 4 + 15
	else
		f.link:Hide()
	end
	if art then
		art:SetPoint("TOPLEFT", page.body, "TOPLEFT", x + W - (4 * 34 + 10), -(y + 2))
		h = max(h, 66)
	end
	h = max(h, 36)
	f:SetSize(W, h)
	return h + 12
end

-- a change or fix: a dot and one line (the game it is for in front)
local CLIENT_WORD = { forever = "WoW: Forever", anniversary = "Anniversary" }
local function Bullet(key, y, x, W, line)
	local b = Keep("bullet:" .. key, function()
		local fr = CreateFrame("Frame", nil, page.body)
		fr.dot = fr:CreateTexture(nil, "ARTWORK"); fr.dot:SetSize(4, 4)
		fr.dot:SetPoint("TOPLEFT", fr, "TOPLEFT", 3, -6); fr.dot:SetColorTexture(Core:Color("textDim"))
		fr.text = Text(fr, "rowDim"); fr.text:SetPoint("TOPLEFT", fr, "TOPLEFT", 14, 0)
		return fr
	end)
	local t, client = LineText(line)
	if client and CLIENT_WORD[client] then t = "|cff3FA9F5" .. CLIENT_WORD[client] .. ":|r " .. t end
	b:SetPoint("TOPLEFT", page.body, "TOPLEFT", x, -y)
	b.text:SetWidth(W - 14)
	b.text:SetText(t)
	local h = math.ceil(b.text:GetStringHeight())
	b:SetSize(W, h)
	return h + 5
end

-- one version's notes under its bar: New, then Changes, then Fixes, then (after a
-- space) its thanks line, if it has one
local function Notes(key, y, W, new, changes, fixes, thanks)
	local x, w = 18, W - 36
	if #new > 0 then
		y = y + Label(key .. ":new", y, x, "NEW")
		for i, it in ipairs(new) do y = y + Feature(key .. ":" .. i, y, x, w, it) end
	end
	if #changes > 0 then
		y = y + 2 + Label(key .. ":changes", y + 2, x, "CHANGES")
		for i, l in ipairs(changes) do y = y + Bullet(key .. ":c" .. i, y, x, w, l) end
		y = y + 6
	end
	if #fixes > 0 then
		y = y + 2 + Label(key .. ":fixes", y + 2, x, "FIXES")
		for i, l in ipairs(fixes) do y = y + Bullet(key .. ":f" .. i, y, x, w, l) end
		y = y + 6
	end
	if thanks and thanks ~= "" then
		y = y + 10
		local t = Keep("thanks:" .. key, function()
			local fr = CreateFrame("Frame", nil, page.body)
			fr.text = Text(fr, "rowDim"); fr.text:SetPoint("TOPLEFT", fr, "TOPLEFT", 0, 0)
			return fr
		end)
		t:SetPoint("TOPLEFT", page.body, "TOPLEFT", x, -y)
		t.text:SetWidth(w)
		t.text:SetText(thanks)
		local h = math.ceil(t.text:GetStringHeight())
		t:SetSize(w, h)
		y = y + h + 6
	end
	return y
end

local function CountsOf(new, changes, fixes)
	local c = {}
	if #new > 0 then c[#c + 1] = Plural(#new, "new", "new") end
	if #changes > 0 then c[#c + 1] = Plural(#changes, "change", "changes") end
	if #fixes > 0 then c[#c + 1] = Plural(#fixes, "fix", "fixes") end
	return c
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------
local function BaseVersion(v) return v and (v:gsub("%-.*$", "")) or nil end

-- the sidebar's NEW tag: until this version's notes have been opened
function SP:PatchNotesUnseen()
	local g = self.db and self.db.global
	local cur = BaseVersion(GetAddOnMetadata and GetAddOnMetadata("ShamanPower", "Version"))
	return g ~= nil and cur ~= nil and g.patchNotesSeen ~= cur
end

function Page.Render(_, body, W, onChanged, query)
	page.body = body
	for i = #shown, 1, -1 do shown[i] = nil end
	local notes = ns.PATCH_NOTES or {}
	query = query and query ~= "" and query:lower() or nil
	-- seen: the sidebar's NEW tag goes
	local g = SP.db and SP.db.global
	local cur = BaseVersion(GetAddOnMetadata and GetAddOnMetadata("ShamanPower", "Version"))
	if g and cur and g.patchNotesSeen ~= cur then
		g.patchNotesSeen = cur
		C_Timer.After(0, Refresh)   -- the sidebar redraws without its NEW tag
	end
	-- the latest version starts open
	if state.open.first == nil and notes[1] then state.open[notes[1].v] = true; state.open.first = true end

	local y = 0
	-- the game filter and Expand / Collapse All
	local x = 0
	for _, def in ipairs({ { "all", "All" }, { "forever", "WoW: Forever" }, { "anniversary", "TBC Anniversary" } }) do
		local c = Chip(def[1], def[2], state.filter == def[1], function() state.filter = def[1]; Refresh() end)
		c:SetPoint("TOPLEFT", body, "TOPLEFT", x, -y)
		x = x + c:GetWidth() + 8
	end
	local collapse = Keep("btn:collapse", function()
		local b = Core:MakeButton(page.body, "Collapse All", 110, false)
		b:SetScript("OnClick", function() for k in pairs(state.open) do if k ~= "first" then state.open[k] = nil end end; Refresh() end)
		return b
	end)
	collapse:SetPoint("TOPRIGHT", body, "TOPLEFT", W, -y)
	local expand = Keep("btn:expand", function()
		local b = Core:MakeButton(page.body, "Expand All", 110, false)
		b:SetScript("OnClick", function()
			for _, v in ipairs(ns.PATCH_NOTES or {}) do state.open[v.v] = true end
			state.open["2.x"] = true
			Refresh()
		end)
		return b
	end)
	expand:SetPoint("RIGHT", collapse, "LEFT", -8, 0)
	y = y + 38

	-- 3.x versions one by one; 2.x folded into one block
	local era, eraFirst, eraLast = {}, nil, nil
	local drew = false
	for i, ver in ipairs(notes) do
		local new, changes, fixes = Visible(ver, query)
		if new then
			if ver.v:match("^2%.") then
				era[#era + 1] = { ver = ver, new = new, changes = changes, fixes = fixes }
				eraLast = eraLast or ver.date
				eraFirst = ver.date or eraFirst
			else
				local isOpen = state.open[ver.v] or query ~= nil
				local key = ver.v
				y = y + Header(key, y, W, true, ver.v, ver.date and NiceDate(ver.date) or "", ver.headline,
					CountsOf(new, changes, fixes), isOpen, i == 1, function() state.open[key] = not state.open[key] or nil; Refresh() end)
				if isOpen then y = Notes(key, y + 14, W, new, changes, fixes, ver.thanks) + 6 end
				y = y + 8
				drew = true
			end
		end
	end
	if #era > 0 then
		-- EARLIER, then the 2.x block
		local lab = Keep("earlier", function()
			local f = CreateFrame("Frame", nil, page.body)
			f.text = Text(f, "section", "textMute"); f.text:SetPoint("LEFT", f, "LEFT", 0, 0); f.text:SetWordWrap(false)
			f.text:SetText("EARLIER")
			f.line = f:CreateTexture(nil, "ARTWORK"); f.line:SetHeight(1); f.line:SetColorTexture(Core:Color("border"))
			f.line:SetPoint("LEFT", f.text, "RIGHT", 8, 0); f.line:SetPoint("RIGHT", f, "RIGHT", 0, 0)
			return f
		end)
		lab:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -(y + 4)); lab:SetSize(W, 14)
		y = y + 26
		local isOpen = state.open["2.x"] or query ~= nil
		local span = (eraFirst and eraLast) and (MonthYear(eraFirst) .. " - " .. MonthYear(eraLast)) or ""
		if MonthYear(eraFirst) == MonthYear(eraLast) then span = MonthYear(eraFirst) end
		y = y + Header("2.x", y, W, false, "2.x", span, "The setup tour, the new settings window and more",
			{ Plural(#era, "version", "versions") }, isOpen, false, function() state.open["2.x"] = not state.open["2.x"] or nil; Refresh() end)
		if isOpen then
			y = y + 14
			for _, e in ipairs(era) do
				y = y + Label("era:" .. e.ver.v, y, 18, e.ver.v .. (e.ver.date and ("   " .. NiceDate(e.ver.date)) or ""), nil, true) + 4
				y = Notes(e.ver.v, y, W, e.new, e.changes, e.fixes, e.ver.thanks) + 8
			end
		end
		y = y + 8
		drew = true
	end
	if not drew then
		local none = Keep("none", function()
			local f = CreateFrame("Frame", nil, page.body)
			f.text = Text(f, "rowDim"); f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
			return f
		end)
		none.text:SetWidth(W)
		none.text:SetText(query and "No patch notes match that search." or "No patch notes for this game.")
		none:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y); none:SetSize(W, 20)
		y = y + 24
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
