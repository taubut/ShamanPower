-- ShamanPower_Config :: RaidCD
-- The Raid Cooldowns assignment panel (Bloodlust/Heroism primary + backups +
-- caller, and a Mana Tide caller per shaman), rebuilt on the dialog chrome.
-- Data, permissions and comms stay in ShamanPower_RaidCooldowns; only the
-- window is replaced. If that module is not loaded this file does nothing and
-- the engine's "module not loaded" stub remains.

local ADDON, ns = ...
local Core    = ns.Core
local Widgets = ns.Widgets

local SP = ShamanPower
if not SP or not SP.GetRaidShamans or not SP.SendRaidCooldownSync then return end

local WIDTH = 380
local NONE  = ""
local dlg

local function Build()
	if dlg then return dlg end
	local faction = UnitFactionGroup("player")
	dlg = Core:CreateDialog({
		name = "ShamanPowerRaidCooldownPanel",
		width = WIDTH, height = 300,
		title = "Raid Cooldowns",
		subtitle = ((faction == "Alliance") and "Heroism" or "Bloodlust") .. " & Mana Tide",
		headerHeight = 46, bodyTop = 6,
	})
	dlg:SetFrameStrata("DIALOG")
	-- The module refreshes "the panel" when a sync arrives; point it at ours.
	SP.raidCooldownPanel = dlg
	return dlg
end

local function ListValues(names)
	local values, order = { [NONE] = "|cff8A94A6\226\128\148 None \226\128\148|r" }, { NONE }
	for _, n in ipairs(names) do
		values[n] = n
		order[#order + 1] = n
	end
	return function() return values end, function() return order end
end

local function CanAssign()
	return SP:CanAssignRaidCooldowns()
end

local function Populate()
	SP:InitRaidCooldowns()
	local bl = ShamanPower_RaidCooldowns.bloodlust
	local mt = ShamanPower_RaidCooldowns.manatide
	local shamans = SP:GetRaidShamans()
	local members = SP:GetRaidMembers()
	local blName = (UnitFactionGroup("player") == "Alliance") and "Heroism" or "Bloodlust"
	local locked = not CanAssign()
	local lockNote = locked and " |cffff4444Leader or assist only.|r" or ""

	local body = dlg.body
	Widgets:ReleaseAll(body)
	local width = WIDTH - dlg.pad * 2
	local y = 0
	local function Row(kind, opts)
		opts.x, opts.y, opts.width = 0, y, width
		local f, h = Widgets[kind](Widgets, body, opts)
		y = y + h
		return f
	end

	-- Bloodlust / Heroism ---------------------------------------------------
	Row("SectionHeader", { label = blName .. " assignment" })
	local shamanValues, shamanOrder = ListValues(shamans)
	local memberValues, memberOrder = ListValues(members)

	local function BlRow(label, field, desc, values, order, extra)
		Row("Dropdown", {
			label = label, desc = desc .. lockNote,
			values = values, order = order,
			get = function() return bl[field] or NONE end,
			set = function(v)
				bl[field] = (v ~= NONE) and v or nil
				SP:SendRaidCooldownSync()
				if extra then extra() end
			end,
			disabled = function() return not CanAssign() end,
		})
	end
	BlRow("Primary",  "primary", "Shaman who pops " .. blName .. " when called.", shamanValues, shamanOrder)
	BlRow("Backup 1", "backup1", "Used if the primary is dead.", shamanValues, shamanOrder)
	BlRow("Backup 2", "backup2", "Used if the primary and first backup are dead.", shamanValues, shamanOrder)
	BlRow("Caller",   "caller",  "Who is allowed to call " .. blName .. " (besides leader/assists).", memberValues, memberOrder,
		function() SP:UpdateCallerButtons() end)

	-- Mana Tide -------------------------------------------------------------
	y = y + 4
	Row("SectionHeader", { label = "Mana Tide callers", note = "one caller per shaman" })
	local mtShamans = SP:GetManaTideShamans()
	if #mtShamans == 0 then
		Row("Description", { text = "No shamans in the group." })
	end
	for _, info in ipairs(mtShamans) do
		local name = info.name
		Row("Dropdown", {
			label = name .. "  |cff8A94A6G" .. tostring(info.group) .. "|r",
			desc = "Who may call " .. name .. "'s Mana Tide." .. lockNote,
			values = memberValues, order = memberOrder,
			get = function() return mt[name] and mt[name].caller or NONE end,
			set = function(v)
				mt[name] = mt[name] or {}
				mt[name].caller = (v ~= NONE) and v or nil
				SP:SendRaidCooldownSync()
				SP:UpdateCallerButtons()
			end,
			disabled = function() return not CanAssign() end,
		})
	end

	dlg:SetHeight(46 + 4 + 6 + y + dlg.pad + 2)
end

-- ---------------------------------------------------------------------------
-- Engine entry points (replace the module's window; data functions untouched)
-- ---------------------------------------------------------------------------
function SP:ToggleRaidCooldownPanel()
	Build()
	if dlg:IsShown() then
		dlg:Hide()
	else
		Populate()
		dlg:Show()
		SP:UpdateCallerButtons()
	end
end

function SP:UpdateRaidCooldownPanel()
	if dlg and dlg:IsShown() then Populate() end
	SP:UpdateCallerButtons()
end

-- Roster changes while open: rebuild the member lists (debounced).
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
watcher:RegisterEvent("PLAYER_ROLES_ASSIGNED")
watcher:SetScript("OnEvent", function()
	if not (dlg and dlg:IsShown()) or watcher.pending then return end
	watcher.pending = true
	C_Timer.After(0.5, function()
		watcher.pending = nil
		if dlg and dlg:IsShown() then Populate() end
	end)
end)

-- Settings panel for the floating caller buttons (the corner button).
local FS = ns.FrameSettings
if FS then
	local function Notify()
		local reg = LibStub and LibStub("AceConfigRegistry-3.0", true)
		if reg then reg:NotifyChange("ShamanPower") end
	end
	FS.specs.raidcd = function(frame)
		return {
			key = "raidcd", title = "Caller Buttons", subtitle = "Raid cooldowns",
			scale = {
				min = 50, max = 200,
				get = function() return math.floor((SP.opt.raidCDButtonScale or 1) * 100 + 0.5) end,
				set = function(v) SP.opt.raidCDButtonScale = v / 100; SP:UpdateCallerButtonScale(); Notify() end,
			},
			opacity = {
				get = function() return math.floor((SP.opt.raidCDButtonOpacity or 1) * 100 + 0.5) end,
				set = function(v) SP.opt.raidCDButtonOpacity = v / 100; SP:UpdateCallerButtonOpacity(); Notify() end,
			},
			hideFrame = {
				get = function() return SP.opt.raidCDButtonHideFrame and true or false end,
				set = function(v) SP.opt.raidCDButtonHideFrame = v and true or nil; SP:UpdateCallerButtonFrameStyle() end,
			},
		}
	end
end

return true
