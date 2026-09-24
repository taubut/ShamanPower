-- ShamanPower_Config :: RaidCD
-- The Raid Cooldowns assignment panel (Bloodlust/Heroism primary + backups +
-- caller, a Mana Tide caller per shaman, and Drums), rebuilt on the dialog
-- chrome. Sections for spells this client does not have (WoW: Forever has no
-- Bloodlust / Heroism and no Drums of Battle) are not built at all.
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
local registry = _G.LibStub("AceConfigRegistry-3.0", true)
local function Notify()
	if registry then registry:NotifyChange("ShamanPower") end
end

local function HasBL() return not (SPCompat and SPCompat.HasBloodlust) or SPCompat.HasBloodlust() end
local function HasDrums() return not (SPCompat and SPCompat.HasDrums) or SPCompat.HasDrums() end

local function Subtitle()
	local parts = {}
	if HasBL() then parts[#parts + 1] = (UnitFactionGroup("player") == "Alliance") and "Heroism" or "Bloodlust" end
	parts[#parts + 1] = "Mana Tide"
	if HasDrums() then parts[#parts + 1] = "Drums" end
	if #parts == 1 then return parts[1] .. " calling" end
	return table.concat(parts, ", ", 1, #parts - 1) .. " & " .. parts[#parts]
end

local function Build()
	if dlg then return dlg end
	dlg = Core:CreateDialog({
		name = "ShamanPowerRaidCooldownPanel",
		width = WIDTH, height = 300,
		title = "Raid Cooldowns",
		subtitle = Subtitle(),
		headerHeight = 46, bodyTop = 6,
		special = true, strata = "DIALOG",
	})
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

	local shamanValues, shamanOrder = ListValues(shamans)
	local memberValues, memberOrder = ListValues(members)

	-- Bloodlust / Heroism ---------------------------------------------------
	if HasBL() then
		Row("SectionHeader", { label = blName .. " assignment" })

		local function BlRow(label, field, desc, values, order, extra)
			Row("Dropdown", {
				label = label, desc = desc .. lockNote,
				values = values, order = order,
				get = function() return bl[field] or NONE end,
				set = function(v)
					bl[field] = (v ~= NONE) and v or nil
					SP:SendRaidCooldownSync()
					if extra then extra() end
					Notify()
				end,
				disabled = function() return not CanAssign() end,
			})
		end
		BlRow("Primary",  "primary", "Shaman who pops " .. blName .. " when called.", shamanValues, shamanOrder)
		BlRow("Backup 1", "backup1", "Used if the primary is dead.", shamanValues, shamanOrder)
		BlRow("Backup 2", "backup2", "Used if the primary and first backup are dead.", shamanValues, shamanOrder)
		BlRow("Caller",   "caller",  "Who is allowed to call " .. blName .. " (besides leader/assists).", memberValues, memberOrder,
			function() SP:UpdateCallerButtons() end)
	end

	-- Mana Tide -------------------------------------------------------------
	if y > 0 then y = y + 4 end
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
				Notify()
			end,
			disabled = function() return not CanAssign() end,
		})
	end

	-- Drums of Battle --------------------------------------------------------
	if HasDrums() then
		y = y + 4
		Row("SectionHeader", { label = "Drums of Battle", note = "one drummer per group" })
		local drums = ShamanPower_RaidCooldowns.drums
		Row("Dropdown", {
			label = "Caller", desc = "Who is allowed to call for Drums (besides leader/assists)." .. lockNote,
			values = memberValues, order = memberOrder,
			get = function() return drums.caller or NONE end,
			set = function(v)
				drums.caller = (v ~= NONE) and v or nil
				SP:SendRaidCooldownSync()
				SP:UpdateCallerButtons()
				Notify()
			end,
			disabled = function() return not CanAssign() end,
		})
		local groups = SP:GetGroupMembers()
		local groupIds = {}
		for g in pairs(groups) do table.insert(groupIds, g) end
		table.sort(groupIds)
		for _, g in ipairs(groupIds) do
			local gValues, gOrder = ListValues(groups[g])
			Row("Dropdown", {
				label = IsInRaid() and ("Group " .. tostring(g)) or "Party",
				desc = "Drummer for this group. Drums only affect the drummer's own group." .. lockNote,
				values = gValues, order = gOrder,
				get = function() return drums.drummers[g] or NONE end,
				set = function(v)
					drums.drummers[g] = (v ~= NONE) and v or nil
					SP:SendRaidCooldownSync()
					SP:UpdateCallerButtons()
					Notify()
				end,
				disabled = function() return not CanAssign() end,
			})
	end
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
				set = function(v)
					SP.opt.raidCDButtonHideFrame = v and true or nil
					SP:UpdateCallerButtonFrameStyle(); Notify()
				end,
			},
		}
	end
end

if registry and registry.RegisterCallback then
	local queued = false
	registry.RegisterCallback({}, "ConfigTableChange", function(_, appName)
		if appName ~= "ShamanPower" or queued or not (dlg and dlg:IsShown()) then return end
		queued = true
		_G.C_Timer.After(0, function()
			queued = false
			if dlg and dlg:IsShown() then Populate() end
		end)
	end)
end

return true
