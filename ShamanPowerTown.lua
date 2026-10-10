-- ShamanPowerTown: Out Of The Way (A27, 2026-10-10). One rule, read in one place: in a rested
-- area (a city or an inn), or anywhere (Where: Anywhere Outside A Fight), out of a fight, not
-- inside an instance, and with no enemy targeted (red or yellow: anything you can attack),
-- the displays that follow the rule get out of the way: hidden, or faded to Appearance >
-- Visibility's Faded Opacity. Any one of the four ending brings them back at once. Each module
-- asks the rule when it draws itself and is told when the rule changes; the bars that take
-- clicks in a fight (the cooldown, loadout and controller bars) are hidden by a secure state
-- driver that shows them the moment a fight starts, since a fight ends town but Show is
-- protected then. Off by default; each module has its own line under the switch.
local SP = ShamanPower

local Town = { inTown = false, listeners = {}, drivers = {} }
SP.Town = Town
-- the modules with a line under the switch (Appearance > Visibility > In Town)
SP.TOWN_MODULES = {
	{ key = "rr", name = "Ready Reminders" }, { key = "sc", name = "Shield Charges" }, { key = "cd", name = "Cooldown Bar" },
	{ key = "tb", name = "Totem Bar (and its flyouts)" }, { key = "lb", name = "Loadout Bar" },
	{ key = "ctl", name = "Controller Bar", forever = true }, { key = "ea", name = "Expiring Alerts" },
	{ key = "es", name = "Earth Shield Tracker" }, { key = "pb", name = "Party Buff Tracker" },
}

-- a plain true (a hidden value is neither true nor false here)
local function yes(v)
	if issecretvalue and issecretvalue(v) then return false end
	return v == true
end

local function compute()
	local o = SP.opt
	if not (o and o.hideInTown == true) then return false end
	if SP.IsOff and SP:IsOff() then return false end
	if InCombatLockdown() or yes(UnitAffectingCombat("player")) then return false end
	if (o.townWhere or "town") == "town" and not yes(IsResting()) then return false end   -- (Where: In A City Or Inn)
	if yes((IsInInstance())) then return false end   -- a dungeon, raid, battleground or arena
	if yes(UnitExists("target")) and yes(UnitCanAttack("player", "target")) and not yes(UnitIsDeadOrGhost("target")) then return false end
	return true
end

-- the switch covers this module (on, and the module's own line not turned off)
function SP:TownCovers(module)
	local o = self.opt
	if not (o and o.hideInTown == true) then return false end
	local mods = o.townModules
	return not (type(mods) == "table" and mods[module] == false)
end
-- the rule hides (or fades) this module's display right now
function SP:TownHides(module) return Town.inTown and self:TownCovers(module) end
function SP:InTown() return Town.inTown end
function SP:TownFades() return self.opt ~= nil and self.opt.townHow == "fade" end
function SP:TownFadeAlpha()
	local v = tonumber(self.opt and self.opt.fadeOpacity) or 0.25
	if v > 1 then v = v / 100 end
	if v < 0 then v = 0 elseif v > 1 then v = 1 end
	return v
end
-- what a display's own opacity is multiplied by: the fade while the rule fades it, else 1
function SP:TownAlphaMul(module)
	if self:TownHides(module) and self:TownFades() then return self:TownFadeAlpha() end
	return 1
end

-- a bar that takes clicks in a fight: hidden by a secure state driver that shows it the moment a
-- fight starts (Show is protected then); off the driver, the bar's own code shows it again
function SP:TownDriveHidden(frame, on)
	if not frame then return end
	if on then
		if not Town.drivers[frame] and RegisterStateDriver then
			Town.drivers[frame] = true
			pcall(RegisterStateDriver, frame, "visibility", "[combat] show; hide")
		end
	elseif Town.drivers[frame] then
		Town.drivers[frame] = nil
		if UnregisterStateDriver then pcall(UnregisterStateDriver, frame, "visibility") end
	end
end

-- a module's hook, run when the rule changes (with whether it is in town)
function SP:OnTownChange(fn) Town.listeners[#Town.listeners + 1] = fn end

local function apply()
	local function run(name) local fn = SP[name]; if fn then local ok, err = pcall(fn, SP); if not ok and geterrorhandler then geterrorhandler()(err) end end end
	run("UpdateTotemBarVisibility")
	run("TownApplyCooldownBar")
	run("TownApplyLoadoutBar")
	run("TownApplyController")
	run("TownApplyESTracker")
	run("UpdateCoverage")
	run("UpdatePartyStrip")
	run("UpdateShieldChargeDisplays")
	for _, fn in ipairs(Town.listeners) do
		local ok, err = pcall(fn, Town.inTown)
		if not ok and geterrorhandler then geterrorhandler()(err) end
	end
end

-- the rule again (an event, a setting): the modules draw themselves when it changes
function SP:TownRefresh(force)
	local now = compute()
	if now ~= Town.inTown or force then
		Town.inTown = now
		apply()
	end
end

local f = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_UPDATE_RESTING", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
	"ZONE_CHANGED_NEW_AREA", "PLAYER_TARGET_CHANGED" }) do
	f:RegisterEvent(ev)
end
if f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, "UNIT_FACTION", "target") end
f:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then C_Timer.After(0.5, function() SP:TownRefresh() end) return end   -- (the options and the bars are up)
	SP:TownRefresh()
end)
