-- ShamanPower_Config / MobList.lua
-- Tremor Reminder's fear-caster mob list, drawn with the config kit. Replaces
-- the module's Blizzard-template window (this addon loads after the module).
local _, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not SP then return end

local frame
local rows = {}
local ROW_H = 24

local function DB()
	ShamanPowerTremorReminderDB = ShamanPowerTremorReminderDB or {}
	ShamanPowerTremorReminderDB.fearCasters = ShamanPowerTremorReminderDB.fearCasters or {}
	return ShamanPowerTremorReminderDB
end

-- Same semantics as the module: defaults (unless hidden with = false) plus
-- custom additions (= true and not a default).
local function BuildList()
	local sv = DB()
	local defaults = SP.GetDefaultFearCasters and SP:GetDefaultFearCasters() or {}
	local mobs, hiddenDefaults = {}, 0
	if sv.useDefaultList ~= false then
		for name in pairs(defaults) do
			if sv.fearCasters[name] ~= false then table.insert(mobs, { name = name, custom = false }) else hiddenDefaults = hiddenDefaults + 1 end
		end
	end
	for name, enabled in pairs(sv.fearCasters) do
		if enabled and not defaults[name] then table.insert(mobs, { name = name, custom = true }) end
	end
	table.sort(mobs, function(a, b) return a.name < b.name end)
	return mobs, hiddenDefaults
end

local function AddName(name)
	name = name and strtrim(name) or ""
	if name == "" then return end
	DB().fearCasters[name] = true
	SP:RefreshMobList()
end

local function Build()
	if frame then return frame end
	frame = Core:CreateDialog({
		name = "ShamanPowerMobListFrame", width = 400, height = 520,
		title = "Fear-Caster Mobs", subtitle = "tremor reminder watches these", headerHeight = 46, footer = 44,
		special = true, strata = "DIALOG",
	})
	local body = frame.body

	-- add row: [ name ............ ] [Add] [Add target]
	local hint = body:CreateFontString(nil, "OVERLAY"); hint:SetFontObject(Core.fonts.rowDim)
	hint:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0); hint:SetText("Add a mob by name, or target one and add it.")
	local box = CreateFrame("EditBox", nil, body)
	box:SetSize(180, 24); box:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
	box:SetAutoFocus(false); box:SetFontObject(Core.fonts.row); box:SetTextInsets(6, 6, 0, 0)
	Core:SolidTex(box, "windowBg", "BACKGROUND"); Core:MakeBorder(box, "border")
	box:SetScript("OnEditFocusGained", function() Core:SetBorderColor(box, "accent") end)
	box:SetScript("OnEditFocusLost", function() Core:SetBorderColor(box, "border") end)
	box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) AddName(self:GetText()); self:SetText(""); self:ClearFocus() end)
	frame.box = box
	local add = Core:MakeButton(body, "Add", 60, true); add:SetPoint("LEFT", box, "RIGHT", 6, 0)
	add:SetScript("OnClick", function() AddName(box:GetText()); box:SetText(""); box:ClearFocus() end)
	local tgt = Core:MakeButton(body, "Add target", 100, false); tgt:SetPoint("LEFT", add, "RIGHT", 6, 0)
	tgt:SetScript("OnClick", function()
		local name = UnitName("target")
		if name and UnitCanAttack("player", "target") then AddName(name)
		else print("|cff0070ddShamanPower|r: target an enemy first.") end
	end)

	-- list
	local listBg = CreateFrame("Frame", nil, body)
	listBg:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -10); listBg:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
	Core:SolidTex(listBg, "contentBg", "BACKGROUND"); Core:MakeBorder(listBg, "borderSoft")
	local scroll = CreateFrame("ScrollFrame", nil, listBg)
	scroll:SetPoint("TOPLEFT", listBg, "TOPLEFT", 4, -4); scroll:SetPoint("BOTTOMRIGHT", listBg, "BOTTOMRIGHT", -16, 4)
	local child = CreateFrame("Frame", nil, scroll); child:SetSize(10, 10); scroll:SetScrollChild(child)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local maxS = math.max(0, child:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.max(0, math.min(maxS, self:GetVerticalScroll() - delta * ROW_H * 3)))
	end)
	Core:AttachScrollbar(scroll, child, { offset = 4 })
	frame.scroll, frame.child = scroll, child

	-- footer: count + restore
	local count = frame:CreateFontString(nil, "OVERLAY"); count:SetFontObject(Core.fonts.tiny)
	count:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16); count:SetTextColor(Core:Color("textDim"))
	frame.count = count
	local restore = Core:MakeButton(frame, "Restore removed defaults", 10, false)
	restore:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 10)
	restore:SetScript("OnClick", function()
		local sv, defaults = DB(), SP:GetDefaultFearCasters()
		for name, v in pairs(sv.fearCasters) do if v == false and defaults[name] then sv.fearCasters[name] = nil end end
		SP:RefreshMobList()
	end)
	frame.restore = restore
	return frame
end

local function Row(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, frame.child); r:SetHeight(ROW_H)
	r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(r)
	r.name = r:CreateFontString(nil, "OVERLAY"); r.name:SetFontObject(Core.fonts.row); r.name:SetPoint("LEFT", r, "LEFT", 8, 0); r.name:SetJustifyH("LEFT")
	r.tag = r:CreateFontString(nil, "OVERLAY"); r.tag:SetFontObject(Core.fonts.tiny); r.tag:SetPoint("RIGHT", r, "RIGHT", -34, 0); r.tag:SetTextColor(Core:Color("accentHi")); r.tag:SetText("custom")
	r.del = CreateFrame("Button", nil, r); r.del:SetSize(20, 20); r.del:SetPoint("RIGHT", r, "RIGHT", -6, 0)
	Core:MakeBorder(r.del, "border")
	local x = r.del:CreateFontString(nil, "OVERLAY"); x:SetFontObject(Core.fonts.tiny); x:SetPoint("CENTER"); x:SetText("X"); x:SetTextColor(Core:Color("textDim"))
	r.del:SetScript("OnEnter", function(self) Core:SetBorderColor(self, "warn"); x:SetTextColor(Core:Color("warn")) end)
	r.del:SetScript("OnLeave", function(self) Core:SetBorderColor(self, "border"); x:SetTextColor(Core:Color("textDim")) end)
	r.del:SetScript("OnClick", function(self)
		local mob = r.mob; if not mob then return end
		if mob.custom then DB().fearCasters[mob.name] = nil else DB().fearCasters[mob.name] = false end   -- defaults are hidden, not deleted
		SP:RefreshMobList()
	end)
	r:SetScript("OnEnter", function(self) self.bg:SetColorTexture(Core:Color("rowHover")) end)
	r:SetScript("OnLeave", function(self) self.bg:SetColorTexture(Core:Color("rowBg", (self.idx % 2 == 0) and 0.5 or 0.25)) end)
	r:EnableMouse(true)
	rows[i] = r
	return r
end

function SP:RefreshMobList()
	if not frame then return end
	local mobs, hidden = BuildList()
	local w = frame.scroll:GetWidth()
	for i, mob in ipairs(mobs) do
		local r = Row(i)
		r.mob, r.idx = mob, i
		r:ClearAllPoints(); r:SetPoint("TOPLEFT", frame.child, "TOPLEFT", 0, -((i - 1) * ROW_H)); r:SetWidth(w)
		r.name:SetText(mob.name); r.name:SetTextColor(Core:Color(mob.custom and "accentHi" or "text"))
		r.tag:SetShown(mob.custom)
		r.bg:SetColorTexture(Core:Color("rowBg", (i % 2 == 0) and 0.5 or 0.25))
		r:Show()
	end
	for i = #mobs + 1, #rows do rows[i]:Hide(); rows[i].mob = nil end
	frame.child:SetSize(w, math.max(1, #mobs * ROW_H))
	local defaultsOff = DB().useDefaultList == false
	frame.count:SetText(#mobs .. " mobs" .. (hidden > 0 and ("  -  " .. hidden .. " default" .. (hidden == 1 and "" or "s") .. " removed") or "") .. (defaultsOff and "  -  built-in list is OFF" or ""))
	frame.restore:SetShown(hidden > 0)
end

function SP:ShowMobList() Build(); frame:Show(); self:RefreshMobList() end
function SP:HideMobList() if frame then frame:Hide() end end
function SP:ToggleMobList() if frame and frame:IsShown() then self:HideMobList() else self:ShowMobList() end end
