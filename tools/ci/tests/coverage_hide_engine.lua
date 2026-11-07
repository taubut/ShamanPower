-- client: forever
-- regime: secrets
-- The preview has no native aura evaluation. Model only aura slot visibility and
-- one-slot group dimensions; the real addon owns all clipping and cell painting.
-- This checks layout/ownership and transitions, not WoW's secret-access enforcement.
local SP, ST = ShamanPower, __sim.ST
if not SP:CoverageAvailable() then skip("no native aura containers") end
local ACM = __sim.W.foreverClasses.AuraContainer.methods
local original = { add = ACM.AddAuraSlot, group = ACM.AddAuraGroup, update = ACM.UpdateAllAuras,
	exists = UnitExists, name = UnitName, class = UnitClass, visible = UnitIsVisible,
	grouped = IsInGroup, count = GetNumSubgroupMembers, position = UnitPosition,
	info = SP.GetElementTotemInfo, buff = SP.GetActiveTotemBuffName,
	has = SP.UnitHasBuff, unread = SPCompat.AurasUnreadable, coverage = SP.opt.coverage }
local names = { party1 = "Grak", party2 = "Mosh", party3 = "Lina", party4 = "Tova" }
local buffed, far = { party1 = true, party2 = true, party3 = true, party4 = true }, {}
local groupAdds = 0
UnitExists = function(u) if names[u] then return true end return original.exists(u) end
UnitName = function(u) if names[u] then return names[u] end return original.name(u) end
UnitClass = function(u) if names[u] then return "Warrior", "WARRIOR", 1 end return original.class(u) end
UnitIsVisible = function(u) if names[u] then return not far[u] end return original.visible(u) end
IsInGroup = function() return true end
GetNumSubgroupMembers = function() return 4 end
UnitPosition = function() return nil end
function ACM:AddAuraSlot(key, filter, options)
	local b = original.add(self, key, filter, options)
	ST[self].coverageSlot = { button = b, options = options }
	return b
end
function ACM:AddAuraGroup(key, filter, options)
	assert(not InCombatLockdown(), "aura group rebuilt during combat")
	assert(filter == "HELPFUL|PLAYER", "coverage must match the player's buffs")
	assert(options.maxFrameCount == 1, "one covered member contributes once")
	groupAdds = groupAdds + 1
	original.group(self, key, filter, options)
	ST[self].coverageGroup = options
end
function ACM:UpdateAllAuras()
	local s = ST[self]
	local slot, group = s.coverageSlot, s.coverageGroup
	local options = group or (slot and slot.options)
	if not options then return end
	local ids = options.candidateFilters.includeSpellIDs
	local present = s.auraEnabled and buffed[s.auraUnit] and ids[8076] or false
	if slot then slot.button:SetShown(present) end
	if group then
		-- Native flow layout's minimum empty dimensions are one pixel.
		self:SetSize(present and group.layout.elementWidth or 1, present and group.layout.elementHeight or 1)
	end
end
SP.GetElementTotemInfo = function(_, e)
	if e == 1 then return true, "Strength of Earth Totem", GetTime() - 5, 120, 136023 end
	return false
end
SP.GetActiveTotemBuffName = function(_, e) if e == 1 then return SP.TotemBuffNames[1][1], 1 end end
SP.UnitHasBuff = function(_, unit) return buffed[unit] or false end
SPCompat.AurasUnreadable = function() return InCombatLockdown() end
SP.opt.coverage = { enabled = true, hideWhenCovered = true, iconSize = 60, showTimer = true }
SP:RebuildCoverage()
local cell = SP.coverageFrame.buttons[1]
local function auraPass()
	for _, f in ipairs(__sim.W.frames) do if f:GetObjectType() == "AuraContainer" then f:UpdateAllAuras() end end
end
local function descendant(f, ancestor)
	while f do if f == ancestor then return true end f = f:GetParent() end
	return false
end
local function contains(outer, inner)
	return outer:GetLeft() <= inner:GetLeft() and outer:GetRight() >= inner:GetRight()
		and outer:GetBottom() <= inner:GetBottom() and outer:GetTop() >= inner:GetTop()
end
local function excluded(c)
	return c.coverageClip:DoesClipChildren() and c.coverageClip:GetLeft() > c.visual:GetRight()
end
local function fullCellInside(c)
	if not contains(c.coverageClip, c.visual) then return false end
	for _, row in ipairs(c.rows) do if not contains(c.coverageClip, row) then return false end end
	return true
end
__sim.setCombat(true)
auraPass()
SP:UpdateCoverage()
checkEq("uses dungeon engine path", cell.state, "engine")
check("engine hide setup succeeded", cell.coverAll.hideReady)
checkEq("one aura ruler per party member", #cell.coverAll.hideContainers, 4)
check("everyone covered: entire artwork excluded", excluded(cell))
check("root cell has no own drawable regions", select("#", cell:GetRegions()) == 0)
check("backdrop inside clip", descendant(cell.visual, cell.coverageClip))
for _, part in ipairs({ cell.icon, cell.rangeOverlay, cell.statusText, cell.timerText, cell.coverAll.ring }) do
	check("cell visual stays below clip: " .. tostring(part), descendant(part, cell.coverageClip))
end
for _, row in ipairs(cell.rows) do
	check("name and dot below clip", descendant(row.text, cell.coverageClip) and descendant(row.dot, cell.coverageClip))
end
for _, c in ipairs(cell.coverAll.hideContainers) do
	check("aura ruler is outside clip", not descendant(c, cell.coverageClip))
end
check("timer is live behind the clip", cell.timerText:IsShown())
local addsBeforeCombat = groupAdds
-- Any one member, including the first and last nested aura slots, must restore
-- the whole cell, without moving it or calling UpdateCoverage at all.
local left, top, tex = cell:GetLeft(), cell:GetTop(), cell.icon:GetTexture()
-- A repeat of the failed visibility-read approach must not pass this fixture.
local ringVisible = cell.coverAll.ring.IsVisible
cell.coverAll.ring.IsVisible = function() error("aura subtree visibility cannot be read in combat") end
for i = 1, 4 do
	local unit = "party" .. i
	buffed[unit] = false
	auraPass()
	check("member " .. i .. " loses buff: full cell fits clip", fullCellInside(cell))
	check("member " .. i .. " loses buff: visible layout retained", cell:IsVisible())
	checkEq("cell left unchanged", cell:GetLeft(), left)
	checkEq("cell top unchanged", cell:GetTop(), top)
	checkEq("icon unchanged", cell.icon:GetTexture(), tex)
	buffed[unit] = true
	auraPass()
	check("member " .. i .. " regains buff: whole cell gone", excluded(cell))
end
checkEq("aura transitions never rebuild groups in combat", groupAdds, addsBeforeCombat)
SP:UpdateCoverage()
cell.coverAll.ring.IsVisible = ringVisible
SP.opt.coverage.hideWhenCovered = false
SP:UpdateCoverage()
check("option off disables clipping", not cell.coverageClip:DoesClipChildren())
SP.opt.coverage.hideWhenCovered = true
SP.opt.coverage.plainIcon = true
SP:UpdateCoverage()
check("plain icon still hides when covered", excluded(cell))
checkEq("plain icon suppresses green independently", cell.coverAllHolder:GetAlpha(), 0)
SP.opt.coverage.plainIcon = nil
far.party3 = true
SP:UpdateCoverage()
check("far-away member keeps cell visible", not cell.coverageClip:DoesClipChildren())
far.party3 = nil
SP._coveragePending = true
SP:UpdateCoverage()
check("stale roster cannot hide cell", not cell.coverageClip:DoesClipChildren())
checkEq("stale roster is neutral", cell.state, "combat")
SP._coveragePending = false
SP:UpdateCoverage()
check("ready roster resumes clipping", excluded(cell))
__sim.setCombat(false)
buffed.party4 = false
SP:UpdateCoverage()
checkEq("readable buffs retain missing state", cell.state, "missing")
check("readable buffs bypass clipping", not cell.coverageClip:DoesClipChildren())
buffed.party4 = true
SP:UpdateCoverage()
check("readable buffs still hide covered cells", not cell:IsVisible())
SP:CoverageDemo(true)
check("preview disables live clipping", not cell.coverageClip:DoesClipChildren())
SP:CoverageDemo(false)
-- Free placement changes parents and frame levels; it must retain the entire
-- visual below the clip and keep aura evaluation outside that clip.
SP.opt.coverage.freeCells = true
SP:RebuildCoverage()
local free = SP:CoverageTotemCell(1, 1)
__sim.setCombat(true)
auraPass()
SP:UpdateCoverage()
checkEq("free cell is parented to screen", free:GetParent(), UIParent)
check("free cell covered: entire art excluded", excluded(free))
buffed.party4 = false
auraPass()
check("free cell missing: all artwork fits", fullCellInside(free))
check("free icon below clip", descendant(free.icon, free.coverageClip))
buffed.party4 = true
auraPass()
check("free cell covered again", excluded(free))

-- A rejected group setup leaves the existing green-border display available,
-- but must not leave an old clipping rule hiding an otherwise valid cell.
__sim.setCombat(false)
SP.opt.coverage.freeCells = false
SP.opt.coverage.tracked = { [8072] = false }
local healthyGroup = ACM.AddAuraGroup
ACM.AddAuraGroup = function() error("fixture: aura group unavailable", 0) end
SP:RebuildCoverage()
ACM.AddAuraGroup = healthyGroup
__sim.setCombat(true)
SP:UpdateCoverage()
check("failed group setup stays visible", cell:IsVisible() and not cell.coverageClip:DoesClipChildren())
check("failed group setup is not treated as ready", cell.coverAll and not cell.coverAll.hideReady)

__sim.setCombat(false)
ACM.AddAuraSlot, ACM.AddAuraGroup, ACM.UpdateAllAuras = original.add, original.group, original.update
UnitExists, UnitName, UnitClass, UnitIsVisible = original.exists, original.name, original.class, original.visible
IsInGroup, GetNumSubgroupMembers, UnitPosition = original.grouped, original.count, original.position
SP.GetElementTotemInfo, SP.GetActiveTotemBuffName = original.info, original.buff
SP.UnitHasBuff, SPCompat.AurasUnreadable = original.has, original.unread
SP.opt.coverage = original.coverage
SP:RebuildCoverage()
finish()
