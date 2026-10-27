-- client: both
-- The Zone Name box (3.0.9.5): a leading "The" never matters (the game calls one place Molten Core on its map
-- and The Molten Core inside it), zones you stand in are remembered by their exact name and kind, and close
-- names are suggested as you type (nothing when what you typed already matches)
local SP = ShamanPower
if not (SP.LoadoutZoneSuggestions and SP.AddLoadoutGroup and SP.db and SP.db.global) then skip("no zone suggestions") end
local keepGroups, keepSeen = ShamanPower_LoadoutGroups, SP.db.global.zonesSeen
local keepZone, keepInst = GetRealZoneText, IsInInstance
local zone, kind = "Orgrimmar", nil
GetRealZoneText = function() return zone end
IsInInstance = function() if kind then return true, kind end return false, "none" end
local function go(z, k)
	zone, kind = z, k
	__sim.W.fireEvent("ZONE_CHANGED_NEW_AREA")
	__sim.advance(0.1)
end

ShamanPower_LoadoutGroups = {}
SP.db.global.zonesSeen = {}

-- a leading "The" never matters, either way round
local mc = SP:AddLoadoutGroup({ kind = "zone", zone = "Molten Core", zoneType = "raid" })
check("typed Molten Core: found inside (The Molten Core)", SP:LoadoutGroupForZone("The Molten Core") == mc)
SP:EditLoadoutGroup(mc.id, { zone = "The Molten Core" })
check("typed The Molten Core: found as Molten Core", SP:LoadoutGroupForZone("molten core") == mc)
check("a name in the middle still counts", SP:LoadoutGroupForZone("Theramore Isle") == nil)

-- the zones you stand in, by their exact name and kind
go("The Molten Core", "raid")
local seen = SP.db.global.zonesSeen["molten core"]
check("remembered on entering", seen ~= nil)
checkEq("its exact name", seen and seen.name, "The Molten Core")
checkEq("its kind", seen and seen.kind, "raid")
go("Ragefire Chasm", "party")

-- suggestions
local s = SP:LoadoutZoneSuggestions("Molton Core", 3)
checkEq("a typo: The Molten Core first", s[1] and s[1].name, "The Molten Core")
checkEq("with its kind (you've been there)", s[1] and s[1].kind, "raid")
checkEq("Molten Core matches as typed: nothing to suggest", #SP:LoadoutZoneSuggestions("molten core", 3), 0)
checkEq("Ragefire Chasm as typed: nothing", #SP:LoadoutZoneSuggestions("Ragefire Chasm", 3), 0)
s = SP:LoadoutZoneSuggestions("ragefire", 3)
checkEq("the start of a name: Ragefire Chasm", s[1] and s[1].name, "Ragefire Chasm")
checkEq("under three letters: nothing", #SP:LoadoutZoneSuggestions("mo", 3), 0)
checkEq("nothing close: nothing", #SP:LoadoutZoneSuggestions("Qqqqqq Zzzz", 3), 0)

-- filling in the rest as you type
checkEq("Molt fills in Molten Core (The left out)", SP:LoadoutZoneComplete("Molt"), "Molten Core")
checkEq("The Mol fills in The Molten Core", SP:LoadoutZoneComplete("The Mol"), "The Molten Core")
checkEq("ragefire c: Ragefire Chasm", SP:LoadoutZoneComplete("ragefire c"), "Ragefire Chasm")
check("a whole name: nothing to fill in", SP:LoadoutZoneComplete("Ragefire Chasm") == nil)
check("one letter: nothing", SP:LoadoutZoneComplete("R") == nil)
-- the box (the sim's edit box has no cursor: it stands at the end, as when typing)
if SP.OpenLoadoutGroupWindow then
	SP:OpenLoadoutGroupWindow()
	local row = __sim.frameWithText("Zone Name")
	local box = row and row.box
	check("the Zone Name box", box ~= nil)
	if box then
		box.GetCursorPosition = function(b) return #b:GetText() end
		box.SetCursorPosition = function() end
		local h = box:GetScript("OnTextChanged")
		box:SetText("Mol")
		box.spTyped = 2
		h(box, true)
		checkEq("typing Mol fills the box in", box:GetText(), "Molten Core")
		box:SetText("Mol")
		box.spTyped = #"Molten Core"
		h(box, true)
		checkEq("Backspace (shorter): nothing filled in", box:GetText(), "Mol")
	end
	if ShamanPowerLoadoutGroupWindow then ShamanPowerLoadoutGroupWindow:Hide() end
end

-- the game's own dungeon and raid names (ShamanPowerZoneNames.lua), with nothing remembered yet
check("the instance list loaded", type(SP.INSTANCE_NAMES) == "table" and #SP.INSTANCE_NAMES > 20)
SP.db.global.zonesSeen = {}
checkEq("never been there: Molt still fills in Molten Core", SP:LoadoutZoneComplete("Molt"), "Molten Core")
s = SP:LoadoutZoneSuggestions("Molton Core", 3)
checkEq("never been there: Molton Core suggests Molten Core", s[1] and s[1].name, "Molten Core")
checkEq("as a raid (from the game's data)", s[1] and s[1].kind, "raid")
check("not as somewhere you've been", s[1] and not s[1].seen)

-- back as it was
GetRealZoneText, IsInInstance = keepZone, keepInst
ShamanPower_LoadoutGroups, SP.db.global.zonesSeen = keepGroups, keepSeen
SP:LoadoutGroupsChanged()
finish()
