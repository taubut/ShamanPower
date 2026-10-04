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
-- The window's own element (D32: Raid Cooldowns is a Group Tools window, so Water):
-- the header band's light, the title's underline, the section cards' strips
local ELEMENT  = "water"
local CARD_TOP, CARD_GAP = 6, 12   -- the settings page's: over the first card, between cards
local dlg
local registry = _G.LibStub("AceConfigRegistry-3.0", true)
local function Notify()
	if registry then registry:NotifyChange("ShamanPower") end
end

local function HasBL() return not (SPCompat and SPCompat.HasBloodlust) or SPCompat.HasBloodlust() end
local function HasDrums() return not (SPCompat and SPCompat.HasDrums) or SPCompat.HasDrums() end

local function Subtitle()
	local parts = {}
	if HasBL() then
		local alliance = UnitFactionGroup("player") == "Alliance"
		parts[#parts + 1] = SPCompat.SpellLabel(alliance and 32182 or 2825, alliance and "Heroism" or "Bloodlust")
	end
	parts[#parts + 1] = SPCompat.SpellLabel(16190, "Mana Tide")
	if HasDrums() then parts[#parts + 1] = SPCompat.SpellLabel(35476, "Drums") end
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
		element = ELEMENT,
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

-- A section's note beside its name on the card's strip ("one caller per shaman"), in
-- the caption font the section headings had; one per section, made once and kept
local notes = {}
local function Note(i, card, text)
	local n = notes[i]
	if not n then
		n = CreateFrame("Frame", nil, dlg.body)   -- (a frame: over the card under it)
		n:SetSize(1, 1)
		n.text = n:CreateFontString(nil, "OVERLAY")
		n.text:SetFontObject(Core.fonts.tiny)
		n.text:SetPoint("LEFT", n, "LEFT", 0, 0)
		notes[i] = n
	end
	n:ClearAllPoints()
	n:SetPoint("LEFT", card.label, "RIGHT", 8, 0)
	n.text:SetText(text)
	n:Show()
end

local function Populate()
	SP:InitRaidCooldowns()
	local bl = ShamanPower_RaidCooldowns.bloodlust
	local mt = ShamanPower_RaidCooldowns.manatide
	local shamans = SP:GetRaidShamans()
	local members = SP:GetRaidMembers()
	local blName = (UnitFactionGroup("player") == "Alliance") and "Heroism" or "Bloodlust"
	blName = SPCompat.SpellLabel(UnitFactionGroup("player") == "Alliance" and 32182 or 2825, blName)
	local tideName = SPCompat.SpellLabel(16190, "Mana Tide")
	local locked = not CanAssign()
	local lockNote = locked and " |cffff4444Group leader or assistant only.|r" or ""

	local body = dlg.body
	Widgets:ReleaseAll(body)
	for i = 1, #notes do notes[i]:Hide() end
	local width = WIDTH - dlg.pad * 2
	local INSET = Widgets.CARD_INSET
	local y = CARD_TOP
	-- One card per section (the settings page's, D30 6 / D32b): a strip with the
	-- element's tiny box and the section's name, the section's rows in it with a thin
	-- line between them. The rows take the window's element.
	local card, cardTop, cardRows, noteCount = nil, 0, 0, 0
	Widgets:SetElement(ELEMENT)
	local function CloseCard()
		if not card then return end
		Widgets:CardFinish(card, y - cardTop)
		y = y + CARD_GAP
		card = nil
	end
	local function Section(label, note)
		CloseCard()
		card = Widgets:Card(body, { x = 0, y = y, width = width, label = label, element = ELEMENT })
		cardTop, cardRows = y, 0
		y = y + Widgets.STRIP_H
		if note and card.label then
			noteCount = noteCount + 1
			Note(noteCount, card, note)
		end
	end
	local function Row(kind, opts)
		opts.x, opts.y, opts.width, opts.inCard = INSET, y, width - 2 * INSET, true
		if cardRows > 0 then Widgets:CardLine(card, 12, y - cardTop, width - 24, 1, "borderSoft") end
		local f, h = Widgets[kind](Widgets, body, opts)
		y = y + h
		cardRows = cardRows + 1
		return f
	end

	local shamanValues, shamanOrder = ListValues(shamans)
	local memberValues, memberOrder = ListValues(members)

	-- Bloodlust / Heroism ---------------------------------------------------
	if HasBL() then
		Section(blName .. " assignment")

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
		BlRow("Caller",   "caller",  "Who can call for " .. blName .. " besides the group leader and assistants.", memberValues, memberOrder,
			function() SP:UpdateCallerButtons() end)
	end

	-- Mana Tide -------------------------------------------------------------
	Section(tideName .. " callers", "one caller per shaman")
	local mtShamans = SP:GetManaTideShamans()
	if #mtShamans == 0 then
		Row("Description", { text = "No shaman in your group has " .. SPCompat.SpellLabel(16190, "Mana Tide Totem") .. "." })
	end
	for _, info in ipairs(mtShamans) do
		local name = info.name
		Row("Dropdown", {
			label = name .. "  |cff8A94A6G" .. tostring(info.group) .. "|r",
			desc = "Who may call " .. name .. "'s " .. tideName .. "." .. lockNote,
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
		Section(SPCompat.SpellLabel(35476, "Drums of Battle"), "one drummer per group")
		local drums = ShamanPower_RaidCooldowns.drums
		Row("Dropdown", {
			label = "Caller", desc = "Who can call for Drums besides the group leader and assistants." .. lockNote,
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
	CloseCard()
	y = y - CARD_GAP   -- no gap under the last card
	Widgets:SetElement(nil)

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
			element = ELEMENT,
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
					SP.opt.raidCDButtonHideFrame = v and true or false
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
