-- client: forever
-- WoW: Forever files each character under its full name, "First Surname" (3.0.9.6), as AceDB-3.0 40 and the
-- game do. Before, every character went under "First - Realm", so shamans with the same first name shared
-- one profile pick (the owner's test 11-05: a new Sru Testing came up on Sru Shamanpower's profile, and
-- switching one switched both). Once per character the old entry is carried over, the profile it was on and
-- its data, so nothing changes on update day; the old entry stays for the characters that still read it.
local SP = ShamanPower
local db = SP.db
local keys, sv = rawget(db, "keys"), rawget(db, "sv")
local P = __sim.A.player
if not (RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled()) then skip("no regional names here") end
local pk = sv.profileKeys
local realmKey = UnitName("player") .. " - " .. GetRealmName()
local keepSurname = P.surname
local full = P.name .. " " .. (P.surname or "Bagels")
checkEq("after login the character is on its full name", keys.char, full)
check("its carry is marked done (in its own data)", sv.char and sv.char[full] and sv.char[full].charKeyCarried == true)
local startProfile = db:GetCurrentProfile()
local keepChar = sv.char and sv.char[full]
sv.char = sv.char or {}

-- a login as AceDB opens it: on the character's own key, on the profile that key holds (no callbacks)
local function open(key, profile)
	keys.char = key
	pk[key] = profile
	rawset(db, "profile", nil)
	keys.profile = profile
	rawset(db, "char", nil)
end

-- update day: the pick and the data are under the old "First - Realm" entry, never carried
pk[realmKey] = "SPCI Shared"
sv.char[realmKey] = { spciMarker = 5, totemDurations = { [5394] = 60 } }
sv.char[full] = nil
open(full, "Default")
checkEq("update day: the carry happens", SP:KeepCharKey(true), "moved")
checkEq("on the profile the old entry had", db:GetCurrentProfile(), "SPCI Shared")
checkEq("the pick is the full name's now", pk[full], "SPCI Shared")
checkEq("its data came along", db.char.spciMarker, 5)
checkEq("its learned totem lengths too", db.char.totemDurations and db.char.totemDurations[5394], 60)
check("copied, not shared with the old entry", db.char.totemDurations ~= sv.char[realmKey].totemDurations)
checkEq("the old entry's pick stays (others may still read it)", pk[realmKey], "SPCI Shared")
check("the old entry's data stays", sv.char[realmKey] ~= nil and sv.char[realmKey].spciMarker == 5)
check("marked done", db.char.charKeyCarried == true)

-- a pick after that is this character's alone
db:SetProfile("SPCI Own")
checkEq("a new pick is saved under the full name", pk[full], "SPCI Own")
checkEq("the old entry keeps its pick (another character's)", pk[realmKey], "SPCI Shared")

-- the next login: done once, never again (the old entry never pulls it back)
open(full, "SPCI Own")
checkEq("next login: nothing to carry", SP:KeepCharKey(true), true)
checkEq("next login: still its own pick", db:GetCurrentProfile(), "SPCI Own")

-- back to a version before 3.0.9.6 (it files the character under "First - Realm" again and clears the
-- full name's entries), then updated again: carried once more, never Default
pk[realmKey] = "SPCI Own"
sv.char[full], pk[full] = nil, nil
open(full, "Default")
checkEq("updated again: carried once more", SP:KeepCharKey(true), "moved")
checkEq("updated again: on what it was on", db:GetCurrentProfile(), "SPCI Own")
pk[realmKey] = "SPCI Shared"

-- a second shaman with the same first name, its first login after the update: the old shared pick
-- (what it was on until now), then a key of its own
P.surname = "Testing"
local second = P.name .. " Testing"
open(second, "Default")
checkEq("same first name: carried too", SP:KeepCharKey(true), "moved")
checkEq("same first name: on what it had", db:GetCurrentProfile(), "SPCI Shared")
checkEq("same first name: its own key", keys.char, second)
checkEq("same first name: its own pick", pk[second], "SPCI Shared")
check("same first name: its own copy of the data", sv.char[second] ~= nil and sv.char[second] ~= sv.char[full] and sv.char[second].spciMarker == 5)
pk[full] = "SPCI Own"   -- (the sim's AceDB writes every pick under its one key, Srumar Bagels)
pk[second] = "SPCI Second"
checkEq("one character's pick leaves the other's alone", pk[full], "SPCI Own")

-- a brand-new character with nothing under the old entry: Default, as for any new character
P.surname = "Newbie"
local newbie = P.name .. " Newbie"
local savedPick, savedData = pk[realmKey], sv.char[realmKey]
pk[realmKey], sv.char[realmKey] = nil, nil
open(newbie, "Default")
SP:KeepCharKey(true)
checkEq("nothing under the old entry: Default", db:GetCurrentProfile(), "Default")
check("nothing under the old entry: marked done", sv.char[newbie] ~= nil and sv.char[newbie].charKeyCarried == true)
pk[realmKey], sv.char[realmKey] = savedPick, savedData

-- the realm not readable yet: nothing done, nothing marked; done once it is
P.surname = "Later"
local later = P.name .. " Later"
open(later, "Default")
local realGRN = GetRealmName
GetRealmName = function() return "" end
checkEq("no realm yet: waits", SP:KeepCharKey(true), false)
check("no realm yet: not marked", sv.char[later] == nil)
checkEq("no realm yet: nothing filed under \"Name - \"", pk[P.name .. " - "], nil)
GetRealmName = realGRN
checkEq("realm known: carried", SP:KeepCharKey(true), "moved")
checkEq("realm known: on what it had", db:GetCurrentProfile(), "SPCI Shared")

-- a cold login (AceDB opened under "Unknown ..."): moved to the full name with the character's own pick
P.surname = "Testing"
db:SetProfile("Default")
open("Unknown Testing", "Default")
sv.char["Unknown Testing"] = { mixed = true }
checkEq("cold login: moved", SP:KeepCharKey(), "moved")
__sim.advance(0.1)
checkEq("cold login: its own key", keys.char, second)
checkEq("cold login: its own pick", db:GetCurrentProfile(), "SPCI Second")
checkEq("cold login: the Unknown data is dropped", sv.char["Unknown Testing"], nil)
pk[full] = "SPCI Own"   -- (again: the sim's AceDB wrote the switch under Srumar Bagels)
pk["Unknown Bagels"] = "Default"
SP:FixPlayerIdentity()
checkEq("an Unknown full-name key goes", pk["Unknown Bagels"], nil)
checkEq("the old entry stays", pk[realmKey], "SPCI Shared")
checkEq("the other character's key stays", pk[full], "SPCI Own")

-- AceDB keyed it "First - Realm" itself: moved to the full name, the old entry put back after each pick
open(realmKey, "SPCI Shared")
SP:KeepCharKey(true)
checkEq("keyed the old way: moved to the full name", keys.char, second)
checkEq("keyed the old way: the old entry kept", pk[realmKey], "SPCI Shared")
pk[realmKey] = "SPCI Elsewhere"   -- (what AceDB writes under its own key on a pick)
SP:SyncCharProfileKey()
checkEq("after a pick: the old entry put back", pk[realmKey], "SPCI Shared")
SP.aceCharKeyFix = nil

-- tidy
P.surname = keepSurname
for _, k in ipairs({ second, newbie, later, realmKey, "Unknown Testing" }) do pk[k], sv.char[k] = nil, nil end
open(full, startProfile)
sv.char[full] = keepChar
rawset(db, "char", nil)
db:SetProfile("Default")
for _, n in ipairs({ "SPCI Shared", "SPCI Own", "SPCI Second", "SPCI Elsewhere" }) do pcall(db.DeleteProfile, db, n, true) end
db:SetProfile(startProfile)
finish()
