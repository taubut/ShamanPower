-- client: both
-- (3.0.9.9) Racials in Ready Reminders: off until clicked, each one only for its own race (another
-- race never sees it, not even dark on the page), and the client-only ones only on their client.
-- Every spell's default spot is as in 3.0.9.8; your racials get a short row under the spells'.
-- The sim's spell data has no racials, so they are added here as the game has them.
local SP = ShamanPower
local A, W = __sim.A, __sim.W
local FOREVER = SPCompat.FOREVER
local list = SP.ReadyReminderSpells
local byKey = {}
for _, e in ipairs(list) do byKey[e.key] = e end
SP:SetReadyRemindersEnabled(true)   -- (off by default on Anniversary)
local RACIALS = { "bloodfury", "shattercurse", "stoneform", "warstomp", "berserking", "rapidregen", "naaru", "skysight", "walkonair" }

-- the catalog: all nine, off by default, after every spell that was there before
local firstRacial
for i, e in ipairs(list) do if e.races and not firstRacial then firstRacial = i end end
check("the racials come after Combined Shocks", firstRacial and list[firstRacial - 1].key == "shocks")
for _, k in ipairs(RACIALS) do
	local e = byKey[k]
	check(k .. " in the list, off until clicked, with its race", e and e.def == false and type(e.races) == "table")
end

-- the spells as each game has them (name, icon), every one known
local DATA = FOREVER and {
	[20572] = { "Blood Fury", 135726 }, [1299026] = { "Shatter Curse", 136082 }, [20594] = { "Stoneform", 136225 },
	[20549] = { "War Stomp", 132368 }, [20554] = { "Berserking", 135727 }, [1260270] = { "Rapid Regeneration", 1850550 },
	[1259686] = { "Skysight", 1029587 }, [1259416] = { "Walk on Air", 132845 },
} or {
	[33697] = { "Blood Fury", 135726 }, [20572] = { "Blood Fury", 135726 }, [20549] = { "War Stomp", 132368 },
	[20554] = { "Berserking", 135727 }, [28880] = { "Gift of the Naaru", 135923 },
}
for id, d in pairs(DATA) do
	A.spells[id] = { name = d[1], sub = "", icon = d[2], level = 1 }
	A.known[id] = true
end
-- Anniversary: 20572 is the warrior's and rogue's Blood Fury, never a shaman's
if not FOREVER then A.known[20572] = nil end
A.byName["blood fury"] = FOREVER and 20572 or 33697
for id, d in pairs(DATA) do if id ~= 20572 or FOREVER then A.byName[d[1]:lower()] = id end end

local realRace = UnitRace
local function playAs(raceID)
	UnitRace = function(u) if u == "player" then return "Race", "Race", raceID end return realRace(u) end
	SP.readyRaceID = nil
	W.fireEvent("SPELLS_CHANGED")
	SP:UpdateReadyReminders(); __sim.advance(0.2)
end
local function usableSet()
	local out = {}
	for _, k in ipairs(RACIALS) do if SP.ReadyReminderUsable(byKey[k]) then out[#out + 1] = k end end
	return table.concat(out, ",")
end

-- each race sees only its own, on its own client
local WANT = FOREVER and {
	[2] = "bloodfury,shattercurse", [3] = "stoneform", [6] = "warstomp", [8] = "berserking,rapidregen",
	[96] = "skysight,walkonair", [11] = "",
} or {
	[2] = "bloodfury", [3] = "", [6] = "warstomp", [8] = "berserking", [96] = "", [11] = "naaru",
}
for _, race in ipairs({ 2, 3, 6, 8, 11, 96 }) do
	playAs(race)
	checkEq("race " .. race .. ": its racials on the page", usableSet(), WANT[race])
end
playAs(2)
SP.ReadyReminderUsable(byKey.bloodfury)
checkEq("Blood Fury: this game's own spell", byKey.bloodfury.clientID, FOREVER and 20572 or 33697)
check("Blood Fury: learned", SP.ReadyReminderKnown(byKey.bloodfury))

-- off until clicked: no icon yet; clicked on, it shows (ready, no cooldown)
local frames = SP.readyReminderFrames
check("before a click: no Blood Fury icon", not (frames.bloodfury and frames.bloodfury:IsShown()))
SP:ReadyReminderSetSpell("bloodfury", true)
if FOREVER then SP:ReadyReminderSetSpell("shattercurse", true) end
SP:UpdateReadyReminders(); __sim.advance(0.2)
local bf = frames.bloodfury
check("clicked on: the Blood Fury icon shows", bf and bf:IsShown())

-- default spots (Free placement, nothing moved): Earth Shock where 3.0.9.8 put it, the racials
-- in a short centered row under the spells'
local function spot(f)
	local _, _, _, x, y = f:GetPoint()
	return string.format("%d,%d", math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5))
end
local es = frames.earthshock
if es and es:IsShown() and SP:ReadyReminderPageOpt("layout") ~= "column" and (SP:ReadyReminderPageOpt("arrange") or "free") == "free" then
	checkEq("Earth Shock's default spot as in 3.0.9.8", spot(es), "-588,-140")
end
if bf then checkEq("Blood Fury's default spot: under the spells", spot(bf), FOREVER and "-28,-196" or "0,-196") end
if FOREVER and frames.shattercurse then checkEq("Shatter Curse beside it", spot(frames.shattercurse), "28,-196") end

-- another race: the icon goes, even switched on
playAs(8)
check("a Troll: no Blood Fury icon, even switched on", not (bf and bf:IsShown()))

-- your race, not learned yet: on the page (dark), no icon
playAs(6)
A.known[20549] = nil
W.fireEvent("SPELLS_CHANGED"); SP:UpdateReadyReminders(); __sim.advance(0.2)
check("not learned yet: War Stomp still on the page", SP.ReadyReminderUsable(byKey.warstomp))
check("not learned yet: it reads unlearned", not SP.ReadyReminderKnown(byKey.warstomp))

-- put back
UnitRace = realRace
SP.readyRaceID = nil
SP:ReadyReminderSetSpell("bloodfury", false)
SP:ReadyReminderSetSpell("shattercurse", false)
for id in pairs(DATA) do A.spells[id] = nil; A.known[id] = nil end
W.fireEvent("SPELLS_CHANGED")
finish()
