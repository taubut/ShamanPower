-- client: both
-- (3.0.9.14) Profile by Spec: a profile picked for each spec on the Profiles page. A change of spec puts its profile
-- in use (out of combat); picking one for the spec you're in puts it in use at once; a profile you pick yourself
-- stays until the spec changes; Don't Switch leaves your profile alone; the spec is never guessed.
local SP = ShamanPower
local W = __sim.W
local db = SP.db
local was = db:GetCurrentProfile()
for _, n in ipairs({ "PBS Enh", "PBS Resto", "PBS Other" }) do db:SetProfile(n) end
db:SetProfile(was)
local keepIdx = SP.ShareSpecIndex
local spec, asked = 2, nil
SP.ShareSpecIndex = function(talentsOnly) asked = talentsOnly; return spec end
local function respec(n) spec = n; W.fireEvent("SPELLS_CHANGED"); __sim.advance(1.3) end
local function cur() return db:GetCurrentProfile() end

respec(2)
SP:SetSpecProfile("enhancement", "PBS Enh")
checkEq("picked for the spec you're in: in use at once", cur(), "PBS Enh")
check("the spec is read from the talents only (never the setup's guess)", asked == true)
SP:SetSpecProfile("restoration", "PBS Resto")
checkEq("picked for another spec: yours stays", cur(), "PBS Enh")
respec(1)
checkEq("respec into Restoration: its profile", cur(), "PBS Resto")
respec(2)
checkEq("back to Enhancement: its profile", cur(), "PBS Enh")

-- your own pick stays until the spec changes
db:SetProfile("PBS Other")
W.fireEvent("SPELLS_CHANGED"); W.fireEvent("PLAYER_ENTERING_WORLD"); __sim.advance(1.3)
checkEq("a profile you pick yourself stays (same spec)", cur(), "PBS Other")

-- the talents can't tell: nothing
respec(0)
checkEq("the spec can't be told: no switch", cur(), "PBS Other")

-- a change in a fight: right after it
__sim.setCombat(true)
respec(1)
checkEq("in a fight: not yet", cur(), "PBS Other")
__sim.setCombat(false); W.fireEvent("PLAYER_REGEN_ENABLED"); __sim.advance(0.2)
checkEq("after the fight: its profile", cur(), "PBS Resto")

-- Don't Switch
SP:SetSpecProfile("enhancement", nil)
respec(2)
checkEq("Don't Switch for Enhancement: your profile stays", cur(), "PBS Resto")

-- its profile deleted: no switch, no error
SP:SetSpecProfile("elemental", "PBS Gone")
respec(3)
checkEq("a profile that's gone: no switch", cur(), "PBS Resto")
check("a profile that's gone reads as none", SP:SpecProfileFor("elemental") == nil)

-- the page's three dropdowns
if SP.OpenConfig or SP.options then
	local args = SP.options and SP.options.args and SP.options.args.profiles and SP.options.args.profiles.args
	if args and args.spSpec_enhancement then
		local o = args.spSpec_enhancement
		check("its dropdown lists Don't Switch first", o.sorting()[1] == "\001none" and o.values()["\001none"] == "Don't Switch")
		checkEq("its dropdown shows the pick", args.spSpec_restoration.get(), "PBS Resto")
	end
end

SP.ShareSpecIndex = keepIdx
db.char.specProfiles, db.char.specProfileLast = nil, nil
db:SetProfile(was)
finish()
