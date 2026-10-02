-- ShamanPower_Config / WhatsNew.lua
-- Small once-per-release "what's new" card for existing users. New installs
-- get the guided setup instead and are never shown this; releases whose notes
-- below do not match the running version show nothing at all. The seen
-- version is stamped account-wide (db.global.lastSeenVersion).
local _, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not SP then return end

-- The card reads the patch notes (PatchNotes.lua, also Settings > Patch Notes):
-- the items marked card = true in every version newer than the one this account
-- last saw. The newest version's items are full rows (its look item is the NEW
-- box); older versions' items are one-line rows under "Also new in". A release
-- with no card items for this account shows nothing at all.
local NOTES = { version = (ns.PATCH_NOTES and ns.PATCH_NOTES[1] and ns.PATCH_NOTES[1].v) or "3.0.0" }

local DISCORD_INVITE = "https://discord.gg/eCtNeBqE8U"

-- The gold banner's title (ui-style-guide 2.3 A) in Fira Sans SemiBold, the
-- wordmark's weight, gold with its outline as before. The game's font where Fira
-- is missing (a new file loads only after a full restart) or on Chinese and
-- Korean clients (SP:BrandFontPath gives the game's font there).
local function BannerFont(fs)
	local path = SP.BrandFontPath and SP:BrandFontPath("semibold")
	local ok, set = false, false
	if path then ok, set = pcall(fs.SetFont, fs, path, 26, "OUTLINE") end
	if not (ok and set) then fs:SetFont("Fonts\\FRIZQT__.TTF", 26, "OUTLINE") end
end

local function BaseVersion(v)
	return v and (v:gsub("%-.*$", "")) or nil
end

-- "3.0.4" -> 3000004 (test builds by the part before the dash); nil if unreadable
local function VerNum(v)
	v = BaseVersion(v)
	if not v then return nil end
	local a, b, c = v:match("^(%d+)%.(%d+)%.?(%d*)")   -- (never "v and v:match": "and" keeps only the first capture)
	if not a then return nil end
	return tonumber(a) * 1000000 + tonumber(b) * 1000 + (tonumber(c) or 0)
end
-- the card's versions: newer than `since` and not newer than the running one
-- (since = nil: all of them), each with its card items for this game; newest first
local function CardSets(since, preview)
	local s = VerNum(since)
	local cur = VerNum(GetAddOnMetadata and GetAddOnMetadata("ShamanPower", "Version"))
	local forever = SPCompat.FOREVER
	local out = {}
	for _, ver in ipairs(ns.PATCH_NOTES or {}) do
		local n = VerNum(ver.v)
		-- (on request, since = nil, or a preview: every version's items, even a test build's newest)
		if n and (not s or n > s) and (not s or preview or not cur or n <= cur) then
			local items = {}
			for _, it in ipairs(ver.new or {}) do
				local gameOK = it.client == nil or ((it.client == "forever") == forever)
				if it.card and gameOK and (not it.when or it.when()) then items[#items + 1] = it end
			end
			if #items > 0 then out[#out + 1] = { ver = ver, items = items } end
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Style preview: the setup tour's own Totem Bar mock, drawn with the player's
-- current bar settings plus one style's flags (ShamanPowerStyles.lua), in
-- read-only preview mode. Nothing changes unless "Turn it on" is pressed.
-- ---------------------------------------------------------------------------
local previewDlg
local function ShowStylePreview(key)
	local st = SP.TotemBarStyle and SP:TotemBarStyle(key)
	if not (st and SP.Wizard and SP.Wizard.BuildTotemBarStep and SP.ApplyTotemBarStyleTo) then
		print("|cff0070ddShamanPower|r: that Totem Bar style is not available in this version of the game.")
		return
	end
	if not previewDlg then
		previewDlg = Core:CreateDialog({
			name = "ShamanPowerStylePreview", width = 560, height = 372,
			title = st.label, subtitle = "a preview with your current bar settings - nothing changes until you turn it on",
			headerHeight = 46, footer = 52, special = true, strata = "FULLSCREEN_DIALOG",
		})
		local solid = previewDlg:CreateTexture(nil, "BACKGROUND", nil, 1)
		solid:SetAllPoints(previewDlg)   -- (out to the edge, which draws over it)
		solid:SetColorTexture(Core:Color("windowBg", 1))
		local solidH = previewDlg.header:CreateTexture(nil, "BACKGROUND", nil, 1)
		solidH:SetAllPoints(previewDlg.header); solidH:SetColorTexture(Core:Color("sidebarBg", 1))

		local shot = CreateFrame("Frame", nil, previewDlg.body)
		shot:SetPoint("TOPLEFT", previewDlg.body, "TOPLEFT", 0, 0)
		shot:SetPoint("TOPRIGHT", previewDlg.body, "TOPRIGHT", 0, 0)
		shot:SetHeight(190)
		Core:SolidTex(shot, "contentBg", "BACKGROUND"); Core:MakeBorder(shot, "border")
		previewDlg.shot = shot

		local cap = previewDlg.body:CreateFontString(nil, "OVERLAY"); cap:SetFontObject(Core.fonts.rowDim)
		cap:SetPoint("TOPLEFT", shot, "BOTTOMLEFT", 0, -8); cap:SetPoint("TOPRIGHT", shot, "BOTTOMRIGHT", 0, -8)
		cap:SetJustifyH("LEFT"); cap:SetWordWrap(true)
		previewDlg.cap = cap

		-- spOnHide keeps the dialog shell's own OnHide (popup cleanup) intact
		previewDlg.spOnHide = function(self)
			SP.Wizard.optOverride = nil
			SP.Wizard.previewOnly = nil
			if self.host then self.host:Hide() end
		end

		local on = Core:MakeButton(previewDlg, "Turn it on", 150, true)
		on:SetPoint("BOTTOMRIGHT", previewDlg, "BOTTOMRIGHT", -14, 12)
		on:SetScript("OnClick", function()
			local k = previewDlg.styleKey
			previewDlg:Hide()
			local picked = SP.TotemBarStyle and SP:TotemBarStyle(k)
			if picked and SP:SetTotemBarStyle(k) then   -- in combat it says so itself
				print("|cff0070ddShamanPower|r: " .. picked.label .. " is on. Settings > General > Main > Totem Bar Style"
					.. " switches back; Bars > Totem Bar > Style has its settings.")
				if ns.SPConfig and ns.SPConfig.Open then ns.SPConfig:Open({ "settings", "settings_totemMode" }) end
			end
		end)
		local notNow = Core:MakeButton(previewDlg, "Not now", 100, false)
		notNow:SetPoint("RIGHT", on, "LEFT", -8, 0)
		notNow:SetScript("OnClick", function() previewDlg:Hide() end)
	end
	previewDlg.styleKey = key
	previewDlg:SetTitles(st.label, "a preview with your current bar settings - nothing changes until you turn it on")
	previewDlg.cap:SetText(ns.StyleCaptions and ns.StyleCaptions[key] or "")

	-- Rebuild the mock on every open so it reflects the current settings.
	if previewDlg.host then previewDlg.host:Hide(); previewDlg.host:SetParent(nil) end
	local host = CreateFrame("Frame", nil, previewDlg.shot)
	host:SetPoint("TOPLEFT", previewDlg.shot, "TOPLEFT", 4, -4)
	host:SetPoint("BOTTOMRIGHT", previewDlg.shot, "BOTTOMRIGHT", -4, 4)
	host:SetClipsChildren(true)
	previewDlg.host = host

	local o = {}
	for k, v in pairs(SP.opt) do o[k] = v end   -- shallow copy; nested tables are only read
	SP:ApplyTotemBarStyleTo(o, key)
	SP.Wizard.optOverride = o
	SP.Wizard.previewOnly = true
	local dummyCard = CreateFrame("Frame", nil, host); dummyCard:SetSize(400, 10); dummyCard:Hide()
	local ok = pcall(SP.Wizard.BuildTotemBarStep, dummyCard, host, 0)
	if ok then
		-- the mock's own caption belongs to the tour page, not this card
		for _, r in ipairs({ host:GetRegions() }) do
			if r.IsObjectType and r:IsObjectType("FontString") then r:Hide() end
		end
	else
		local t = host:CreateFontString(nil, "OVERLAY"); t:SetFontObject(Core.fonts.rowDim)
		t:SetPoint("CENTER"); t:SetText("Could not build the preview.")
	end
	previewDlg:Show()
	previewDlg:Raise()   -- above the what's-new card it was opened from
end

-- ---------------------------------------------------------------------------
-- The ShamanPower look (General > Themes). Offered once per account, to
-- existing users only: a new install picks its look in the setup tour. It
-- only ever shows and opens: nothing changes unless the player changes it on
-- the Themes tab, and "Keep my look" / "Got it" / the X change nothing.
-- ---------------------------------------------------------------------------
local function ThemesAvailable()
	return SP.SetThemeGlobal ~= nil and SP.ThemeGlobal ~= nil and SP.Wizard ~= nil and SP.Wizard.ThemeMiniBar ~= nil
end

local function OpenThemes()
	if SP.OpenThemesTab then SP:OpenThemesTab() return end   -- the Themes page's own opener, when it has one
	if ns.SPConfig and ns.SPConfig.Open then ns.SPConfig:Open({ "settings", "settings_themes" }) end
end

local LOOK_TEXT = "One look for every color in ShamanPower: the logo's element colors, WoW's own green, yellow"
	.. " and red for charges and timers, and navy panels. ShamanPower Minimal adds flat element boxes."
	.. " Your look stays exactly as it is unless you pick a theme, and Standard always puts it back."
	.. "\n|cff3FA9F5Settings > General > Themes|r"

-- The item: an info box (accent fill and border) with the NEW tag, the heading,
-- the text and the player's bar now next to it in the ShamanPower look.
-- onTry: a "Try it" button in the box (secondary, as the card's other Try it
-- buttons). Returns the box and its height.
local function LookBox(parent, y, W, onTry)
	local GOLD = { 1, 0.82, 0.15 }
	local box = CreateFrame("Frame", nil, parent)
	box:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
	box:SetWidth(W)
	Core:SolidTex(box, "accent", "BACKGROUND", 0.10)
	Core:MakeBorder(box, "accent")
	local tag = box:CreateFontString(nil, "OVERLAY")
	tag:SetFontObject(Core.fonts.section)
	tag:SetTextColor(1, 0.82, 0)   -- gold: "new"
	tag:SetText("NEW")
	local head = box:CreateFontString(nil, "OVERLAY")
	head:SetFontObject(Core.fonts.row)
	head:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	head:SetJustifyH("LEFT"); head:SetWordWrap(true)
	head:SetText("The ShamanPower look")
	tag:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -12)
	local tagW = math.ceil(tag:GetStringWidth())
	head:SetPoint("TOPLEFT", box, "TOPLEFT", 12 + tagW + 8, -11)
	head:SetWidth(W - 24 - tagW - 8)
	local h = 11 + math.max(14, math.ceil(head:GetStringHeight())) + 6
	local body = box:CreateFontString(nil, "OVERLAY")
	body:SetFontObject(Core.fonts.rowDim)
	body:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -h)
	body:SetWidth(W - 24); body:SetJustifyH("LEFT"); body:SetWordWrap(true)
	body:SetText(LOOK_TEXT)
	h = h + math.ceil(body:GetStringHeight()) + 12

	-- your bar now, and in the ShamanPower look
	local x = 12
	local barH = 0
	for _, key in ipairs({ "now", "shamanpower" }) do
		local cap = box:CreateFontString(nil, "OVERLAY")
		cap:SetFontObject(Core.fonts.section)
		cap:SetPoint("TOPLEFT", box, "TOPLEFT", x, -h)
		cap:SetText(strupper(key == "now" and "Your bar now" or "ShamanPower"))
		local bar = SP.Wizard.ThemeMiniBar(box, 24, false)
		bar:SetPoint("TOPLEFT", box, "TOPLEFT", x, -(h + 18))
		bar:Paint(key)
		barH = bar:GetHeight()
		x = x + math.max(bar:GetWidth(), math.ceil(cap:GetStringWidth())) + 28
	end
	h = h + 18 + barH + 12
	if onTry then
		local try = Core:MakeButton(box, "Try it", 80, false)
		try:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)
		try:SetScript("OnClick", onTry)
		Core:AttachTooltip(try, "Try it", "Opens Settings > General > Themes. Nothing changes until you pick a theme there.")
	end
	box:SetHeight(h)
	return box, h
end

-- the look card on its own, for existing users who already saw this release's card
local lookDlg
local function BuildLookDialog()
	if lookDlg then return lookDlg end
	lookDlg = Core:CreateDialog({
		name = "ShamanPowerWhatsNewLook", width = 560, height = 200,
		title = "What's new", subtitle = "shown once",
		headerHeight = 46, footer = 52, special = true, strata = "DIALOG",
	})
	local solid = lookDlg:CreateTexture(nil, "BACKGROUND", nil, 1)
	solid:SetAllPoints(lookDlg)   -- (out to the edge, which draws over it)
	solid:SetColorTexture(Core:Color("windowBg", 1))
	local solidH = lookDlg.header:CreateTexture(nil, "BACKGROUND", nil, 1)
	solidH:SetAllPoints(lookDlg.header); solidH:SetColorTexture(Core:Color("sidebarBg", 1))

	local W, y = 526, 2
	local GOLD = { 1, 0.82, 0.15 }
	-- the gold banner (ui-style-guide 2.3 A), as the release card draws it
	do
		local band = CreateFrame("Frame", nil, lookDlg.body)
		band:SetPoint("TOPLEFT", lookDlg.body, "TOPLEFT", 0, 0); band:SetPoint("TOPRIGHT", lookDlg.body, "TOPRIGHT", 0, 0)
		local glow = band:CreateTexture(nil, "BACKGROUND"); glow:SetAllPoints(band); glow:SetColorTexture(1, 1, 1, 1)
		Core:Gradient(glow, "HORIZONTAL", GOLD[1], GOLD[2], GOLD[3], 0.26, GOLD[1], GOLD[2], GOLD[3], 0)
		local rule = band:CreateTexture(nil, "ARTWORK"); rule:SetHeight(2)
		rule:SetPoint("BOTTOMLEFT", band, "BOTTOMLEFT", 0, 0); rule:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", 0, 0)
		rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
		local icon = band:CreateTexture(nil, "ARTWORK"); icon:SetSize(44, 44)
		icon:SetPoint("LEFT", band, "LEFT", 8, 0); icon:SetTexture("Interface\\WorldStateFrame\\Icons-Classes"); icon:SetTexCoord(0.25, 0.5, 0.25, 0.5)
		local title = band:CreateFontString(nil, "OVERLAY")
		BannerFont(title); title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		title:SetShadowColor(0, 0, 0, 1); title:SetShadowOffset(2, -2)
		title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, 0)
		local installed = BaseVersion(GetAddOnMetadata and GetAddOnMetadata("ShamanPower", "Version"))
		title:SetText("ShamanPower " .. ((installed or NOTES.version):gsub("%.0$", "")))
		local sub = band:CreateFontString(nil, "OVERLAY"); sub:SetFontObject(Core.fonts.row)
		sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -3)
		sub:SetWidth(W - 64 - 12); sub:SetJustifyH("LEFT"); sub:SetWordWrap(true)
		sub:SetText("A new look, if you want one")
		local bandH = math.max(62, 9 + math.ceil(title:GetStringHeight()) + 3 + math.ceil(sub:GetStringHeight()) + 12)
		band:SetHeight(bandH)
		y = y + bandH + 14
	end
	local _, h = LookBox(lookDlg.body, y, W, nil)
	y = y + h
	lookDlg:SetHeight(46 + 4 + 10 + y + lookDlg.pad + 52)   -- header, rule, body top, content, pad, footer

	-- Try it (primary, rightmost) opens the Themes tab; Keep my look, the X and
	-- Escape just close it
	local try = Core:MakeButton(lookDlg, "Try it", 110, true)
	try:SetPoint("BOTTOMRIGHT", lookDlg, "BOTTOMRIGHT", -14, 12)
	try:SetScript("OnClick", function() lookDlg:Hide(); OpenThemes() end)
	local keep = Core:MakeButton(lookDlg, "Keep my look", 110, false)
	keep:SetPoint("RIGHT", try, "LEFT", -8, 0)
	keep:SetScript("OnClick", function() lookDlg:Hide() end)
	lookDlg.close:SetScript("OnClick", function() keep:Click() end)
	return lookDlg
end

-- ---------------------------------------------------------------------------
-- The card
-- ---------------------------------------------------------------------------
-- 3.0.4's NEW box: the release's look story (the notes' look item), the bar now
-- and in the new shapes, Try it opens the Themes tab. Returns the box and its height.
local function NewLookBox(parent, y, W, it, onTry)
	local GOLD = { 1, 0.82, 0.15 }
	local box = CreateFrame("Frame", nil, parent)
	box:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
	box:SetWidth(W)
	Core:SolidTex(box, "accent", "BACKGROUND", 0.10)
	Core:MakeBorder(box, "accent")
	local tag = box:CreateFontString(nil, "OVERLAY")
	tag:SetFontObject(Core.fonts.section)
	tag:SetTextColor(1, 0.82, 0)
	tag:SetText("NEW")
	tag:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -12)
	local tagW = math.ceil(tag:GetStringWidth())
	local head = box:CreateFontString(nil, "OVERLAY")
	head:SetFontObject(Core.fonts.row)
	head:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	head:SetJustifyH("LEFT"); head:SetWordWrap(true)
	head:SetPoint("TOPLEFT", box, "TOPLEFT", 12 + tagW + 8, -11)
	head:SetWidth(W - 24 - tagW - 8)
	head:SetText(it.h)
	local h = 11 + math.max(14, math.ceil(head:GetStringHeight())) + 6
	local body = box:CreateFontString(nil, "OVERLAY")
	body:SetFontObject(Core.fonts.rowDim)
	body:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -h)
	body:SetWidth(W - 24); body:SetJustifyH("LEFT"); body:SetWordWrap(true)
	body:SetText(it.b .. (it.path and ("\n|cff3FA9F5" .. it.path .. "|r") or ""))
	h = h + math.ceil(body:GetStringHeight()) + 10
	-- your bar now, and in Circle icons with two-tone bars
	local x, barH = 12, 0
	local cap = box:CreateFontString(nil, "OVERLAY")
	cap:SetFontObject(Core.fonts.section)
	cap:SetPoint("TOPLEFT", box, "TOPLEFT", x, -h)
	cap:SetText("YOUR BAR NOW")
	local bar = SP.Wizard.ThemeMiniBar(box, 24, false)
	bar:SetPoint("TOPLEFT", box, "TOPLEFT", x, -(h + 18))
	bar:Paint("now")
	barH = bar:GetHeight()
	x = x + math.max(bar:GetWidth(), math.ceil(cap:GetStringWidth())) + 28
	if ns.BuildLookArt then
		local cap2 = box:CreateFontString(nil, "OVERLAY")
		cap2:SetFontObject(Core.fonts.section)
		cap2:SetPoint("TOPLEFT", box, "TOPLEFT", x, -h)
		cap2:SetText("CIRCLE, TWO-TONE BARS")
		local art = ns.BuildLookArt(box)
		if art.cap then art.cap:Hide() end
		art:SetPoint("TOPLEFT", box, "TOPLEFT", x, -(h + 18))
		barH = math.max(barH, 48)
	end
	h = h + 18 + barH + 12
	local try = Core:MakeButton(box, "Try it", 80, false)
	try:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)
	try:SetScript("OnClick", onTry)
	Core:AttachTooltip(try, "Try it", "Opens Settings > General > Themes. Nothing changes until you pick something there.")
	box:SetHeight(h)
	return box, h
end

-- a small-caps section line ("NEW IN 3.0.4", "ALSO NEW IN 3.0") with a rule after it
local function CardSection(parent, y, W, text)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(Core.fonts.section)
	fs:SetTextColor(Core:Color("accentHi"))
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
	fs:SetText(text)
	local rule = parent:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	rule:SetColorTexture(Core:Color("border"))
	rule:SetPoint("LEFT", fs, "RIGHT", 8, 0)
	rule:SetPoint("RIGHT", parent, "TOPLEFT", W, -(y + 7))
	return 20
end

local function OpenPatchNotes()
	if ns.SPConfig and ns.SPConfig.Open then ns.SPConfig:Open({ "settings", "settings_patchnotes" }) end
end

-- the card for everything newer than `since` (nil: every version's card items)
local cards = {}
local function BuildDialog(since, preview)
	local key = since or "all"
	if cards[key] then return cards[key] end
	local dlg = Core:CreateDialog({
		name = "ShamanPowerWhatsNew" .. ((key == "all") and "" or key:gsub("%.", "_")), width = 560, height = 200,
		title = "What's new",
		subtitle = "shown once per update", headerHeight = 46, footer = 52, special = true,
	})
	cards[key] = dlg
	dlg:SetFrameStrata("DIALOG")
	local solid = dlg:CreateTexture(nil, "BACKGROUND", nil, 1)
	solid:SetAllPoints(dlg)   -- (out to the edge, which draws over it)
	solid:SetColorTexture(Core:Color("windowBg", 1))

	local W, y = 526, 2
	local isShaman = select(2, UnitClass("player")) == "SHAMAN"
	local GOLD = { 1, 0.82, 0.15 }

	-- the banner: big gold version title over a gold glow, like the Discord heading
	do
		local band = CreateFrame("Frame", nil, dlg.body)
		band:SetPoint("TOPLEFT", dlg.body, "TOPLEFT", 0, 0); band:SetPoint("TOPRIGHT", dlg.body, "TOPRIGHT", 0, 0)
		band:SetHeight(62)
		local glow = band:CreateTexture(nil, "BACKGROUND"); glow:SetAllPoints(band); glow:SetColorTexture(1, 1, 1, 1)
		Core:Gradient(glow, "HORIZONTAL", GOLD[1], GOLD[2], GOLD[3], 0.26, GOLD[1], GOLD[2], GOLD[3], 0)
		local rule = band:CreateTexture(nil, "ARTWORK"); rule:SetHeight(2)
		rule:SetPoint("BOTTOMLEFT", band, "BOTTOMLEFT", 0, 0); rule:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", 0, 0)
		rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
		local icon = band:CreateTexture(nil, "ARTWORK"); icon:SetSize(44, 44)
		icon:SetPoint("LEFT", band, "LEFT", 8, 0); icon:SetTexture("Interface\\WorldStateFrame\\Icons-Classes"); icon:SetTexCoord(0.25, 0.5, 0.25, 0.5)   -- shaman emblem, no background
		local title = band:CreateFontString(nil, "OVERLAY")
		BannerFont(title); title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		title:SetShadowColor(0, 0, 0, 1); title:SetShadowOffset(2, -2)
		title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, 0)
		-- the installed version (3.0.1), so a patch of the series needs no edit here
		local installed = BaseVersion(GetAddOnMetadata and GetAddOnMetadata("ShamanPower", "Version"))
		local about = CardSets(since, preview)[1]   -- the version this card is about (a test build may still carry the older number)
		title:SetText("ShamanPower " .. (((about and about.ver.v) or installed or NOTES.version):gsub("%.0$", "")))
		local sub = band:CreateFontString(nil, "OVERLAY"); sub:SetFontObject(Core.fonts.row)
		sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -3)
		sub:SetText("Now on |cff3FA9F5WoW: Forever|r and TBC Anniversary")
		y = y + 62 + 14
	end

	-- Everything under the banner scrolls when the card would not fit on the screen
	-- (the full list, or an update from far back); the banner and the buttons stay put.
	local top = y
	local scroll = CreateFrame("ScrollFrame", nil, dlg.body)
	scroll:SetPoint("TOPLEFT", dlg.body, "TOPLEFT", 0, -top)
	scroll:SetPoint("BOTTOMRIGHT", dlg.body, "BOTTOMRIGHT", 0, 0)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(W, 10)
	scroll:SetScrollChild(content)
	y = 0

	-- one full item: icon, gold title, a few words and the settings path; a totem
	-- bar style gets its picture on the left and a Try it button on the right
	local function FullRow(it)
		local tryIt = it.try and isShaman and SP.TotemBarStyle and SP:TotemBarStyle(it.try) ~= nil
		local x, w = 0, W
		if not tryIt and it.icon then
			local ic = content:CreateTexture(nil, "ARTWORK"); ic:SetSize(30, 30)
			ic:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(y + 1)); ic:SetTexture(it.icon); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			x, w = 44, W - 44
		end
		if tryIt then
			if ns.DrawStyleThumb then
				local th = ns.DrawStyleThumb(content, it.try, 72, 34)
				th:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
				x = 84
			end
			local tb = Core:MakeButton(content, "Try it", 80, false)
			tb:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(y + 2))
			local style = it.try
			tb:SetScript("OnClick", function() ShowStylePreview(style) end)
			w = W - x - 92
		end
		local h = content:CreateFontString(nil, "OVERLAY"); h:SetFontObject(Core.fonts.row)
		h:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y); h:SetWidth(w); h:SetJustifyH("LEFT")
		h:SetText(it.h); h:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		y = y + h:GetStringHeight() + 4
		local b = content:CreateFontString(nil, "OVERLAY"); b:SetFontObject(Core.fonts.rowDim)
		b:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y); b:SetWidth(w); b:SetJustifyH("LEFT"); b:SetWordWrap(true)
		b:SetText(it.b .. (it.path and ("\n|cff3FA9F5" .. it.path .. "|r") or ""))
		y = y + b:GetStringHeight() + 14
	end
	-- one short row (an older version's highlight): a small icon, the title, one line
	local function ShortRow(it)
		if it.icon then
			local ic = content:CreateTexture(nil, "ARTWORK"); ic:SetSize(22, 22)
			ic:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -(y + 1)); ic:SetTexture(it.icon); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
		local h = content:CreateFontString(nil, "OVERLAY"); h:SetFontObject(Core.fonts.row)
		h:SetPoint("TOPLEFT", content, "TOPLEFT", 38, -y); h:SetWidth(W - 38); h:SetJustifyH("LEFT")
		h:SetText(it.h); h:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		y = y + h:GetStringHeight() + 3
		local b = content:CreateFontString(nil, "OVERLAY"); b:SetFontObject(Core.fonts.rowDim)
		b:SetPoint("TOPLEFT", content, "TOPLEFT", 38, -y); b:SetWidth(W - 38); b:SetJustifyH("LEFT"); b:SetWordWrap(true)
		b:SetText(it.s or it.b)
		y = y + b:GetStringHeight() + 10
	end

	local sets = CardSets(since, preview)
	local latest = sets[1]
	-- older versions' highlights, oldest first
	local older = {}
	for i = #sets, 2, -1 do older[#older + 1] = sets[i] end
	if latest then
		if #older > 0 then y = y + CardSection(content, y, W, "NEW IN " .. latest.ver.v) end
		for _, it in ipairs(latest.items) do
			if it.look and ThemesAvailable() then
				local _, lh = NewLookBox(content, y, W, it, function() dlg:Hide(); OpenThemes() end)
				y = y + lh + 14
			end
		end
		for _, it in ipairs(latest.items) do
			if not (it.look and ThemesAvailable()) then FullRow(it) end
		end
	end
	if #older > 0 then
		local series = older[#older].ver.v:match("^(%d+%.%d+)") or older[#older].ver.v
		y = y + 2 + CardSection(content, y + 2, W, "ALSO NEW IN " .. series)
		for _, set in ipairs(older) do
			for _, it in ipairs(set.items) do ShortRow(it) end
		end
		y = y + 4
	end

	-- Discord strip: logo, invite line, Copy Link
	do
		local strip = CreateFrame("Frame", nil, content)
		strip:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y); strip:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
		strip:SetHeight(40)
		local bg = strip:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(strip); bg:SetColorTexture(1, 1, 1, 1)
		Core:Gradient(bg, "HORIZONTAL", 0.345, 0.396, 0.949, 0.22, 0.345, 0.396, 0.949, 0.04)
		local logo = strip:CreateTexture(nil, "ARTWORK"); logo:SetSize(30, 30)
		logo:SetPoint("LEFT", strip, "LEFT", 6, 0); logo:SetTexture("Interface\\AddOns\\ShamanPower\\Media\\discord")
		local copy = Core:MakeButton(strip, "Copy Link", 100, true)
		copy:SetPoint("RIGHT", strip, "RIGHT", -6, 0)
		-- WoW cannot open links or write the clipboard: ShamanPower's copy box, above this card
		copy:SetScript("OnClick", function()
			SP:ShowSPDialog({
				key = "discordlink",
				title = "ShamanPower Discord",
				text = "The link is selected - press |cffFFD100Ctrl+C|r to copy it, then paste it into your browser.",
				editText = DISCORD_INVITE,
			})
		end)
		local t = strip:CreateFontString(nil, "OVERLAY"); t:SetFontObject(Core.fonts.row)
		t:SetPoint("LEFT", logo, "RIGHT", 10, 0); t:SetPoint("RIGHT", copy, "LEFT", -10, 0); t:SetJustifyH("LEFT")
		t:SetText("|cff8C9EFFJoin the ShamanPower Discord|r - help, bug reports and early test builds")
		y = y + 40 + 12
	end
	-- the Also line: each version's smaller things, newest first
	local also = {}
	for _, set in ipairs(sets) do
		if set.ver.also then also[#also + 1] = set.ver.also end
	end
	do
		local f = content:CreateFontString(nil, "OVERLAY"); f:SetFontObject(Core.fonts.tiny)
		f:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y); f:SetWidth(W); f:SetJustifyH("LEFT"); f:SetWordWrap(true)
		local text = "Every change is in Settings > Patch Notes."
		if #also > 0 then text = "Also: " .. table.concat(also, "; ") .. ". " .. text end
		f:SetText(text)
		y = y + f:GetStringHeight()
	end
	content:SetHeight(y)
	-- at most most of the screen's height; the rest scrolls (wheel or the thin bar)
	local maxH = math.floor(UIParent:GetHeight() * UIParent:GetEffectiveScale() / dlg:GetEffectiveScale() * 0.88)
	dlg:SetHeight(math.min(46 + 16 + top + y + 52, maxH))
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local maxS = math.max(0, content:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.max(0, math.min(maxS, self:GetVerticalScroll() - delta * 60)))
	end)
	Core:AttachScrollbar(scroll, content, { offset = 4 })   -- hides itself when everything fits

	local ok = Core:MakeButton(dlg, "Got it", 120, true)
	ok:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -14, 12)
	ok:SetScript("OnClick", function() dlg:Hide() end)
	if dlg.close then dlg.close:SetScript("OnClick", function() ok:Click() end) end
	-- every version's notes, in the settings
	local all = Core:MakeButton(dlg, "See All Patch Notes", 170, false)
	all:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 14, 12)
	all:SetScript("OnClick", function() dlg:Hide(); OpenPatchNotes() end)
	return dlg
end

-- The look card, automatically: once per account (db.global.themesCardSeen),
-- to an existing user (setup done) who has never used a theme on this
-- profile. Never over the tour, and it waits out combat like the release card.
local function LookCardDue(g)
	if not ThemesAvailable() or g.themesCardSeen then return false end
	if not (SP.opt and SP.opt.setupDone) then return false end   -- a new install: the tour offers the looks
	if SP.opt.theme ~= nil then g.themesCardSeen = true return false end   -- already on the Themes tab
	return true
end
local function ShowLookCard(g)
	if not LookCardDue(g) then return end
	local wiz = _G["ShamanPowerWizard"]
	if wiz and wiz:IsShown() then return end
	if InCombatLockdown() then C_Timer.After(15, function() SP:ShowWhatsNew() end) return end
	g.themesCardSeen = true
	BuildLookDialog():Show()
end

-- force = true (the /spwhatsnew test command) bypasses the version gate and
-- never stamps anything. "/spwhatsnew preview <style>" opens a style preview,
-- "/spwhatsnew look" the look card.
function SP:ShowWhatsNew(force)
	if force then
		-- opened on request (tour, settings button, /spwhatsnew): on top of the tour's layer
		local d = BuildDialog()
		d:SetFrameStrata("FULLSCREEN_DIALOG"); d:Show(); d:Raise()
		return
	end
	-- Automatic popup: shamans only. The "seen" stamp is account-wide, so an alt
	-- logging in first must not use it up; non-shamans open it from the settings button.
	if select(2, UnitClass("player")) ~= "SHAMAN" then return end
	-- ShamanPower switched off: stays quiet and unstamped (shown at a login with it on)
	if SP.IsOff and SP:IsOff() then return end
	local cur = GetAddOnMetadata and GetAddOnMetadata("ShamanPower", "Version")
	local g = self.db and self.db.global
	if not cur or not g then return end
	-- (no release card due: the look card, once, if it is due)
	if g.lastSeenVersion == cur then return ShowLookCard(g) end
	-- Brand-new installs are in (or headed into) the guided setup - stamp and
	-- stay quiet rather than stacking two windows.
	if self.opt and not self.opt.setupDone then g.lastSeenVersion = cur return end
	-- Only what is new since the version this account last saw: a release with no
	-- card items past it (for this game) stays quiet.
	local since = g.lastSeenVersion
	if #CardSets(since) == 0 then g.lastSeenVersion = cur return ShowLookCard(g) end
	-- Never on top of the setup wizard; try again next login instead.
	local wiz = _G["ShamanPowerWizard"]
	if wiz and wiz:IsShown() then return end
	if InCombatLockdown() then C_Timer.After(15, function() SP:ShowWhatsNew() end) return end
	g.lastSeenVersion = cur
	-- the release card carries the look item: that is the look offered
	if LookCardDue(g) then g.themesCardSeen = true end
	BuildDialog(since):Show()
end

SLASH_SPWHATSNEW1 = "/spwhatsnew"
SlashCmdList["SPWHATSNEW"] = function(msg)
	local m = strtrim(msg or ""):lower()
	if m == "look" then
		if not ThemesAvailable() then print("|cff0070ddShamanPower|r: themes are not available in this build.") return end
		local d = BuildLookDialog()
		d:SetFrameStrata("FULLSCREEN_DIALOG"); d:Show(); d:Raise()   -- on request: never stamped
		return
	end
	if m == "preview" then ShowStylePreview(SP.TotemBarStyle and SP:TotemBarStyle("blizzard") and "blizzard" or "compact") return end
	local key = m:match("^preview%s+(%S+)$")
	if key then ShowStylePreview(key) return end
	-- "/spwhatsnew 3.0.3": the card a player updating from 3.0.3 gets (never stamped)
	local from = m:match("^(%d+%.%d+[%.%d]*)$")
	if from then
		if #CardSets(from, true) == 0 then print("|cff0070ddShamanPower|r: nothing new on the card since " .. from .. ".") return end
		local d = BuildDialog(from, true)
		d:SetFrameStrata("FULLSCREEN_DIALOG"); d:Show(); d:Raise()
		return
	end
	SP:ShowWhatsNew(true)
end

local ef = CreateFrame("Frame")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	C_Timer.After(4, function() SP:ShowWhatsNew() end)
end)
