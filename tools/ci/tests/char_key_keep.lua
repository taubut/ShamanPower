-- client: both
-- ShamanPower keeps each character under its own key whatever AceDB copy loads: "Name - Realm" (AceDB-3.0
-- 33's key) on other clients, the full name "First Surname" on WoW: Forever (3.0.9.6; char_key_fullname has
-- the carry from the old key). AceDB-3.0 39 keyed Forever characters by first name alone ("Name"): left
-- alone, the first login with it put the character on Default and lost its own data. KeepCharKey moves it
-- to ours with the profile it had; FixPlayerIdentity's cleanup keeps other characters' keys and drops only
-- "Unknown" ones.
local SP = ShamanPower
local db = SP.db
local keys, sv = rawget(db, "keys"), rawget(db, "sv")
local ours = UnitName("player") .. " - " .. GetRealmName()
if SPCompat.FOREVER and RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
	local name, surname = UnitNameUnmodified("player")
	ours = name .. " " .. surname
end
checkEq("the character is on our key after login", keys.char, ours)
checkEq("its profile is kept under our key", sv.profileKeys[ours], db:GetCurrentProfile())
if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
	checkEq("AceDB 39's own key holds no profile pick", sv.profileKeys[UnitName("player")], nil)
end
-- a pick after login lands under our key, never AceDB's
db:SetProfile("SPCI Picked")
__sim.advance(0.1)
checkEq("a new pick is saved under our key", sv.profileKeys[ours], "SPCI Picked")
-- a login where AceDB keyed the character its own way, with its own data there
local aceKey = UnitName("player")
db:SetProfile("Default")
sv.profileKeys[ours] = "SPCI Picked"
sv.profileKeys[aceKey] = "Default"
sv.char = sv.char or {}
local mine = sv.char[ours]
sv.char[ours] = nil
sv.char[aceKey] = { spciMarker = 7 }
keys.char = aceKey
rawset(db, "char", nil)
checkEq("KeepCharKey reports the move", SP:KeepCharKey(true), "moved")
checkEq("back on our key", keys.char, ours)
checkEq("on the profile it had under our key", db:GetCurrentProfile(), "SPCI Picked")
checkEq("its data came along", db.char.spciMarker, 7)
checkEq("AceDB's key is cleared", sv.profileKeys[aceKey], nil)
checkEq("AceDB's char data is cleared", sv.char[aceKey], nil)
-- a cold login (the game said "Unknown"): moved once the name is known, profile switched next frame
db:SetProfile("Default")
sv.profileKeys[ours] = "SPCI Picked"
keys.char = "Unknown"
sv.char.Unknown = { mixed = true }
rawset(db, "char", nil)
checkEq("KeepCharKey moves an Unknown key", SP:KeepCharKey(), "moved")
__sim.advance(0.1)
checkEq("the cold login's profile is put right", db:GetCurrentProfile(), "SPCI Picked")
checkEq("the Unknown data is dropped, never moved", sv.char.Unknown, nil)
-- the cleanup keeps other characters in either key format and drops Unknown ones
sv.profileKeys["Little Simpin"] = "Other"
sv.char["Little Simpin"] = { spciMarker = 1 }
sv.profileKeys["Simpin - Dreamscythe"] = "Other"
sv.profileKeys["Unknown - Dreamscythe"] = "Default"
SP:FixPlayerIdentity()
checkEq("another character's region-wide key stays", sv.profileKeys["Little Simpin"], "Other")
check("another character's region-wide data stays", sv.char["Little Simpin"] ~= nil)
checkEq("another character's Name - Realm key stays", sv.profileKeys["Simpin - Dreamscythe"], "Other")
checkEq("an Unknown key goes", sv.profileKeys["Unknown - Dreamscythe"], nil)
-- tidy: back on Default, the test rows gone
db:SetProfile("Default")
sv.profileKeys["Little Simpin"], sv.char["Little Simpin"], sv.profileKeys["Simpin - Dreamscythe"] = nil, nil, nil
sv.char[ours] = mine
rawset(db, "char", nil)
db:DeleteProfile("SPCI Picked", true)
finish()
