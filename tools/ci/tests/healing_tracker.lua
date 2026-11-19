-- client: both
-- (3.0.9.17, A117) Frame Buff Indicators (the module ShamanPower_HealingTracker; WoW: Forever only). Your Riptide and Ancestral Healing
-- (Ancestral Fortitude) on WoW's own party and raid frames: on each frame, one game-drawn slot per buff (an
-- AuraContainer on the frame's unit, YOUR buff's IDs) with its icon, the sweep handed over (SetDurationCooldown)
-- and the time left (SetDurationText). Each buff its own size, spot and look, set in its icon's right-click menu
-- on the page (an icon row, as Shield Charges'). A slot is made ONCE: every look change goes onto the same parts
-- (the owner's test, 11-18: a remade slot showed a new Icon Size only from the next cast). Built out of combat
-- only. Party Frames / Raid Frames switches, never a pet's frame. Off by default.
local SP = ShamanPower
local W = __sim.W

if not SPCompat.FOREVER then
	check("Anniversary: no Frame Buff Indicators module", SP.HealingTrackerLoaded == nil)
	check("Anniversary: no page", SP.options.args.fluffy.args.healingtracker_section == nil)
	check("Anniversary: no icon row", SP.HealingIconsRow == nil)
	local area = false
	for _, a in ipairs(SP.FONT_AREAS) do if a.key == "healing" then area = true end end
	check("Anniversary: no font row", not area)
	finish()
	return
end

check("the module is loaded", SP.HealingTrackerLoaded == true)
local sv = ShamanPowerHealingTrackerDB
check("its own saved settings", type(sv) == "table")
if type(sv) ~= "table" then finish() return end
local keep = {}
for k, v in pairs(sv) do keep[k] = v end
check("off by default", (sv.enabled or false) == false)
local area = false
for _, a in ipairs(SP.FONT_AREAS) do if a.key == "healing" then area = true end end
check("its own font row (Appearance > Fonts & Textures > Frame Buff Indicators)", area)
check("its page: Frame Buff Indicators", SP.options.args.fluffy.args.healingtracker_section
	and SP.options.args.fluffy.args.healingtracker_section.name:find("Frame Buff Indicators", 1, true) ~= nil)
local page = SP.options.args.fluffy.args.healingtracker_section
check("its own page", page ~= nil)
if not page then finish() return end
local function setting(key, v) page.args[key].set(nil, v) end

-- the page: the buffs as icons (each one's settings in its menu), the switches under them
check("the page has the icon row", page.args.healingIcons ~= nil and SP.OptionCustomRow[page.args.healingIcons] == "healingIcons")
check("no rows of switches per buff", page.args.ht_riptide_size == nil and page.args.ht_ancestral_point == nil)
check("the icon row is made", SP.HealingIconsRow ~= nil)
local row = SP.HealingIconsRow
local items = {}
row.def.list(items)
checkEq("two icons", #items, 2)
checkEq("first: Riptide", items[1] and items[1].name, "Riptide")
checkEq("second: Ancestral Healing", items[2] and items[2].name, "Ancestral Healing")
local function menu(key)
	local byText = {}
	for _, it in ipairs(row.def.menu({ key = key })) do if it.text then byText[it.text] = it end end
	return byText
end
local m = menu("riptide")
for _, name in ipairs({ "Icon Size", "Position", "Offset X", "Offset Y", "Show Sweep", "Show Time Left", "Time Text Size",
	"Copy Settings To...", "Reset This Icon", "Hide This Icon" }) do
	check("its menu: " .. name, m[name] ~= nil)
end
local function slide(key, text, v) local it = menu(key)[text]; it.slider.set(v) end
local function pick(key, text, v)
	for _, c in ipairs(menu(key)[text].sub()) do
		if c.text == v then c.onClick() return end
	end
	error("no choice " .. tostring(v) .. " in " .. text)
end

-- the game's part, watched: which unit each container is bound to, and what each slot was handed
local AC = W.foreverClasses.AuraContainer.methods
local AB = W.foreverClasses.AuraButton.methods
local realSetUnit, realSetEnabled = AC.SetUnit, AC.SetEnabled
local boundTo, enabledOf = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
function AC:SetUnit(u) boundTo[self] = u return realSetUnit(self, u) end
function AC:SetEnabled(on) enabledOf[self] = on return realSetEnabled(self, on) end
local handed = {}
local realCd, realText, realIcon, realSlot = AB.SetDurationCooldown, AB.SetDurationText, AB.SetIcon, AC.AddAuraSlot
local slotArgs, slots = {}, 0
function AC:AddAuraSlot(key, filter, options)
	slots = slots + 1
	slotArgs[key] = { filter = filter, ids = options and options.candidateFilters and options.candidateFilters.includeSpellIDs }
	return realSlot(self, key, filter, options)
end
AB.SetDurationCooldown = function(self, cd) handed.cd = (handed.cd or 0) + 1; if realCd then return realCd(self, cd) end end
AB.SetDurationText = function(self, fs, o) handed.text = (handed.text or 0) + 1; if realText then return realText(self, fs, o) end end
AB.SetIcon = function(self, t) handed.icon = (handed.icon or 0) + 1; if realIcon then return realIcon(self, t) end end

-- WoW's frames, as the game names them (a pet's frame too, which never gets one)
local function cuf(name, unit)
	local f = _G[name] or CreateFrame("Button", name, UIParent)
	f:SetSize(72, 36)
	f:SetPoint("CENTER")
	f.unit = unit
	f:Show()
	return f
end
local p1 = cuf("CompactPartyFrameMember1", "player")
local p2 = cuf("CompactPartyFrameMember2", "party1")
local r1 = cuf("CompactRaidFrame1", "raid1")
local g1 = cuf("CompactRaidGroup2Member3", "raid8")
local pet = cuf("CompactPartyFramePet1", "partypet1")
local recs = SP.HealingTrackerState.recs

SP:UpdateHealingTracker()
check("off: nothing made on any frame", next(recs) == nil)

setting("ht_enabled", true)
local function part(f, key) return recs[f] and recs[f].parts[key] end
for _, f in ipairs({ p1, p2, r1, g1 }) do
	check(f:GetName() .. ": Riptide's slot", part(f, "riptide") and part(f, "riptide").container ~= nil)
	check(f:GetName() .. ": Ancestral Healing's slot", part(f, "ancestral") and part(f, "ancestral").container ~= nil)
end
check("never a pet's frame", recs[pet] == nil)
checkEq("Riptide's slot: your buffs only", slotArgs.riptide and slotArgs.riptide.filter, "HELPFUL|PLAYER")
local rip = slotArgs.riptide and slotArgs.riptide.ids or {}
check("Riptide's slot: every rank", rip[408521] and rip[1239242] and rip[1239243] and true or false)
checkEq("Ancestral Healing's slot: your buffs only", slotArgs.ancestral and slotArgs.ancestral.filter, "HELPFUL|PLAYER")
check("Ancestral Healing's slot: Ancestral Fortitude", slotArgs.ancestral and slotArgs.ancestral.ids and slotArgs.ancestral.ids[16177] == true)
checkEq("bound to the frame's player (you)", boundTo[part(p1, "riptide").container], "player")
checkEq("bound to the frame's player (party1)", boundTo[part(p2, "ancestral").container], "party1")
checkEq("bound to the frame's player (raid8)", boundTo[part(g1, "riptide").container], "raid8")
check("switched on", enabledOf[part(r1, "ancestral").container] == true)
check("the icons, sweeps and times left handed to the game", (handed.icon or 0) >= 8 and (handed.cd or 0) >= 8 and (handed.text or 0) >= 8)
local P = part(r1, "riptide")
check("the time left has its font", P.timeText and P.timeText:GetFont() ~= nil)
local _, px = P.timeText:GetFont()
checkEq("the time left sized to the icon (14: 9)", px and math.floor(px + 0.5), 9)
check("the sweep darkens as it runs out (reversed)", P.cd and P.cd:GetReverse() == true)
check("the sweep shows no numbers of its own", P.cd and W.ST[P.cd].hideNumbers == true)   -- (the sim keeps it, no getter)

-- where they sit: Riptide top right, Ancestral Healing top left, 3 in, size 14
local h = P.host
local point, rel, relPoint, x, y = h:GetPoint(1)
checkEq("Riptide: top right", point, "TOPRIGHT")
check("on its frame", rel == r1 and relPoint == "TOPRIGHT")
checkEq("3 in from the edge (x)", x, -3)
checkEq("3 in from the edge (y)", y, -3)
checkEq("size 14", math.floor(h:GetWidth() + 0.5), 14)
local ha = part(r1, "ancestral").host
point, rel, relPoint, x, y = ha:GetPoint(1)
checkEq("Ancestral Healing: top left", point, "TOPLEFT")
checkEq("Ancestral Healing: 3 in (x)", x, 3)

-- every look change from the menu: the same slot, changed in place (never made again)
local c0, fs0, made0 = P.container, P.timeText, slots
pick("riptide", "Position", "Bottom Left")
slide("riptide", "Offset X", 4)
point, rel, relPoint, x, y = h:GetPoint(1)
checkEq("menu Position: bottom left", point, "BOTTOMLEFT")
checkEq("menu Offset X added", x, 7)
checkEq("bottom: 3 up", y, 3)
checkEq("Ancestral Healing stays where it was", ha:GetPoint(1), "TOPLEFT")
slide("riptide", "Icon Size", 22)
checkEq("menu Icon Size 22", math.floor(h:GetWidth() + 0.5), 22)
_, px = P.timeText:GetFont()
checkEq("the time left follows it (22: 14)", px and math.floor(px + 0.5), 14)
checkEq("Ancestral Healing's size untouched", math.floor(ha:GetWidth() + 0.5), 14)
pick("riptide", "Show Sweep", "Off")
check("Show Sweep off: the sweep stops drawing", W.ST[P.cd].drawSwipe == false)
pick("riptide", "Show Time Left", "Off")
check("Show Time Left off: the time left hidden", not P.texts:IsShown())
pick("riptide", "Show Time Left", "On")
check("Show Time Left on: shown again", P.texts:IsShown())
slide("riptide", "Time Text Size", 16)
_, px = P.timeText:GetFont()
checkEq("Time Text Size 16", px and math.floor(px + 0.5), 16)
pick("riptide", "Show Sweep", "On")
check("Show Sweep on: drawing again", W.ST[P.cd].drawSwipe == true)
check("every change: the same slot", P.container == c0 and P.timeText == fs0)
checkEq("no slot made again", slots, made0)

-- the menu's Copy Settings To and Reset This Icon
check("changed from its start: the blue corner", SP:HealingOwnChanged("riptide") == true)
for _, c in ipairs(menu("riptide")["Copy Settings To..."].sub()) do
	if c.text == "Ancestral Healing" then c.onClick() end
end
checkEq("Copy To: Ancestral Healing's size", SP:HealingOpt("ancestral", "size"), 22)
checkEq("Copy To: never its spot", SP:HealingOpt("ancestral", "point"), "TOPLEFT")
checkEq("Copy To: drawn at once", math.floor(ha:GetWidth() + 0.5), 22)
menu("ancestral")["Reset This Icon"].onClick()
checkEq("Reset This Icon: back to 14", SP:HealingOpt("ancestral", "size"), 14)
check("Reset This Icon: Riptide untouched", SP:HealingOpt("riptide", "size") == 22)
check("nothing changed now: no blue corner", SP:HealingOwnChanged("ancestral") == false)

-- a click on an icon: shown or not
row.def.toggle({ key = "ancestral" })
check("click: Ancestral Healing hidden", not part(r1, "ancestral").host:IsShown())
check("click: switched off", enabledOf[part(r1, "ancestral").container] == false)
check("Riptide still on", part(r1, "riptide").host:IsShown())
check("the line beside the icons says so", row.def.beside():find("Ancestral Healing:|r  hidden", 1, true) ~= nil)
row.def.toggle({ key = "ancestral" })
check("click again: shown", part(r1, "ancestral").host:IsShown())
checkEq("and bound again", boundTo[part(r1, "ancestral").container], "raid1")

-- the frames' switches
setting("ht_party", false)
check("Party Frames off: the party frames' icons hidden", not part(p1, "riptide").host:IsShown() and not part(p2, "ancestral").host:IsShown())
check("Party Frames off: switched off", enabledOf[part(p1, "riptide").container] == false)
check("the raid frames still on", part(r1, "riptide").host:IsShown())
setting("ht_party", true)
check("Party Frames on again: shown", part(p1, "riptide").host:IsShown())
checkEq("and bound again", boundTo[part(p1, "riptide").container], "player")
check("and switched on again", enabledOf[part(p1, "riptide").container] == true)
setting("ht_raid", false)
check("Raid Frames off: the raid frames' icons hidden", not part(r1, "riptide").host:IsShown() and not part(g1, "ancestral").host:IsShown())
setting("ht_raid", true)

-- a frame handed another player: bound to them
p2.unit = "party3"
SP:UpdateHealingTracker()
checkEq("a frame's new player: bound to them (Riptide)", boundTo[part(p2, "riptide").container], "party3")
checkEq("a frame's new player: bound to them (Ancestral Healing)", boundTo[part(p2, "ancestral").container], "party3")

-- in a fight: nothing touched until it ends
__sim.setCombat(true)
local cFight = P.container
slide("riptide", "Icon Size", 24)
checkEq("in a fight: the size waits", math.floor(h:GetWidth() + 0.5), 22)
check("in a fight: waiting", SP.HealingTrackerState.pending == true)
__sim.setCombat(false)
W.fireEvent("PLAYER_REGEN_ENABLED")
__sim.advance(0.3)
checkEq("after the fight: the new size", math.floor(h:GetWidth() + 0.5), 24)
check("after the fight: the same slot", P.container == cFight)
check("after the fight: no longer waiting", SP.HealingTrackerState.pending == false)

-- the page's Reset Page Settings: both back to their start, both shown
row.def.toggle({ key = "riptide" })
SP:HealingTrackerResetPage()
checkEq("Reset Page: Riptide's size back", SP:HealingOpt("riptide", "size"), 14)
checkEq("Reset Page: Riptide's spot back", SP:HealingOpt("riptide", "point"), "TOPRIGHT")
check("Reset Page: Riptide shown again", SP:HealingOpt("riptide", "on") == true and P.host:IsShown())

-- off: every icon hidden, every slot switched off
setting("ht_enabled", false)
local allOff = true
for _, r in pairs(recs) do
	for _, pt in pairs(r.parts) do
		if pt.host:IsShown() or enabledOf[pt.container] ~= false then allOff = false end
	end
end
check("off: every icon hidden and switched off", allOff)
setting("ht_enabled", true)
checkEq("on again: bound again", boundTo[P.container], "raid1")
check("on again: shown", P.host:IsShown() and part(r1, "ancestral").host:IsShown())

local status = SP:HealingTrackerStatus()
check("the support code's line", type(status) == "string" and status:find("enabled=true", 1, true) ~= nil
	and status:find("ancestral", 1, true) ~= nil)
check("redrawn with a profile switch", type(SP.UpdateHealingTrackerAppearance) == "function")

-- put back
AC.SetUnit, AC.SetEnabled, AC.AddAuraSlot = realSetUnit, realSetEnabled, realSlot
AB.SetDurationCooldown, AB.SetDurationText, AB.SetIcon = realCd, realText, realIcon
setting("ht_enabled", false)
for k in pairs(sv) do sv[k] = nil end
for k, v in pairs(keep) do sv[k] = v end
for _, f in ipairs({ p1, p2, r1, g1, pet }) do f:Hide() end
finish()
