-- ShamanPower_Config :: LoadoutIcons
-- Loadouts > Loadouts (A17 part B, 3.0.8; Auto Loadout Groups A79, 3.0.9.5): the Saved Loadouts row
-- and every loadout's right-click menu, on the shared icon row (IconRow.lua, with its optional label
-- / mark / add and its groups). A tile per saved loadout (ShamanPower_TotemLoadouts, shared by your
-- characters): its own icon, else its first totem's (SP:GetLoadoutIcon), its name under it (wraps,
-- never cut short), a green bar under the one in use.
-- The row is in lines like Ready Reminders' Rows view: EVERYWHERE first (the loadouts on no group,
-- and +), then each Auto Loadout Group (ShamanPowerLoadoutRules.lua) in the page's order: its name
-- on the left (a raid's in fire red, the red of the window's fire line), what kind of place under
-- it. The first loadout in a group says On Entry (the one you are switched to when you enter).
-- Click: show or hide the loadout (as every icon page; hidden ones are gray, out of the flyout and
-- the Loadout List). Right-click: its menu (Hide This Loadout, Switch To This Loadout, its 4 totems,
-- Drop All, Blizzard Totem Set on WoW: Forever, Rename..., Icon..., Delete This Loadout...). Drag:
-- onto a group's row (it shows only there), back to Everywhere, or to another place (its place in
-- the saved list: the flyout's order and its click cycle). A group's name: click it to change the
-- group (the group window), drag it to move the whole group up or down. +: a new loadout from the
-- totems on your bar now, put in use (SP:CreateLoadout), then a box to name it. Make an Auto
-- Loadout Group (a button under the row, ShamanPowerOptions.lua) opens the group window.
-- Switching loadouts is out of a fight only, on both games: the page locks in a fight, and a
-- click, drag, menu choice or dialog button refuses (and says so) while InCombatLockdown().
-- Nothing here runs while the page is closed.
local _, ns = ...
local Core, W = ns.Core, ns.Widgets
local SP = ShamanPower
if not (Core and W and SP and ns.IconRow) then return end

local Menu = ns.IconRow.Menu
local SEP = { separator = true }
local ELEMENTS = { "Earth", "Fire", "Water", "Air" }
local MAX_NAME = 32      -- the name box's letters
local GUTTER = 124       -- the group names' room, left of the tiles
local EVERYWHERE = "everywhere"
local Row

-- (the words that say what to do in the settings' blue, so a player sees them first)
local CAPTION = "|cff3FA9F5CLICK|r a loadout to show or hide it in your flyout (|cff3FA9F5gray|r: hidden). |cff3FA9F5DRAG|r it"
	.. " onto a group to show it only there, or back to Everywhere. The |cff3FA9F5first|r loadout in a group is the one you"
	.. " switch to when you enter. |cff3FA9F5RIGHT-CLICK|r a loadout to switch to it, or for its totems, name, icon or"
	.. " Drop All (the green bar: the one in use). |cff3FA9F5EDIT|r under a group's name changes or deletes it, |cff3FA9F5DRAG|r its name to"
	.. " move the whole group. |cff3FA9F5+|r saves a new loadout from the totems on your bar now."
local CAPTION_NONE = "No loadouts saved yet. |cff3FA9F5+|r saves one from the totems on your bar now: your 4 totems and"
	.. " which of them Drop All leaves out."
local COMBAT = "|cff0070ddShamanPower|r: |cffe64a4aLoadouts can't change in combat - try again after the fight.|r"

-- ---------------------------------------------------------------------------
-- The loadouts: each tile's key is the loadout itself, so a drag, a delete or a menu left open
-- always finds the right one (its place in the list is looked up when it is used)
-- ---------------------------------------------------------------------------
local function List() return ShamanPower_TotemLoadouts or {} end

local function IndexOf(lo)
	if type(lo) ~= "table" then return nil end
	for i, x in ipairs(List()) do
		if x == lo then return i end
	end
	return nil
end

local function NameOf(lo)
	if type(lo) == "table" and lo.name then return lo.name end
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

-- a zone's name as the groups compare it (capital letters and extra spaces never matter)
local function Norm(s)
	if SP.LoadoutZoneKey then return SP.LoadoutZoneKey(s) end
	return strlower(strtrim(tostring(s or "")))
end

local function GroupOf(lo)
	return type(lo) == "table" and lo.group and SP.LoadoutGroupByID and SP:LoadoutGroupByID(lo.group) or nil
end

-- a raid group's name: the brand's fire red (the red of the window's fire line)
local function FireRGB()
	local e = SP.Brand and SP.Brand.elements and SP.Brand.elements.fire
	if e then return e[1], e[2], e[3] end
	return 0.949, 0.341, 0.208
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
-- ones on your bar now (Switch To This Loadout puts them on the bar again)
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

-- a click: shown or hidden (out of the flyout and the Loadout List everywhere)
local function ToggleHidden(lo)
	local i = IndexOf(lo)
	if i and SP.SetLoadoutHidden then SP:SetLoadoutHidden(i, not lo.hidden) end
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
	-- the pictures (the icon's own screen): None is an empty plate; a totem is its own icon in the loadout's place
	local out = { { text = "None", selected = cur == 0, pic = { kind = "hidden" },
		onClick = function() return SetTotem(lo, e, 0) end } }
	for _, idx in ipairs(TotemIndexes(e)) do
		local name = SP:GetTotemName(e, idx) or ("Totem " .. idx)
		-- a totem this character hasn't learned stays pickable, marked (the game won't drop it yet)
		local learned = not SP.KnowsTotem or SP:KnowsTotem(e, idx)
		out[#out + 1] = { text = learned and name or (name .. "  |cff8A94A6(not learned)|r"), icon = SP:GetTotemIcon(e, idx),
			selected = idx == cur, pic = { kind = "swap", icon = SP:GetTotemIcon(e, idx) },
			onClick = function() return SetTotem(lo, e, idx) end }
	end
	return out
end

local function DropAllRows(lo)
	local r = {}
	-- on, its picture: the icon grayed (left out), as Not Dropped draws on the Totem Bar page
	for e = 1, 4 do
		r[#r + 1] = Menu.OnOff("Skip " .. ELEMENTS[e], function()
			local i = IndexOf(lo)
			local v = (i and SP:LoadoutExcluded(i, e)) and true or false
			return v, v   -- (On is not the usual: in blue)
		end, function(v)
			local i = IndexOf(lo)
			if i then SP:SetDropAllExclude(e, v and true or false, i) end
			Row:Changed(true)
			return true
		end, "Leaves " .. ELEMENTS[e] .. " out of Drop All and Call of the Elements while this loadout is in use.",
			{ kind = "gray" })
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
		Menu.Choice("Blizzard Totem Set", pages, function()
			local p = SetPageOf(lo)
			return p, p ~= 0
		end, function(page)
			-- that set's own loadout never made: made now, as its Add button does, then this one goes on the set
			local made = false
			if page ~= 0 and SP.HasCallLoadout and not SP:HasCallLoadout(page) then
				local ok, reason = SP:AddCallLoadout(page, true)
				if ok then made = true elseif reason then SP:Print(reason) end
			end
			local i = IndexOf(lo)
			if i and SP.BindLoadoutToTotemSet then
				local ok, reason = SP:BindLoadoutToTotemSet(i, page)
				if not ok and reason then SP:Print(reason) end
			end
			if made then Redraw() return end   -- a new tile: the page lays itself out again (the menu closes)
			Row:Changed(true)
			return true
		end, "Choose a Blizzard totem set for this loadout. Each set can hold one loadout: choosing a set replaces its"
			.. " previous loadout. If you never made that set's Call of the Ancestors or Call of the Spirits loadout, it's"
			.. " made too. Call of the Elements follows your assignments. None: switch loadouts as usual. Saved"
			.. " choices stay saved if their set is unavailable.",
			{ kind = "none" }),   -- (no picture says a totem set: the captions alone)
		{ text = "Copy Totems To Set", disabled = SetPageOf(lo) == 0,
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
			{ text = "Save Name", onClick = function(dialog)
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
	if item.empty then return {} end
	local lo = item.key
	local r = {}
	-- the loadout itself first, as every icon page's menu
	r[#r + 1] = { text = "Show", label = true }
	r[#r + 1] = { text = lo.hidden and "Show This Loadout" or "Hide This Loadout",
		tip = lo.hidden and "Puts it back in your loadout flyout and the Loadout List."
			or "Takes it out of your loadout flyout and the Loadout List. It stays saved here, gray.",
		onClick = function() ToggleHidden(lo); Row:Changed(false) end }
	r[#r + 1] = SEP
	if InUse(lo) and not Differs(lo) then
		r[#r + 1] = { text = "Switch To This Loadout", value = function() return "In use", false end, disabled = true,
			tip = "It is the loadout in use: the green bar under it." }
	else
		r[#r + 1] = { text = "Switch To This Loadout",
			tip = InUse(lo) and ("This loadout is in use, but its saved totems changed here since: your totem bar takes its 4 totems"
					.. " (and its Drop All choices) again. Out of a fight only.")
				or ("Your totem bar takes its 4 totems and its Drop All choices, as a click on it in the loadout flyout"
					.. " does. Out of a fight only."),
			onClick = function() Switch(lo); Row:Changed(false) end }
	end
	r[#r + 1] = SEP
	r[#r + 1] = { text = "Behavior", label = true }
	for e = 1, 4 do
		r[#r + 1] = { text = ELEMENTS[e], subMaxHeight = 260,
			icon = (lo[e] or 0) > 0 and SP:GetTotemIcon(e, lo[e]) or nil,
			words = "the " .. ELEMENTS[e] .. " totem your bar takes when you switch to it",
			value = function()
				local cur = lo[e] or 0
				return cur > 0 and (SP:GetTotemName(e, cur) or "?") or "None", false
			end,
			tip = "This loadout's " .. ELEMENTS[e] .. " totem. Your bar takes it when you switch to this loadout.",
			sub = function() return TotemChoices(lo, e) end }
	end
	r[#r + 1] = Menu.Group("Drop All", function() return DropAllRows(lo) end,
		"What Drop All and Call of the Elements leave out while this loadout is in use.",
		function() return DropAllValue(lo) end, "what it leaves out while in use")
	if HasSetControls() then
		local known = KnownPages()
		if known[2] or known[3] then
			-- (its two rows right here: a group for two controls was one level too many)
			for _, row in ipairs(SetRows(lo)) do r[#r + 1] = row end
		end
	end
	r[#r + 1] = SEP
	r[#r + 1] = { text = "Rename...", tip = "Rename this loadout.", onClick = function() NameBox(lo, false) end }
	r[#r + 1] = { text = "Pick an Icon...", tip = "The icon picker, beside this window. Without an icon of its own a loadout shows its first totem.",
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
-- the box to name it. It goes at the end of Everywhere.
-- ---------------------------------------------------------------------------
local function NewLoadout()
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
-- A loadout dropped on the row: the line under the cursor says the group (Everywhere or one of
-- them), the tile right of the cursor the loadout it lands in front of (none on that line: in
-- front of the group's next line's first, else after the group's last)
-- ---------------------------------------------------------------------------
local PLATE_HALF = 20
local function PlaceAt(item, cx, cy)
	local from = IndexOf(item.key)
	local sx, sy = Row.slotX, Row.slotY
	if not (from and sx and sy) then return end
	local best, lineY
	for i in ipairs(Row.list) do
		local d = math.abs(cy - (sy[i] + PLATE_HALF))
		if not best or d < best then best, lineY = d, sy[i] end
	end
	local group, before, lastOnLine
	for i, it in ipairs(Row.list) do
		if sy[i] == lineY then
			group = it.group
			lastOnLine = i
			if not before and not it.empty and it.key ~= item.key and cx < sx[i] + PLATE_HALF then before = it.key end
		end
	end
	if not group then return end
	if not before and lastOnLine then
		local nextItem = Row.list[lastOnLine + 1]
		if nextItem and nextItem.group == group and not nextItem.empty and nextItem.key ~= item.key then before = nextItem.key end
	end
	if SP.PutLoadoutInGroup then SP:PutLoadoutInGroup(from, group ~= EVERYWHERE and group or nil, before) end
end

-- ---------------------------------------------------------------------------
-- A group dragged by its name: its name and loadouts dim where they were, a copy of the name
-- follows the cursor, a line across the row shows where it lands. Let go: the group moves there
-- (SP:MoveLoadoutGroup: only the page's order). Out of a fight only, as the rest of the page.
-- ---------------------------------------------------------------------------
local groupDrag   -- { id, holder } while a name is held

-- each group's block of lines on the row, in the page's order (Everywhere left out)
local function GroupBlocks()
	local out = {}
	local sy = Row.slotY
	if not sy then return out end
	for i, it in ipairs(Row.list) do
		if it.group ~= EVERYWHERE then
			local b = out[#out]
			if not b or b.id ~= it.group then
				b = { id = it.group, top = sy[i], bottom = sy[i] }
				out[#out + 1] = b
			end
			b.bottom = sy[i]
		end
	end
	local lineH = Row.lineH or 80
	for _, b in ipairs(out) do b.bottom = b.bottom + lineH - 10 end
	return out
end

-- the group's new place among the groups (1: right under Everywhere), and the y of its line
local function GroupDropAt(id, cy)
	local place, lineY, firstTop
	local n = 0
	for _, b in ipairs(GroupBlocks()) do
		if b.id ~= id then
			n = n + 1
			firstTop = firstTop or b.top
			if cy > (b.top + b.bottom) / 2 then place, lineY = n + 1, b.bottom + 6 end
		end
	end
	if not place then place, lineY = 1, (firstTop or 0) - 6 end
	return place, lineY
end

local function DragPieces()
	local f = Row.frame
	local d = Row.spGroupDragPieces
	if not d then
		d = {}
		d.line = f:CreateTexture(nil, "OVERLAY", nil, 7)
		d.line:SetColorTexture(Core:Color("accentHi"))
		d.line:SetHeight(2)
		d.ghost = CreateFrame("Frame", nil, f)
		local bg = d.ghost:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(d.ghost)
		bg:SetColorTexture(Core:Color("rowBg"))
		Core:MakeBorder(d.ghost, "accentHi", 1)
		d.text = d.ghost:CreateFontString(nil, "OVERLAY")
		d.text:SetFontObject(Core.fonts.section)
		d.text:SetPoint("LEFT", d.ghost, "LEFT", 8, 0)
		d.runner = CreateFrame("Frame", nil, f)
		Row.spGroupDragPieces = d
	end
	d.ghost:SetParent(f)
	d.ghost:SetFrameLevel(f:GetFrameLevel() + 30)
	return d
end

local function DimGroup(id, alpha)
	for _, hd in ipairs(Row.groupLabels or {}) do
		if hd.spGroupID == id then
			if hd.spName then hd.spName:SetAlpha(alpha) end
			if hd.spSub then hd.spSub:SetAlpha(alpha) end
		end
	end
	for _, bt in ipairs(Row.buttons or {}) do
		if bt:IsShown() and bt.item and bt.item.group == id then bt:SetAlpha(alpha < 1 and 0.55 or 1) end
	end
end

local function StartGroupDrag(holder)
	local id = holder.spGroupID
	if not id or groupDrag or Refuse() then return end
	if ns.ContextMenu:IsOpen() then ns.ContextMenu:Close() end
	groupDrag = { id = id }
	holder.spDragged = true
	local d = DragPieces()
	d.text:SetText(holder.spName:GetText())
	d.text:SetTextColor(holder.spName:GetTextColor())
	d.ghost:SetSize(math.ceil(d.text:GetStringWidth()) + 16, 24)
	DimGroup(id, 0.35)
	local f = Row.frame
	d.runner:SetScript("OnUpdate", function()
		local cx, cy = Row:CursorInFrame()
		local _, lineY = GroupDropAt(id, cy)
		d.line:ClearAllPoints()
		d.line:SetPoint("TOPLEFT", f, "TOPLEFT", 12 + (tonumber(W.CARD_INSET) or 0), -lineY)
		d.line:SetPoint("RIGHT", f, "RIGHT", -12, 0)
		d.line:Show()
		d.ghost:ClearAllPoints()
		d.ghost:SetPoint("LEFT", f, "TOPLEFT", cx - 12, -cy)
		d.ghost:Show()
	end)
end

local function StopGroupDrag(holder)
	local drag = groupDrag
	groupDrag = nil
	local d = Row.spGroupDragPieces
	if d then
		d.runner:SetScript("OnUpdate", nil)
		d.line:Hide()
		d.ghost:Hide()
	end
	-- (the click that ends a drag is not a click on the name)
	C_Timer.After(0, function() holder.spDragged = nil end)
	if not drag then return end
	DimGroup(drag.id, 1)
	if Refuse() then return end
	local _, cy = Row:CursorInFrame()
	local place = GroupDropAt(drag.id, cy)
	if SP.MoveLoadoutGroup then SP:MoveLoadoutGroup(drag.id, place) end
	Redraw()
end

-- ---------------------------------------------------------------------------
-- The group window: Make an Auto Loadout Group (the button under the row), Change Auto Loadout
-- Group (a group's name). The addon's own dialog, made once; its rows are drawn again on each
-- choice. Kinds of place: A Zone (a name typed, or Use Current Zone inside it, and what kind of
-- zone it is: Raid by default, put right by the game the first time you are there), Any Raid, Any
-- Dungeon, Any Battleground or Arena, Outside (one group each).
-- ---------------------------------------------------------------------------
local KIND_CHOICES = { { "zone", "A Zone", 120 }, { "raid", "Any Raid", 120 }, { "party", "Any Dungeon", 130 } }
local KIND_CHOICES2 = { { "pvp", "Any Battleground or Arena", 200 }, { "none", "Outside", 120 } }
local TYPE_CHOICES = { { "raid", "Raid", 90 }, { "party", "Dungeon", 100 }, { "pvp", "Battleground or Arena", 180 }, { "none", "Other", 90 } }
local RESIST_CHOICES = { { "none", "No Request", 110 }, { "fire", "Fire Resistance", 130 }, { "frost", "Frost Resistance", 130 },
	{ "nature", "Nature Resistance", 130 } }
local KIND_LABEL = { raid = "Any Raid", party = "Any Dungeon", pvp = "Any Battleground or Arena", none = "Outside" }
local TYPE_LABEL = { raid = "raid", party = "dungeon", pvp = "battleground or arena", none = "zone outside" }

local win
local WIN_W, BODY_W = 600, 572

-- pooled pieces of the window's body: buttons (the choices and Use Current Zone) and lines of text
local function Reset()
	win.spBtnUsed, win.spTextUsed = 0, 0
	for _, b in ipairs(win.spBtns) do b:Hide(); b.spBar:Hide() end
	for _, t in ipairs(win.spTexts) do t:Hide() end
	W:ReleaseAll(win.body)
end

local function Text(text, y, font, color, x)
	win.spTextUsed = win.spTextUsed + 1
	local fs = win.spTexts[win.spTextUsed]
	if not fs then
		fs = win.body:CreateFontString(nil, "OVERLAY")
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(true)
		win.spTexts[win.spTextUsed] = fs
	end
	fs:SetFontObject(font or Core.fonts.row)
	fs:SetTextColor(Core:Color(color or "text"))
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", win.body, "TOPLEFT", x or 0, -y)
	fs:SetWidth(BODY_W - (x or 0))
	fs:SetText(text)
	fs:Show()
	return fs, math.ceil(fs:GetStringHeight())
end

-- a button: the chosen one of a line of choices has the green bar under it and its words bright
local function Button(text, width, x, y, onClick, chosen, off, tip)
	win.spBtnUsed = win.spBtnUsed + 1
	local b = win.spBtns[win.spBtnUsed]
	if not b then
		b = Core:MakeButton(win.body, text, width, false)
		b.spBar = b:CreateTexture(nil, "OVERLAY")
		b.spBar:SetColorTexture(Core:Color("on"))
		b.spBar:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
		b.spBar:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, -2)
		b.spBar:SetHeight(3)
		win.spBtns[win.spBtnUsed] = b
	end
	b.text:SetText(text)
	b:SetWidth(math.max(width or 0, math.ceil(b.text:GetStringWidth()) + 28))
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", win.body, "TOPLEFT", x, -y)
	b.spBar:SetShown(chosen == true)
	if off then
		b:Disable()
		b.text:SetTextColor(Core:Color("textMute"))
	else
		b:Enable()
		b.text:SetTextColor(Core:Color(chosen == false and "textDim" or "white"))
	end
	b:SetScript("OnClick", function() if not off then onClick() end end)
	Core:AttachTooltip(b, tip and text or nil, tip)
	b:Show()
	return b
end

-- a line of choices; returns its height
local function Choices(list, current, y, pick, offFn)
	local x = 0
	for _, c in ipairs(list) do
		local off, why = false, nil
		if offFn then off, why = offFn(c[1]) end
		local b = Button(c[2], c[3], x, y, function() pick(c[1]) end, c[1] == current, off, why)
		x = x + b:GetWidth() + 8
	end
	return 26
end

local function MakeWindow()
	win = Core:CreateDialog({ name = "ShamanPowerLoadoutGroupWindow", title = "Make an Auto Loadout Group", subtitle = "Loadouts",
		width = WIN_W, footer = 52, special = true, strata = "DIALOG", element = "earth", opaque = true })
	win.spBtns, win.spTexts = {}, {}
	win.spOK = Core:MakeButton(win, "Create", 100, true)
	win.spOK:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -14, 12)
	win.spCancel = Core:MakeButton(win, "Cancel", 100, false)
	win.spCancel:SetPoint("RIGHT", win.spOK, "LEFT", -8, 0)
	win.spCancel:SetScript("OnClick", function() win:Hide() end)
	win.spDelete = Core:MakeButton(win, "Delete This Group", 150, false)
	win.spDelete:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 14, 12)
	Core:AttachTooltip(win.spDelete, "Delete This Group", "Asks first. Its loadouts go back to Everywhere; no loadout is deleted.")
	-- the settings window closing takes this one with it
	if _G.ShamanPowerConfigUIFrame then _G.ShamanPowerConfigUIFrame:HookScript("OnHide", function() win:Hide() end) end
end

local Draw

local function Save(g, st, err)
	if Refuse() then return end
	if st.kind == "zone" then
		if Norm(st.zone) == "" then err:SetText("Type the zone's name, or use Use Current Zone inside it."); err:Show(); return end
		local other = SP:LoadoutGroupForZone(st.zone, g)
		if other then err:SetText("You already have a group for " .. SP:LoadoutGroupName(other) .. "."); err:Show(); return end
	end
	local fields = { kind = st.kind, zone = st.zone, zoneType = st.zoneType, entry = st.entry, others = st.others,
		resist = (st.resist and st.resist ~= "none") and st.resist or false }
	if g then SP:EditLoadoutGroup(g.id, fields) else SP:AddLoadoutGroup(fields) end
	win:Hide()
	Redraw()
end

local function AskDelete(g)
	SP:ShowSPDialog({
		key = "deleteLoadoutGroup", title = "Delete group",
		text = "Delete the group " .. SP:LoadoutGroupName(g) .. "? Its loadouts go back to Everywhere; no loadout is deleted.",
		buttons = {
			{ text = "Delete", onClick = function()
				if Refuse() then return true end
				SP:DeleteLoadoutGroup(g.id)
				win:Hide()
				Redraw()
			end },
			{ text = "Cancel" },
		},
	})
end

Draw = function(g, st)
	Reset()
	local y = 0
	local _, h = Text("Drag loadouts onto this group's row in Saved Loadouts: the loadout flyout and the Loadout List show them"
		.. " only there. The first one is the loadout you switch to when you enter.", y, Core.fonts.rowDim, "textDim")
	y = y + h + 16
	_, h = Text("Where is this group for?", y)
	y = y + h + 8
	local function pickKind(k)
		st.kind = k
		Draw(g, st)
	end
	-- (one group per kind of place: a kind that has one is off here)
	local function kindTaken(k)
		if k == "zone" then return false end
		local other = SP:LoadoutGroupOfKind(k, g)
		if other then return true, "You already have an " .. KIND_LABEL[k] .. " group: click its name on the page to change it." end
		return false
	end
	y = y + Choices(KIND_CHOICES, st.kind, y, pickKind, kindTaken) + 12
	y = y + Choices(KIND_CHOICES2, st.kind, y, pickKind, kindTaken) + 16
	if st.kind == "zone" then
		local row, used = W:Input(win.body, { label = "Zone Name", width = BODY_W, y = y,
			get = function() return st.zone or "" end,
			set = function(v) st.zone = v end })
		y = y + used + 2
		local cur = Button("Use Current Zone", 160, 0, y, function()
			st.zone = GetRealZoneText() or ""
			local inInstance, kind = IsInInstance()
			if not inInstance then st.zoneType = "none"
			elseif kind == "raid" then st.zoneType = "raid"
			elseif kind == "pvp" or kind == "arena" then st.zoneType = "pvp"
			else st.zoneType = "party" end
			Draw(g, st)
		end, nil, false, "Fills in the name of the zone you are in, and what kind of zone it is.")
		local here = Text("You're in " .. (GetRealZoneText() or "?") .. ".", y + 6, Core.fonts.rowDim, "textDim", cur:GetWidth() + 10)
		here:SetWidth(BODY_W - cur:GetWidth() - 10)
		-- as you type, close names the game knows take that line's place: click one to use it (a zone
		-- you've stood in also sets This zone is a)
		local sx, sy = cur:GetWidth() + 10, y   -- (sy: y moves on as the rest is drawn; typing comes later)
		local mean = Text("Did you mean:", y + 6, Core.fonts.rowDim, "textDim", sx)
		mean:SetWidth(math.ceil(mean:GetStringWidth()) + 4)
		local picks = {}
		for i = 1, 3 do picks[i] = Button("", 0, sx, y, function() end) end
		local function Suggest(text)
			local list = SP.LoadoutZoneSuggestions and SP:LoadoutZoneSuggestions(text, 3) or {}
			local x, shown = sx + math.ceil(mean:GetStringWidth()) + 10, 0
			for i, b in ipairs(picks) do
				local s = list[i]
				local w = 0
				if s then
					b.text:SetText(s.name)
					w = math.ceil(b.text:GetStringWidth()) + 28
				end
				if s and x + w <= BODY_W then
					b:SetWidth(w)
					b:ClearAllPoints()
					b:SetPoint("TOPLEFT", win.body, "TOPLEFT", x, -sy)
					b:SetScript("OnClick", function()
						st.zone = s.name
						if s.kind then st.zoneType = s.kind end
						Draw(g, st)
					end)
					Core:AttachTooltip(b, s.name, (s.seen and ("You've been there: a " .. TYPE_LABEL[s.kind or "none"] .. ". Click to use this name."))
						or (s.kind and ("A " .. TYPE_LABEL[s.kind] .. " in the game. Click to use this name."))
						or "A zone on the game's map. Click to use this name.")
					b:Show()
					x, shown = x + w + 6, shown + 1
				else
					b:Hide()
				end
			end
			mean:SetShown(shown > 0)
			here:SetShown(shown == 0)
		end
		Suggest(st.zone)
		if row.box then
			-- typing on at the end fills in the rest of a name the game knows, highlighted: Enter or Tab keeps
			-- it, typing on replaces it, Backspace takes it away (the text got shorter: nothing filled in)
			row.box:SetScript("OnTextChanged", function(box, user)
				local text = box:GetText()
				local typing = user and #text > (box.spTyped or #text) and box:GetCursorPosition() == #text
				box.spTyped = #text
				local full = typing and SP.LoadoutZoneComplete and SP:LoadoutZoneComplete(text)
				if full then
					box:SetText(full)   -- (comes back here as the game's own change: not typing)
					box.spTyped = #text
					box:SetCursorPosition(#text)
					box:HighlightText(#text, #full)
					text = full
				end
				st.zone = text
				Suggest(text)
			end)
			row.box:SetScript("OnTabPressed", function(box)
				box:HighlightText(0, 0)
				box:SetCursorPosition(#box:GetText())
				box.spTyped = #box:GetText()
			end)
		end
		y = y + 26 + 12
		_, h = Text("This zone is a:", y)
		y = y + h + 8
		y = y + Choices(TYPE_CHOICES, st.zoneType or "raid", y, function(t) st.zoneType = t; Draw(g, st) end) + 12
		_, h = Text("Type the zone's name as the game shows it, like The Molten Core. Capital letters, extra spaces and a"
			.. " leading The don't matter. As you type, close names the game knows show next to Use Current Zone: click one"
			.. " to use it. Use Current Zone fills it in for you inside the zone. A raid's name is red on the page; the first"
			.. " time you enter, the game puts the kind of zone right if it was picked wrong.", y, Core.fonts.rowDim, "textDim")
		y = y + h + 14
	end
	local _, used = W:Toggle(win.body, { label = "Switch to the First Loadout When I Enter", width = BODY_W, y = y,
		desc = "When you enter this group's place, switch to its first loadout once (a fight first: when it ends).",
		get = function() return st.entry end, set = function(v) st.entry = v and true or false end })
	y = y + used
	_, used = W:Toggle(win.body, { label = "Also Show My Other Loadouts Here", width = BODY_W, y = y,
		desc = "The loadouts in Everywhere also show in the flyout and the Loadout List here.",
		get = function() return st.others end, set = function(v) st.others = v and true or false end })
	y = y + used
	_, h = Text("Off: only this group's loadouts show in the flyout there.", y, Core.fonts.rowDim, "textDim")
	y = y + h + 14
	local raid = st.kind == "raid" or (st.kind == "zone" and (st.zoneType or "raid") == "raid")
	if SP.RESIST_REQUESTS and raid then
		_, h = Text("Request Raid Resistance", y)
		y = y + h + 8
		y = y + Choices(RESIST_CHOICES, st.resist or "none", y, function(k) st.resist = k; Draw(g, st) end) + 8
		_, h = Text("Asks the raid's shamans for this totem when you enter. Raids only; it ends when you leave.", y,
			Core.fonts.rowDim, "textDim")
		y = y + h + 6
	end
	local err = Text("", y, Core.fonts.row, "warn")
	err:Hide()
	y = y + 18
	win.spOK.text:SetText(g and "Save" or "Create")
	win.spOK:SetScript("OnClick", function() Save(g, st, err) end)
	win.spDelete:SetShown(g ~= nil)
	win.spDelete:SetScript("OnClick", function() if g then AskDelete(g) end end)
	win:SetHeight(46 + 4 + 10 + y + 14 + 52)
end

-- id: change that group (nil: make a new one)
function SP:OpenLoadoutGroupWindow(id)
	if Refuse() then return end
	if not self.LoadoutGroups then return end
	if ns.ContextMenu:IsOpen() then ns.ContextMenu:Close() end
	if not win then MakeWindow() end
	local g = id and self:LoadoutGroupByID(id) or nil
	local st = {
		kind = g and g.kind or "zone", zone = g and g.zone or "", zoneType = g and g.zoneType or "raid",
		entry = not (g and g.entry == false), others = not (g and g.others == false), resist = g and g.resist or "none",
	}
	if win.title then win.title:SetText(g and "Change Auto Loadout Group" or "Make an Auto Loadout Group") end
	Draw(g, st)
	win:ClearAllPoints()
	local cfg = _G.ShamanPowerConfigUIFrame
	if cfg and cfg:IsShown() then win:SetPoint("CENTER", cfg, "CENTER", 0, 0) else win:SetPoint("CENTER") end
	win:Show()
	win:Raise()
	return win
end

-- ---------------------------------------------------------------------------
-- The row
-- ---------------------------------------------------------------------------
local search = ""       -- Search Loadouts
local refocus = false   -- the box had the cursor before the page was drawn again

local function GroupLabel(holder, key)
	if not holder.spName then
		holder.spName = holder:CreateFontString(nil, "OVERLAY")
		holder.spName:SetFontObject(Core.fonts.section)
		holder.spName:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -6)
		holder.spName:SetWidth(GUTTER - 14)
		holder.spName:SetJustifyH("LEFT")
		holder.spName:SetWordWrap(true)
		holder.spSub = holder:CreateFontString(nil, "OVERLAY")
		holder.spSub:SetFontObject(Core.fonts.small)
		holder.spSub:SetPoint("TOPLEFT", holder.spName, "BOTTOMLEFT", 0, -4)
		holder.spSub:SetWidth(GUTTER - 14)
		holder.spSub:SetJustifyH("LEFT")
		holder:EnableMouse(true)
		holder:RegisterForDrag("LeftButton")
		holder:SetScript("OnDragStart", function(h) StartGroupDrag(h) end)
		holder:SetScript("OnDragStop", function(h) StopGroupDrag(h) end)
		holder:SetScript("OnMouseUp", function(h, button)
			if h.spDragged or button ~= "LeftButton" or not h.spGroupID then return end
			SP:OpenLoadoutGroupWindow(h.spGroupID)
		end)
		-- Edit under the name: the group's window (its zone, kind, switches, Delete This Group)
		holder.spEdit = Core:MakeButton(holder, "Edit", 56, false)
		holder.spEdit:SetHeight(22)
		holder.spEdit:SetPoint("TOPLEFT", holder.spSub, "BOTTOMLEFT", 0, -6)
		holder.spEdit:SetScript("OnClick", function()
			if holder.spGroupID then SP:OpenLoadoutGroupWindow(holder.spGroupID) end
		end)
		Core:AttachTooltip(holder.spEdit, "Edit This Group", "Change its zone, its kind and its switches, or delete it.")
	end
	local g = key ~= EVERYWHERE and SP.LoadoutGroupByID and SP:LoadoutGroupByID(key) or nil
	holder.spGroupID = g and g.id or nil
	holder.spEdit:SetShown(g ~= nil)
	holder.spName:SetAlpha(1)
	holder.spSub:SetAlpha(1)
	if g then
		local name = SP:LoadoutGroupName(g)
		holder.spName:SetText(name:upper())
		if SP:LoadoutGroupIsRaid(g) then holder.spName:SetTextColor(FireRGB()) else holder.spName:SetTextColor(Core:Color("text")) end
		holder.spSub:SetText(SP:LoadoutGroupKindText(g))
		Core:AttachTooltip(holder, name, "Its loadouts show only " .. (g.kind == "zone" and ("in " .. name) or ("in " .. SP:LoadoutGroupKindText(g):lower()))
			.. ". The first one is the loadout you switch to when you enter.", "Click: change this group\nDrag: move the whole group")
	else
		holder.spName:SetText("EVERYWHERE")
		holder.spName:SetTextColor(Core:Color("textDim"))
		holder.spSub:SetText("In every zone")
		Core:AttachTooltip(holder, "Everywhere", "Loadouts on no group: they show in every zone (except where a group turned Also Show My Other Loadouts Here off).")
	end
end

Row = ns.IconRow.New({
	caption = function()
		if #List() == 0 then return CAPTION_NONE end
		return CAPTION
	end,
	hint = "Click: show or hide it\nRight-click: switch to it, its totems and more\nDrag: onto a group, or to another place",
	list = function(out)
		local q = strlower(strtrim((search:gsub("%s+", " "))))   -- (not Norm: a leading "the" counts here)
		local function Add(lo, i, key)
			local name = lo.name or ("Loadout " .. i)
			if q == "" or strlower(name):find(q, 1, true) then out[#out + 1] = { key = lo, name = name, group = key } end
		end
		local n0 = #out
		for i, lo in ipairs(List()) do
			if not GroupOf(lo) then Add(lo, i, EVERYWHERE) end
		end
		-- an empty line still takes a drop (and + sits after it)
		if #out == n0 and q == "" and #List() > 0 then
			out[#out + 1] = { key = "empty:" .. EVERYWHERE, empty = true, group = EVERYWHERE, name = "" }
		end
		for _, g in ipairs(SP.LoadoutGroups and SP:LoadoutGroups() or {}) do
			n0 = #out
			for i, lo in ipairs(List()) do
				if lo.group == g.id then Add(lo, i, g.id) end
			end
			if #out == n0 and q == "" then out[#out + 1] = { key = "empty:" .. g.id, empty = true, group = g.id, name = "" } end
		end
	end,
	textures = function(item, out)
		if item.empty then return 0 end
		local i = IndexOf(item.key)
		out[1] = (i and SP:GetLoadoutIcon(i)) or "Interface\\Icons\\ClassIcon_Shaman"
		return 1
	end,
	shown = function(item) if item.empty then return true end return not item.key.hidden end,
	tooltip = function(item)
		if item.empty then
			if item.group == EVERYWHERE then return "Drag a loadout here: it shows in every zone." end
			local g = SP:LoadoutGroupByID(item.group)
			return "An empty group. Drag loadouts onto it: they show only " .. (g and ("in " .. SP:LoadoutGroupName(g)) or "there") .. "."
		end
		local lo = item.key
		local i = IndexOf(lo)
		local body = i and SP:GetLoadoutDescription(i) or ""
		local p = SetPageOf(lo)
		if PAGE_NAMES[p] then body = body .. "\nBlizzard totem set: " .. PAGE_NAMES[p] .. "." end
		local g = GroupOf(lo)
		if g and SP:LoadoutGroupFirst(g) == i and g.entry ~= false then
			body = body .. "\nOn Entry: you switch to it when you enter " .. SP:LoadoutGroupName(g) .. "."
		end
		if lo.hidden then body = "Hidden: not in your loadout flyout or the Loadout List.\n" .. body end
		if InUse(lo) then
			body = (Differs(lo) and "In use. Its totems changed here since: right-click it > Switch To This Loadout puts them on your bar.\n"
				or "In use.\n") .. body
		end
		return body
	end,
	label = function(item)
		if item.empty then return "Drag here", false end
		local lo = item.key
		local text = NameOf(lo)
		local g = GroupOf(lo)
		if g and g.entry ~= false and SP:LoadoutGroupFirst(g) == IndexOf(lo) then
			text = text .. "\n|cff3FA9F5On Entry|r"
		end
		return text, InUse(lo)
	end,
	mark = function(item) if item.empty then return false end return InUse(item.key) end,
	add = {
		name = "New",
		tip = "Saves the totems on your bar now as a new loadout (your 4 totems and which of them Drop All leaves out)"
			.. " and puts it in use. Then a box to name it.",
		hint = "Click: save a new loadout",
		shown = function() return search == "" end,
		click = NewLoadout,
	},
	toggle = function(item) if not item.empty then ToggleHidden(item.key) end end,
	menu = MenuItems,
	group = function(item) return item.group end,
	groupLabel = GroupLabel,
	groupLabelWidth = GUTTER,
	groupGap = 12,
	crossGroups = true,
	addGroup = EVERYWHERE,
	movable = function(item) return not item.empty end,
	-- a drop: the group and the place under the cursor (the list order alone can't say which line)
	moveAlways = function() return true end,
	move = function(item)
		if item.empty then return end
		local cx, cy = Row:CursorInFrame()
		PlaceAt(item, cx, cy)
	end,
	locked = function() return InCombatLockdown() end,
	onLocked = function() print(COMBAT) end,
})
ns.CustomRows.loadoutIcons = Row
ns.LoadoutRow = Row

-- Search Loadouts over the tiles: only the names that have the words typed (+ and the empty
-- plates hide while a search is on)
do
	local baseRender = Row.Render
	function Row:Render(body, x, y, width, onChanged)
		local box, used = W:Input(body, { label = "Search Loadouts", x = x, y = y, width = width,
			get = function() return search end,
			set = function(v) search = v or "" end })
		if box.box then
			box.box:SetWidth(math.floor(width * 0.55))
			-- on the left, right after its label
			box.box:ClearAllPoints()
			box.box:SetPoint("LEFT", box.label, "RIGHT", 12, 0)
			box.box:SetScript("OnTextChanged", function(b, user)
				if not user then return end
				search = b:GetText() or ""
				refocus = true
				Redraw()
			end)
			if refocus then
				refocus = false
				box.box:SetFocus()
				box.box:SetCursorPosition(#search)
			end
		end
		local frame, height = baseRender(self, body, x, y + used, width, onChanged)
		return frame, height + used
	end
end

-- A group changed somewhere else (its kind of zone learned on a visit): the page is drawn again
function SP:LoadoutGroupsChangedUI()
	if Row.frame and Row.frame:IsVisible() then Redraw() end
end

-- A loadout switched, saved, deleted or changed somewhere else (the loadout bar, /spl, the
-- minimap menu, a group's switch, Blizzard's totem bar) while the page is open: drawn again, once,
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
