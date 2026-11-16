-- client: forever
-- (3.0.9.15) Rakii on Discord: at 60 the login line listed Flame Shock 6, Grace of Air Totem 3, Healing Wave 10 and
-- Strength of Earth Totem 5 as waiting at the trainer, though WoW: Forever's trainers don't teach them yet (they
-- are in its game files from later vanilla patches). They wait now until a trainer is seen offering them; then
-- that rank is reminded like any other. The rest of the list is as before.
local SP = ShamanPower
local W = __sim.W
if not SP.TrainerReminderReport then skip("no Trainer Reminder here") end
local LATER = { 29228, 25359, 25357, 25361 }
for _, id in ipairs(LATER) do if not SPCompat.SpellName(id) then skip("the sim has no name for " .. id) end end
local later = {}
for _, id in ipairs(LATER) do later[id] = true end

-- a level-60 shaman who has bought everything else
local keep = { UnitLevel = UnitLevel, known = IsSpellKnown, player = IsPlayerSpell, num = GetNumTrainerServices,
	info = GetTrainerServiceInfo, tip = C_TooltipInfo and C_TooltipInfo.GetTrainerService }
UnitLevel = function() return 60 end
IsSpellKnown = function(id) return not later[id] end
IsPlayerSpell = function(id) return not later[id] end
SP.db.global.trainerSeen = nil
local said = {}
local add = DEFAULT_CHAT_FRAME.AddMessage
DEFAULT_CHAT_FRAME.AddMessage = function(self, text, ...) said[#said + 1] = tostring(text); return add(self, text, ...) end
local function report() said = {}; SP:TrainerReminderReport(); return table.concat(said, "\n") end

local out = report()
check("no trainer seen yet: the four are not reminded", out:find("nothing new at your trainer", 1, true) ~= nil, out)

-- a trainer offering Flame Shock (Rank 6), by name and rank (WoW: Forever's order: name, type, texture, level, rank text)
local fs = SPCompat.SpellName(29228)
GetNumTrainerServices = function() return 2 end
GetTrainerServiceInfo = function(i)
	if i == 1 then return fs, "available", 135813, 60, "Rank 6", "" end
	return SPCompat.SpellName(10414), "used", 136026, 60, "Rank 7", ""
end
if C_TooltipInfo then C_TooltipInfo.GetTrainerService = function() return nil end end
W.fireEvent("TRAINER_SHOW")
out = report()
check("seen at the trainer: Flame Shock (Rank 6) is reminded", out:find(fs .. " (Rank 6)", 1, true) ~= nil, out)
check("the three not seen yet still wait", not out:find(SPCompat.SpellName(25357), 1, true) and not out:find(SPCompat.SpellName(25361), 1, true), out)
check("remembered for the account", SP.db.global.trainerSeen and SP.db.global.trainerSeen[29228] == true)

-- by the spell ID the trainer's tooltip data gives
if C_TooltipInfo then
	GetNumTrainerServices = function() return 1 end
	GetTrainerServiceInfo = function() return "x", "available", nil, 60, "", "" end
	C_TooltipInfo.GetTrainerService = function() return { id = 25357 } end
	W.fireEvent("TRAINER_UPDATE")
	out = report()
	check("by its spell ID: Healing Wave (Rank 10) is reminded", out:find(SPCompat.SpellName(25357) .. " (Rank 10)", 1, true) ~= nil, out)
end

-- learned: gone from the list, as any rank
IsSpellKnown = function(id) return id ~= 25359 and id ~= 25361 end
IsPlayerSpell = IsSpellKnown
out = report()
check("bought: no longer reminded", out:find("nothing new at your trainer", 1, true) ~= nil, out)

DEFAULT_CHAT_FRAME.AddMessage = add
UnitLevel, IsSpellKnown, IsPlayerSpell = keep.UnitLevel, keep.known, keep.player
GetNumTrainerServices, GetTrainerServiceInfo = keep.num, keep.info
if C_TooltipInfo then C_TooltipInfo.GetTrainerService = keep.tip end
SP.db.global.trainerSeen = nil
finish()
