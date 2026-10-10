-- ShamanPower_Config :: LoadoutIcons
-- Loadouts > Loadouts (A17 part B, 3.0.8): the Saved Loadouts row and every loadout's right-click
-- menu, on the shared icon row (IconRow.lua, with its optional label / mark / add). A tile per
-- saved loadout (ShamanPower_TotemLoadouts, shared by your characters): its own icon, else its
-- first totem's (SP:GetLoadoutIcon), its name under it (wraps, never cut short), a green bar under
-- the one in use. Click: switch to it (SP:ApplyLoadout, as a click on the loadout bar).
-- Right-click: its menu, which changes that loadout without switching to it: Switch To This
-- Loadout, its 4 totems, Drop All, Blizzard Totem Set (WoW: Forever, once Call of the Ancestors or
-- Call of the Spirits is known), Rename..., Icon..., Delete This Loadout... (the same rows the page
-- had for each loadout, the same calls). Drag: its place (SP:MoveLoadout: the loadout bar's order
-- and its click cycle; Auto-Switch follows each loadout's own id, the one in use stays in use).
-- +: a new loadout from the totems on your bar now, put in use (SP:CreateLoadout, as Create
-- Loadout did), then a box to name it. Switching loadouts is out of a fight only, on both games:
-- the page locks in a fight, and a click, drag, menu choice or dialog button refuses (and says so)
-- while InCombatLockdown(). Nothing here runs while the page is closed.
local _, ns = ...
local Core = ns.Core
local SP = ShamanPower
if not (Core and SP and ns.IconRow) then return end

local Menu = ns.IconRow.Menu
local SEP = { separator = true }
local ELEMENTS = { "Earth", "Fire", "Water", "Air" }
local MAX_LOADOUTS = 8   -- SP:SaveLoadout / SP:CreateLoadout's limit
local MAX_NAME = 32      -- the name box's letters
local Row

-- (the words that say what to do in the settings' blue, so a player sees them first)
local CAPTION = "|cff3FA9F5CLICK|r a loadout to switch to it (the green bar: the one in use). |cff3FA9F5RIGHT-CLICK|r it"
	.. " to change its totems, name, icon or Drop All. |cff3FA9F5DRAG|r it to change its place on the loadout bar."
	.. " |cff3FA9F5+|r saves a new one from the totems on your bar now."
local CAPTION_FULL = "|cff3FA9F5CLICK|r a loadout to switch to it (the green bar: the one in use). |cff3FA9F5RIGHT-CLICK|r"
	.. " it to change its totems, name, icon or Drop All. |cff3FA9F5DRAG|r it to change its place on the loadout bar."
	.. " 8 of 8 saved: delete one to make room for a new one."
local CAPTION_NONE = "No loadouts saved yet. |cff3FA9F5+|r saves one from the totems on your bar now: your 4 totems and"
	.. " which of them Drop All leaves out."
local COMBAT = "|cff0070ddShamanPower|r: |cffe64a4aLoadouts can't change in combat - try again after the fight.|r"

-- ---------------------------------------------------------------------------
-- The loadouts: each tile's key is the loadout itself, so a drag, a delete or a menu left open
-- always finds the right one (its place in the list is looked up when it is used)
-- ---------------------------------------------------------------------------
local function List() return ShamanPower_TotemLoadouts or {} end

local function IndexOf(lo)
	if not lo then return nil end
	for i, x in ipairs(List()) do
		if x == lo then return i end
	end
	return nil
end

local function NameOf(lo)
	if lo and lo.name then return lo.name end
	return "Loadout " .. (IndexOf(lo) or "?")
end

local function InUse(lo)
	local i = IndexOf(lo)
	return i ~= nil and SP.opt ~= nil and SP.opt.activeLoadout == i
end

local function Refuse()
	if not InCombatLockdown() then return false end
	print(COMBAT)
	return true
end

-- the page laid out again (a new, renamed or deleted loadout changes the tiles)
local function Redraw()
	local cfg = _G.ShamanPowerConfig
	if cfg and cfg.RefreshCurrent then cfg:RefreshCurrent() end
end

-- ---------------------------------------------------------------------------
-- Blizzard's totem sets (WoW: Forever): Set Page and Send to Set Now, once Call of the
-- Ancestors or Call of the Spirits is known (before that the page's note says when they come)
-- ---------------------------------------------------------------------------
local PAGE_NAMES = { [2] = "Call of the Ancestors", [3] = "Call of the Spirits" }

local function HasSetControls()
	return (SPCompat and SPCompat.FOREVER and SP.HasTotemBar and SP:HasTotemBar()) and true or false
end

local function KnownPages()
	if not (HasSetControls() and SP.KnownTotemSetPages) then return {} end
	return SP:KnownTotemSetPages() or {}
end

-- its set page while that Call spell is known (as the old Set Page row read it), else 0 (None)
local function SetPageOf(lo)
	local i = IndexOf(lo)
	if i and HasSetControls() and SP.BoundLoadoutSummon and SP:BoundLoadoutSummon(i) then return lo.setPage or 0 end
	return 0
end

-- ---------------------------------------------------------------------------
-- The menu
-- ---------------------------------------------------------------------------
-- the loadout in use, changed in its menu since it was switched to: its saved totems are not the
-- ones on your bar now (a click on its tile, or Switch To This Loadout, puts them on the bar again)
local function Differs(lo)
	if not InUse(lo) then return false end
	local mine = ShamanPower_Assignments and SP.player and ShamanPower_Assignments[SP.player] or {}
	for e = 1, 4 do
		if (lo[e] or 0) ~= (mine[e] or 0) then return true end
	end
	return false
end

local function Switch(lo)
	local i = IndexOf(lo)
	if i and (not InUse(lo) or Differs(lo)) then SP:ApplyLoadout(i) end
end

-- every totem of an element this game has, in the old Edit totems dropdown's order
local function TotemIndexes(e)
	local out = {}
	local forever = SPCompat and SPCompat.FOREVER
	for idx in pairs(SP.TotemNames and SP.TotemNames[e] or {}) do
		if not forever or (SP.TotemExistsOnClient and SP:TotemExistsOnClient(e, idx)) then out[#out + 1] = idx end
	end
	table.sort(out)
	return out
end

local function SetTotem(lo, e, idx)
	local i = IndexOf(lo)
	if i then SP:SetLoadoutTotem(i, e, idx) end
	Row:Changed(true)   -- (its icon is its first totem's when it has none of its own)
	return true
end

local function TotemChoices(lo, e)
	local cur = lo[e] or 0
	local out = { { text = "None", selected = cur == 0, onClick = function() return SetTotem(lo, e, 0) end } }
	for _, idx in ipairs(TotemIndexes(e)) do
		local name = SP:GetTotemName(e, idx) or ("Totem " .. idx)
		-- a totem this character hasn't learned stays pickable, marked (the game won't drop it yet)
		local learned = not SP.KnowsTotem or SP:KnowsTotem(e, idx)
		out[#out + 1] = { text = learned and name or (name .. "  |cff8A94A6(not learned)|r"), icon = SP:GetTotemIcon(e, idx),
			selected = idx == cur, onClick = function() return SetTotem(lo, e, idx) end }
	end
	return out
end

local function DropAllRows(lo)
	local r = {}
	for e = 1, 4 do
		r[#r + 1] = Menu.OnOff("Leave Out " .. ELEMENTS[e], function()
			local i = IndexOf(lo)
			local v = (i and SP:LoadoutExcluded(i, e)) and true or false
			return v, v   -- (On is not the usual: in blue)
		end, function(v)
			local i = IndexOf(lo)
			if i then SP:SetDropAllExclude(e, v and true or false, i) end
			Row:Changed(true)
			return true
		end, "Leaves " .. ELEMENTS[e] .. " out of Drop All and Call of the Elements while this loadout is in use.")
	end
	return r
end

local function DropAllValue(lo)
	local i = IndexOf(lo)
	local outs = {}
	for e = 1, 4 do
		if i and SP:LoadoutExcluded(i, e) then outs[#outs + 1] = ELEMENTS[e] end
	end
	if #outs == 0 then return "All Four", false end
	return "Leaves Out " .. table.concat(outs, ", "), true
end

local function SetRows(lo)
	local known = KnownPages()
	local pages = { { 0, "None" } }
	for page = 2, 3 do
		if known[page] then pages[#pages + 1] = { page, PAGE_NAMES[page] } end
	end
	return {
		Menu.Choice("Set Page", pages, function()
			local p = SetPageOf(lo)
			return p, p ~= 0
		end, function(page)
			local i = IndexOf(lo)
			if i and SP.BindLoadoutToTotemSet then
				local ok, reason = SP:BindLoadoutToTotemSet(i, page)
				if not ok and reason then SP:Print(reason) end
			end
			Row:Changed(true)
			return true
		end, "Choose a Blizzard totem set for this loadout. Each set can hold one loadout: choosing a set replaces its"
			.. " previous loadout. Call of the Elements follows your assignments. None: switch loadouts as usual. Saved"
			.. " choices stay saved if their set is unavailable."),
		{ text = "Send to Set Now", disabled = SetPageOf(lo) == 0,
			tip = "Put all four saved totems in the chosen set. None leaves that element empty. Changes made in combat"
				.. " take effect when the fight ends.",
			onClick = function()
				local i = IndexOf(lo)
				if i and SP.SyncBoundLoadout and SP.BoundLoadoutSummon and SP:BoundLoadoutSummon(i) then
					local ok, reason = SP:SyncBoundLoadout(i)
					if not ok and reason then SP:Print(reason) end
				end
				Row:Changed(true)
				return true
			end },
	}
end

-- the name box (the addon's own dialog): Rename..., and after + (isNew)
local function NameBox(lo, isNew)
	local i = IndexOf(lo)
	if not i then return end
	local name = NameOf(lo)
	local text
	if isNew then
		text = name .. " has the totems on your bar now: " .. (SP:GetLoadoutDescription(i) or "")
			.. ". It is in use. Right-click it any time to change its totems or icon."
	else
		text = "A new name for " .. name .. ". It shows under its icon and on the loadout bar, and /spl <name> switches to it."
	end
	return SP:ShowSPDialog({
		key = "loadoutName",
		title = isNew and "Name your new loadout" or "Rename loadout",
		text = text,
		input = { text = name, maxLetters = MAX_NAME },
		buttons = {
			{ text = "Rename", onClick = function(dialog)
				-- combat began while it was open: say so, and keep the box up for after the fight
				if Refuse() then return true end
				local j = IndexOf(lo)
				if not j then return end
				local v = dialog and dialog.GetInput and dialog:GetInput() or ""
				v = tostring(v or ""):match("^%s*(.-)%s*$") or ""
				SP:RenameLoadout(j, v ~= "" and v or nil)   -- (empty: "Loadout N", as the old Rename box did)
				Redraw()
			end },
			{ text = isNew and "Not now" or "Cancel" },
		},
	})
end

local function PickIcon(lo)
	local i = IndexOf(lo)
	if not (i and SP.OpenIconPicker) then return end
	SP:OpenIconPicker(i, function(icon)
		if Refuse() then return end
		local j = IndexOf(lo)
		if not j then return end
		SP:SetLoadoutIcon(j, icon)
		Row:Changed(false)
	end)
end

local function MenuItems(item)
	local lo = item.key
	local r = {}
	if InUse(lo) and not Differs(lo) then
		r[#r + 1] = { text = "Switch To This Loadout", value = function() return "In use", false end, disabled = true,
			tip = "It is the loadout in use: the green bar under it." }
	else
		r[#r + 1] = { text = "Switch To This Loadout",
			tip = InUse(lo) and ("It is the loadout in use, but its totems changed here since: your totem bar takes its 4 totems"
					.. " (and its Drop All choices) again, as a click on it does. Out of a fight only.")
				or ("Your totem bar takes its 4 totems and its Drop All choices, as a click on it (or on the loadout bar)"
					.. " does. Out of a fight only."),
			onClick = function() Switch(lo); Row:Changed(false) end }
	end
	r[#r + 1] = SEP
	for e = 1, 4 do
		r[#r + 1] = { text = ELEMENTS[e], subMaxHeight = 260,
			icon = (lo[e] or 0) > 0 and SP:GetTotemIcon(e, lo[e]) or nil,
			value = function()
				local cur = lo[e] or 0
				return cur > 0 and (SP:GetTotemName(e, cur) or "?") or "None", false
			end,
			tip = "This loadout's " .. ELEMENTS[e] .. " totem. Your bar takes it when you switch to this loadout.",
			sub = function() return TotemChoices(lo, e) end }
	end
	r[#r + 1] = Menu.Group("Drop All", function() return DropAllRows(lo) end,
		"What Drop All and Call of the Elements leave out while this loadout is in use.",
		function() return DropAllValue(lo) end)
	if HasSetControls() then
		local known = KnownPages()
		if known[2] or known[3] then
			r[#r + 1] = Menu.Group("Blizzard Totem Set", function() return SetRows(lo) end, nil, function()
				local p = SetPageOf(lo)
				return PAGE_NAMES[p] or "None", p ~= 0
			end)
		end
	end
	r[#r + 1] = SEP
	r[#r + 1] = { text = "Rename...", tip = "A box to type its new name in.", onClick = function() NameBox(lo, false) end }
	r[#r + 1] = { text = "Icon...", tip = "The icon picker, beside this window. Without an icon of its own a loadout shows its first totem.",
		onClick = function() PickIcon(lo) end }
	r[#r + 1] = SEP
	r[#r + 1] = { text = "Delete This Loadout...", tip = "Asks first.", onClick = function()
		local i = IndexOf(lo)
		if i then SP:ConfirmDeleteLoadout(i, NameOf(lo)) end
	end }
	return r
end

-- ---------------------------------------------------------------------------
-- +: a new loadout from the totems on your bar now, put in use (as Create Loadout did), then
-- the box to name it
-- ---------------------------------------------------------------------------
local function NewLoadout()
	if #List() >= MAX_LOADOUTS then return end
	local mine = ShamanPower_Assignments and SP.player and ShamanPower_Assignments[SP.player] or {}
	local totems = {}
	for e = 1, 4 do totems[e] = mine[e] or 0 end
	SP:CreateLoadout(nil, nil, totems)
	local list = List()
	local lo = list[#list]
	Redraw()
	if lo then NameBox(lo, true) end
end

-- ---------------------------------------------------------------------------
-- The row
-- ---------------------------------------------------------------------------
Row = ns.IconRow.New({
	caption = function()
		local n = #List()
		if n == 0 then return CAPTION_NONE end
		if n >= MAX_LOADOUTS then return CAPTION_FULL end
		return CAPTION
	end,
	hint = "Click: switch to it\nRight-click: change it\nDrag: move it",
	list = function(out)
		for i, lo in ipairs(List()) do
			out[#out + 1] = { key = lo, name = lo.name or ("Loadout " .. i) }
		end
	end,
	textures = function(item, out)
		local i = IndexOf(item.key)
		out[1] = (i and SP:GetLoadoutIcon(i)) or "Interface\\Icons\\ClassIcon_Shaman"
		return 1
	end,
	shown = function() return true end,
	tooltip = function(item)
		local lo = item.key
		local i = IndexOf(lo)
		local body = i and SP:GetLoadoutDescription(i) or ""
		local p = SetPageOf(lo)
		if PAGE_NAMES[p] then body = body .. "\nBlizzard totem set: " .. PAGE_NAMES[p] .. "." end
		if InUse(lo) then
			body = (Differs(lo) and "In use. Its totems changed here since: click it to put them on your bar.\n" or "In use.\n") .. body
		end
		return body
	end,
	label = function(item) return NameOf(item.key), InUse(item.key) end,
	mark = function(item) return InUse(item.key) end,
	add = {
		name = "New",
		tip = "Saves the totems on your bar now as a new loadout (your 4 totems and which of them Drop All leaves out)"
			.. " and puts it in use. Then a box to name it.",
		hint = "Click: save a new loadout",
		shown = function() return #List() < MAX_LOADOUTS end,
		click = NewLoadout,
	},
	toggle = function(item) Switch(item.key) end,
	menu = MenuItems,
	move = function(item, index)
		local from = IndexOf(item.key)
		if from and SP.MoveLoadout then SP:MoveLoadout(from, index) end
	end,
	locked = function() return InCombatLockdown() end,
	onLocked = function() print(COMBAT) end,
})
ns.CustomRows.loadoutIcons = Row
ns.LoadoutRow = Row

-- A loadout switched, saved, deleted or changed somewhere else (the loadout bar, /spl, the
-- minimap menu, Auto-Switch, Blizzard's totem bar) while the page is open: drawn again, once,
-- on the next frame. Every such change runs SP:UpdateLoadoutBar.
do
	local queued = false
	local function Later()
		queued = false
		Row:OnSettingsChanged()
	end
	if type(SP.UpdateLoadoutBar) == "function" then
		hooksecurefunc(SP, "UpdateLoadoutBar", function()
			if queued or not (Row.frame and Row.frame:IsVisible()) then return end
			queued = true
			C_Timer.After(0, Later)
		end)
	end
end
