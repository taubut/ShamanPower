-- ============================================================================
-- The Loadout List (3.0.9.5, sheets A74 / A79; off by default): the loadouts that show here,
-- in a panel you can leave on screen, beside the loadout flyout (which stays as it is). A
-- heading per group: EVERYWHERE (loadouts on no group), then this place's Auto Loadout Groups
-- (ShamanPowerLoadoutRules.lua: the zone's own, its kind's), a raid's name in fire red. Each row:
-- the loadout's name on the left, its four totems on the right (a dash for none), the one in use
-- with the green bar and In Use. Click a row: switch to that loadout, outside a fight (in one,
-- the game's red line says it can't). Hidden loadouts never show, as in the flyout.
--
-- Plain frames, nothing secure: it can be drawn again in a fight. Drawn again only when the
-- loadouts or the place change (SP:UpdateLoadoutBar runs on every such change): nothing runs
-- while it is idle. Settings: Loadouts > Loadout List (opt.loadoutList). Moved in Unlock UI.
-- ============================================================================

local SP = ShamanPower
if not SP then return end
if select(2, UnitClass("player")) ~= "SHAMAN" then return end

local WIDTH = 280
local ROW_H = 22
local HEAD_H = 20
local PAD = 8
local ICON = 16
local DEFAULT_POS = { anchor = "CENTER", x = -420, y = 40 }
local EARTH = { 0.682, 0.494, 0.306 }   -- (the headings' small square: the brand's earth, as the menus')
local IN_USE = { 0.180, 0.800, 0.443 }

local function Opt()
	local o = SP.opt
	if not o then return {} end
	o.loadoutList = o.loadoutList or {}
	return o.loadoutList
end

local function ListOn()
	local o = SP.opt
	return o ~= nil and Opt().enabled == true and not o.loadoutsOff and not SP:IsOff()
end

local frame, rows, offset = nil, {}, 0
local entries = {}   -- what is drawn: { head = text, raid = bool } or { index = n }

local function Fire()
	local e = SP.Brand and SP.Brand.elements and SP.Brand.elements.fire
	if e then return e[1], e[2], e[3] end
	return 0.949, 0.341, 0.208
end

-- ---------------------------------------------------------------------------
-- What shows here, in headings
-- ---------------------------------------------------------------------------
local function Build()
	wipe(entries)
	local list = ShamanPower_TotemLoadouts or {}
	local shown = SP.LoadoutShownSet and SP:LoadoutShownSet() or nil
	local zoneG, kindG
	if SP.LoadoutGroupsHere then zoneG, kindG = SP:LoadoutGroupsHere() end
	local function Section(title, raid, test)
		local first = true
		for i, lo in ipairs(list) do
			if (not shown or shown[i]) and test(lo) then
				if first then entries[#entries + 1] = { head = title, raid = raid }; first = false end
				entries[#entries + 1] = { index = i }
			end
		end
	end
	local function OnNoGroup(lo) return not (lo.group and SP.LoadoutGroupByID and SP:LoadoutGroupByID(lo.group)) end
	Section("EVERYWHERE", false, OnNoGroup)
	for _, g in ipairs({ zoneG, kindG }) do
		if g then
			Section(SP:LoadoutGroupName(g):upper(), SP:LoadoutGroupIsRaid(g), function(lo) return lo.group == g.id end)
		end
	end
end

-- ---------------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------------
local function Font(fs, weight, size)
	if SP.BrandFont then SP:BrandFont(fs, weight, size, "") else fs:SetFontObject(GameFontHighlightSmall) end
end

local function NewRow(i)
	local r = CreateFrame("Button", nil, frame.content)
	r:SetHeight(ROW_H)
	r:SetPoint("LEFT", frame.content, "LEFT", 0, 0)
	r:SetPoint("RIGHT", frame.content, "RIGHT", 0, 0)
	r:RegisterForClicks("LeftButtonUp")
	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints(r)
	r.bg:SetColorTexture(1, 1, 1, 0.07)
	r.hover = r:CreateTexture(nil, "HIGHLIGHT")
	r.hover:SetAllPoints(r)
	r.hover:SetColorTexture(1, 1, 1, 0.05)
	r.mark = r:CreateTexture(nil, "ARTWORK")
	r.mark:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
	r.mark:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
	r.mark:SetWidth(3)
	r.mark:SetColorTexture(IN_USE[1], IN_USE[2], IN_USE[3], 1)
	r.square = r:CreateTexture(nil, "ARTWORK")
	r.square:SetSize(6, 6)
	r.square:SetPoint("LEFT", r, "LEFT", PAD + 2, 0)
	r.square:SetColorTexture(EARTH[1], EARTH[2], EARTH[3], 1)
	r.text = r:CreateFontString(nil, "OVERLAY")
	r.text:SetJustifyH("LEFT")
	r.text:SetWordWrap(true)   -- (a long name wraps: never cut short)
	r.inUse = r:CreateFontString(nil, "OVERLAY")
	Font(r.inUse, "regular", 11)
	r.inUse:SetTextColor(IN_USE[1], IN_USE[2], IN_USE[3])
	r.inUse:SetText("In Use")
	r.icons, r.dashes = {}, {}
	for e = 1, 4 do
		local t = r:CreateTexture(nil, "ARTWORK")
		t:SetSize(ICON, ICON)
		t:SetPoint("RIGHT", r, "RIGHT", -PAD - (4 - e) * (ICON + 3), 0)
		t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		r.icons[e] = t
		local d = r:CreateFontString(nil, "OVERLAY")
		Font(d, "regular", 12)
		d:SetTextColor(0.541, 0.580, 0.651)
		d:SetPoint("CENTER", t, "CENTER", 0, 0)
		d:SetText("-")
		r.dashes[e] = d
	end
	r.inUse:SetPoint("RIGHT", r.icons[1], "LEFT", -8, 0)
	r:SetScript("OnClick", function(self)
		local i = self.spIndex
		if not i then return end
		if InCombatLockdown() then
			UIErrorsFrame:AddMessage("Loadouts can't change in combat.", 1, 0.29, 0.29)
			return
		end
		SP:ApplyLoadout(i)
	end)
	r:SetScript("OnEnter", function(self)
		local i = self.spIndex
		if not (i and SP.opt and SP.opt.ShowTooltips) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local lo = ShamanPower_TotemLoadouts[i]
		GameTooltip:AddLine(lo and (lo.name or ("Loadout " .. i)) or "?", 1, 1, 1)
		local desc = SP.GetLoadoutDescriptionPlain and SP:GetLoadoutDescriptionPlain(i)
		if desc then GameTooltip:AddLine(desc, 0.8, 0.8, 0.8, true) end
		GameTooltip:AddLine("Click: switch to it (outside a fight)", 0, 0.9, 1)
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[i] = r
	return r
end

local function MaxRows()
	local n = tonumber(Opt().rows) or 12
	return math.max(1, math.min(40, n))
end

local function Paint()
	if not frame then return end
	local list = ShamanPower_TotemLoadouts or {}
	local active = SP.opt and SP.opt.activeLoadout
	local visible = MaxRows()
	offset = math.max(0, math.min(offset, #entries - visible))
	local y = 0
	for slot = 1, math.max(#rows, visible) do
		local r = rows[slot]
		local e = entries[slot + offset]
		if slot <= visible and e then
			r = r or NewRow(slot)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -y)
			r:SetPoint("RIGHT", frame.content, "RIGHT", 0, 0)
			if e.head then
				r.spIndex = nil
				r:SetHeight(HEAD_H)
				r:EnableMouse(false)
				r.bg:Hide(); r.mark:Hide(); r.inUse:Hide()
				r.square:Show()
				Font(r.text, "medium", 11)
				r.text:ClearAllPoints()
				r.text:SetPoint("LEFT", r.square, "RIGHT", 6, 0)
				r.text:SetPoint("RIGHT", r, "RIGHT", -PAD, 0)
				r.text:SetText(e.head)
				if e.raid then r.text:SetTextColor(Fire()) else r.text:SetTextColor(0.541, 0.580, 0.651) end
				for k = 1, 4 do r.icons[k]:Hide(); r.dashes[k]:Hide() end
				y = y + HEAD_H
			else
				local lo = list[e.index]
				local inUse = e.index == active
				r.spIndex = e.index
				r:SetHeight(ROW_H)
				r:EnableMouse(true)
				r.square:Hide()
				r.bg:SetShown(inUse)
				r.mark:SetShown(inUse)
				r.inUse:SetShown(inUse)
				Font(r.text, "regular", 12)
				r.text:ClearAllPoints()
				r.text:SetPoint("LEFT", r, "LEFT", PAD + 12, 0)
				r.text:SetPoint("RIGHT", inUse and r.inUse or r.icons[1], "LEFT", -6, 0)
				r.text:SetText(lo and (lo.name or ("Loadout " .. e.index)) or "?")
				r.text:SetTextColor(0.902, 0.918, 0.941)
				local h = math.max(ROW_H, math.ceil(r.text:GetStringHeight() or 0) + 8)
				r:SetHeight(h)
				for k = 1, 4 do
					local idx = lo and lo[k] or 0
					if idx > 0 then
						r.icons[k]:SetTexture(SP:GetTotemIcon(k, idx))
						r.icons[k]:Show()
						r.dashes[k]:Hide()
					else
						r.icons[k]:Hide()
						r.dashes[k]:Show()
					end
				end
				y = y + r:GetHeight()
			end
			r:Show()
		elseif r then
			r:Hide()
			r.spIndex = nil
		end
	end
	frame.content:SetHeight(math.max(1, y))
	-- more rows than fit: the wheel scrolls; a line under them says so
	local more = #entries > visible
	frame.more:SetShown(more)
	frame:SetHeight(y + PAD * 2 + 3 + (more and 14 or 0))
end

local function Restore()
	local o = Opt()
	frame:SetScale(tonumber(o.scale) or 1)
	if not (o.pos and SP:ApplyPositionRecord(frame, o.pos)) then SP:ApplyPositionRecord(frame, DEFAULT_POS) end
	local a = tonumber(o.opacity) or 0.9
	frame.bg:SetColorTexture(0.067, 0.094, 0.137, a)
end

local function Save()
	if frame then Opt().pos = SP:SavePositionRecord(frame) end
end

local function Make()
	if frame then return frame end
	frame = CreateFrame("Frame", "ShamanPowerLoadoutList", UIParent)
	frame:SetSize(WIDTH, 60)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetAllPoints(frame)
	-- the soft edge of the addon's windows, and its four elements along the top
	local edge = { { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
		{ "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }
	for _, e in ipairs(edge) do
		local t = frame:CreateTexture(nil, "BORDER")
		t:SetColorTexture(0.169, 0.216, 0.290, 1)
		t:SetPoint(e[1], frame, e[1])
		t:SetPoint(e[2], frame, e[2])
		if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
	end
	if SP.CreateElementStripe then
		local stripe = SP:CreateElementStripe(frame)
		stripe:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
		stripe:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
	end
	frame.content = CreateFrame("Frame", nil, frame)
	frame.content:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -(PAD + 3))
	frame.content:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -(PAD + 3))
	frame.more = frame:CreateFontString(nil, "OVERLAY")
	Font(frame.more, "regular", 10)
	frame.more:SetTextColor(0.541, 0.580, 0.651)
	frame.more:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 2)
	frame.more:SetText("Scroll for more")
	frame:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta
		Paint()
	end)
	-- ALT + drag moves it, as the loadout bar (Unlock UI moves it too)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(f)
		if Opt().locked or InCombatLockdown() or not IsAltKeyDown() then return end
		f:StartMoving()
		f.spMoving = true
	end)
	frame:SetScript("OnDragStop", function(f)
		if not f.spMoving then return end
		f:StopMovingOrSizing()
		f.spMoving = nil
		Save()
	end)
	Restore()
	frame:Hide()
	return frame
end

-- drawn again: on every loadout or place change (SP:UpdateLoadoutBar), a setting, a profile
function SP:UpdateLoadoutList()
	if not ListOn() then
		if frame then frame:Hide() end
		return
	end
	Make()
	Restore()
	Build()
	if #entries == 0 then frame:Hide() return end
	Paint()
	frame:Show()
end

if type(SP.UpdateLoadoutBar) == "function" then
	hooksecurefunc(SP, "UpdateLoadoutBar", function() SP:UpdateLoadoutList() end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	SP:UpdateLoadoutList()
	if SP.OnOnOff then SP:OnOnOff(function() SP:UpdateLoadoutList() end) end
	if SP.db and SP.db.RegisterCallback then
		local key = {}
		local function reload() SP:UpdateLoadoutList() end
		SP.db.RegisterCallback(key, "OnProfileChanged", reload)
		SP.db.RegisterCallback(key, "OnProfileCopied", reload)
		SP.db.RegisterCallback(key, "OnProfileReset", reload)
	end
end)

-- ---------------------------------------------------------------------------
-- Unlock UI: its own box (Move the Loadout List)
-- ---------------------------------------------------------------------------
-- Unlock UI boxes a module only when a preview is registered under its key: a frame-only one,
-- as the loadout bar's (ShamanPowerUnlock.lua), or neither Unlock UI nor Move showed a box
if SP.RegisterPreview and SP.PreviewRegistry and not SP.PreviewRegistry.loadoutlist then
	SP:RegisterPreview("loadoutlist", { frame = "ShamanPowerLoadoutList" })
end
if SP.UnlockModules then
	table.insert(SP.UnlockModules, {
		key = "loadoutlist", label = "Loadout List",
		enabled = function() return ListOn() end,
		frames = function()
			if not ListOn() then return {} end
			SP:UpdateLoadoutList()
			return frame and frame:IsShown() and { frame } or {}
		end,
		save = function() Save() end,
		reset = function()
			if not frame then return end
			Opt().pos = nil
			SP:ApplyPositionRecord(frame, DEFAULT_POS)
		end,
	})
end

-- ---------------------------------------------------------------------------
-- Settings: Loadouts > Loadout List (fluffy.loadoutlist_section)
-- ---------------------------------------------------------------------------
local function Set(key)
	return function(_, v)
		Opt()[key] = v
		SP:UpdateLoadoutList()
	end
end
local function Off() return not Opt().enabled end

if SP.options and SP.options.args and SP.options.args.fluffy and SP.options.args.fluffy.args then
	local group = { type = "group", name = "Loadout List", order = 11.1, args = {
		intro = {
			order = 1, type = "description", width = "full",
			name = "A list of the loadouts that show here, with their four totems: click one to switch to it, outside a fight."
				.. " It follows your Auto Loadout Groups as the loadout flyout does (Everywhere, then this place's group)."
				.. " Hidden loadouts never show.",
		},
		enabled = {
			order = 2, type = "toggle", width = "full", name = "Enable Loadout List",
			desc = "Show the Loadout List on your screen. Off by default. The loadout bar can stay on too.",
			get = function() return Opt().enabled == true end,
			set = function(_, v) Opt().enabled = v and true or nil; SP:UpdateLoadoutList() end,
		},
		scale = {
			order = 3, type = "range", name = "Scale", isPercent = true, width = 1.5,
			min = 0.5, max = 2, step = 0.05, disabled = Off,
			get = function() return tonumber(Opt().scale) or 1 end, set = Set("scale"),
		},
		opacity = {
			order = 4, type = "range", name = "Background Opacity", isPercent = true, width = 1.5,
			desc = "Fades only the panel behind the list. The names and the totems stay as they are.",
			min = 0, max = 1, step = 0.05, disabled = Off,
			get = function() return tonumber(Opt().opacity) or 0.9 end, set = Set("opacity"),
		},
		rows = {
			order = 5, type = "range", name = "Visible Rows", width = "full",
			desc = "The most rows it shows at once (headings count). More scroll with the mouse wheel.",
			min = 3, max = 40, step = 1, disabled = Off,
			get = function() return tonumber(Opt().rows) or 12 end, set = Set("rows"),
		},
		move = {
			order = 6, type = "execute", width = "full", name = "Move the Loadout List",
			desc = "Hides this window and draws a box around the Loadout List on your screen. Drag it where you want it, then press Done to come back here.",
			disabled = function() return Off() or not SP.UnlockModuleFrames or InCombatLockdown() end,
			func = function() SP:UnlockModuleFrames("loadoutlist") end,
		},
		locked = {
			order = 7, type = "toggle", width = "full", name = "Lock ALT+Drag",
			desc = "On: holding ALT and dragging the list does not move it. Move the Loadout List still does.",
			disabled = Off,
			get = function() return Opt().locked == true end,
			set = function(_, v) Opt().locked = v and true or nil end,
		},
	} }
	SP.options.args.fluffy.args.loadoutlist_section = group
	if SP.OrderSettingsBands then
		SP.OrderSettingsBands(group, {
			{ keys = { "intro", "enabled" } },
			{ header = "look_header", name = "Look", keys = { "scale", "opacity", "rows" } },
			{ header = "position_header", name = "Position", keys = { "move", "locked" } },
		})
	end
end
