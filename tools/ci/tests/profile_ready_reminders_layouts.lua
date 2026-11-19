-- client: both
-- (3.0.9.17) A report after 3.0.9.16: Ready Reminders still don't keep a layout per profile. The owner, 11-17: one
-- whole set of reminders laid out one way on one profile, the same reminders laid out another way on another, and
-- Profile by Spec switching between them. Checked on screen, against the spots set, not in the saved table: which
-- icons show, where each one sits (its own spot, or its row and that row's spot), its size, the rows and the order,
-- both ways and again; and logging in on a profile.
local SP = ShamanPower
local W = __sim.W
local db = SP.db
if not (db and SP.SetSpecProfile and SP.ReadyRowPlace and SP.readyReminderFrames) then skip("no profiles or Ready Reminders here") end
local RR = "ShamanPower_ReadyReminders"
local was = db:GetCurrentProfile()
local keepRR = {}
for k, v in pairs(_G[RR]) do keepRR[k] = v end
local keepSetups = db.global.profileSetups
local keepIdx = SP.ShareSpecIndex
local spec = 2
SP.ShareSpecIndex = function() return spec end
local function respec(n) spec = n; W.fireEvent("SPELLS_CHANGED"); __sim.advance(1.3); __sim.advance(0.3) end
local function sv() return _G[RR] end
local frames = SP.readyReminderFrames
local UW, UH = UIParent:GetWidth(), UIParent:GetHeight()

-- three reminders the sim shows
SP:SetReadyRemindersEnabled(true)
for _, e in ipairs(SP.ReadyReminderSpells) do
	if not (e.stacks or e.proc or e.imbue or e.weaponSet or e.combo) then SP:ReadyReminderSetSpell(e.key, true) end
end
SP:UpdateReadyReminders(); __sim.advance(0.3)
local keys = {}
for _, e in ipairs(SP.ReadyReminderSpells) do
	local f = frames[e.key]
	if f and f:IsShown() and f:GetLeft() and #keys < 3 then keys[#keys + 1] = e.key end
end
for _, e in ipairs(SP.ReadyReminderSpells) do SP:ReadyReminderSetSpell(e.key, false) end
if #keys < 3 then skip("fewer than 3 reminders show in the sim: " .. #keys) end
local A, B, C = keys[1], keys[2], keys[3]

local function settle() SP:UpdateReadyReminders(); __sim.advance(0.3); SP:UpdateReadyReminders() end
local function r(v) return v and math.floor(v + 0.5) end
-- a reminder on screen: "off", or its left,top and size
local function at(k)
	local f = frames[k]
	if not (f and f:IsShown()) then return "off" end
	return ("%s,%s/%s"):format(tostring(r(f:GetLeft())), tostring(r(f:GetTop())), tostring(r(f:GetWidth())))
end
-- a reminder's spot from its center, as Free saves it (CENTER of the screen + x, y)
local function free(x, y, size) return ("%d,%d/%d"):format(r(UW / 2 + x - size / 2), r(UH / 2 + y + size / 2), size) end
local function all() settle(); return ("%s=%s %s=%s %s=%s"):format(A, at(A), B, at(B), C, at(C)) end
-- the reminders left to right (the grid's order)
local function order()
	settle()
	local list = {}
	for _, k in ipairs(keys) do if frames[k]:IsShown() then list[#list + 1] = k end end
	table.sort(list, function(p, q) return frames[p]:GetLeft() < frames[q]:GetLeft() end)
	return table.concat(list, ",")
end

for _, n in ipairs({ "RRL Enh", "RRL Resto" }) do db:SetProfile(n) end
respec(2)
SP:SetSpecProfile("enhancement", "RRL Enh")
SP:SetSpecProfile("restoration", "RRL Resto")
respec(2)
checkEq("Enhancement's profile in use", db:GetCurrentProfile(), "RRL Enh")

-- Enhancement: Free placement, A and B on, each on its own spot, A at 40
sv().arrange = "free"
SP:ReadyReminderSetSpell(A, true); SP:ReadyReminderSetSpell(B, true); SP:ReadyReminderSetSpell(C, false)
sv().positions = sv().positions or {}
sv().positions[A] = { point = "CENTER", x = -300, y = 100 }
sv().positions[B] = { point = "CENTER", x = 250, y = -150 }
SP:ReadyReminderSetIconOpt(A, "iconSize", 40)
SP:UpdateAllReadyReminderAppearance()
local enh = ("%s=%s %s=%s %s=off"):format(A, free(-300, 100, 40), B, free(250, -150, 48), C)
checkEq("Enhancement's layout set", all(), enh)

-- Restoration: all three, on two rows (C then A on row 1, B on row 2), each row on its own spot, A at 60
respec(1)
checkEq("Restoration's profile in use", db:GetCurrentProfile(), "RRL Resto")
SP:ReadyReminderSetSpell(A, true); SP:ReadyReminderSetSpell(B, true); SP:ReadyReminderSetSpell(C, true)
SP:ReadyReminderSetIconOpt(A, "iconSize", 60)
sv().arrange = "rows"
sv().rows = nil
SP:ReadyRowPlace(C, 1); SP:ReadyRowPlace(A, 1)
SP:ReadyRowAdd(); SP:ReadyRowPlace(B, 2)
SP:ReadyRowSet(1, "spacing", 8)
SP:ReadyRowSet(1, "pos", { point = "TOPLEFT", x = 100, y = -100 })
SP:ReadyRowSet(2, "pos", { point = "TOPLEFT", x = 600, y = -500 })
SP:UpdateAllReadyReminderAppearance()
local resto = ("%s=%d,%d/60 %s=%d,%d/48 %s=%d,%d/48"):format(A, 156, r(UH - 100), B, 600, r(UH - 500), C, 100, r(UH - 100))
checkEq("Restoration's layout set", all(), resto)

-- switching by spec: each profile's whole layout, as it was left
respec(2)
checkEq("back to Enhancement: its layout", all(), enh)
respec(1)
checkEq("back to Restoration: its layout", all(), resto)
respec(2)
checkEq("Enhancement again", all(), enh)

-- a row's spot changed on Restoration stays Restoration's
respec(1)
SP:ReadyRowSet(1, "pos", { point = "TOPLEFT", x = 150, y = -120 })
SP:UpdateAllReadyReminderAppearance()
resto = ("%s=%d,%d/60 %s=%d,%d/48 %s=%d,%d/48"):format(A, 206, r(UH - 120), B, 600, r(UH - 500), C, 150, r(UH - 120))
checkEq("Restoration's row moved", all(), resto)
respec(2)
checkEq("Enhancement untouched by Restoration's edit", all(), enh)
respec(1)
checkEq("Restoration kept its edit", all(), resto)

-- the order on the page: each profile's own (the grid fills in it)
sv().arrange = "grid"
SP:ReadyOrderMove(C, nil); SP:ReadyOrderMove(A, nil); SP:ReadyOrderMove(B, nil)   -- C, A, B
checkEq("Restoration's grid in its order", order(), C .. "," .. A .. "," .. B)
respec(2)
sv().arrange = "grid"
SP:ReadyReminderSetSpell(C, true)
SP:ReadyOrderMove(B, nil); SP:ReadyOrderMove(C, nil); SP:ReadyOrderMove(A, nil)   -- B, C, A
checkEq("Enhancement's grid in its order", order(), B .. "," .. C .. "," .. A)
respec(1)
checkEq("back to Restoration: its grid order", order(), C .. "," .. A .. "," .. B)
respec(2)
checkEq("back to Enhancement: its grid order", order(), B .. "," .. C .. "," .. A)

-- logging in: the profile in use brings its own whole setup, whatever the saved table held (Anniversary keeps Ready
-- Reminders for the whole account: another character's last layout loads with it)
SP:KeepProfileSetup()   -- (logging out on Enhancement)
local other = {}
for k, v in pairs(sv()) do other[k] = v end
other.arrange, other.order = "grid", { A, B, C }
wipe(sv()); for k, v in pairs(other) do sv()[k] = v end   -- (another character's, loaded with the account)
check("a login brings the profile's own setup", SP.ProfileSetupLogin ~= nil)
if SP.ProfileSetupLogin then
	SP:ProfileSetupLogin()
	checkEq("logged in on Enhancement's profile: its grid order", order(), B .. "," .. C .. "," .. A)
end

-- put back
SP.ShareSpecIndex = keepIdx
db.char.specProfiles, db.char.specProfileLast = nil, nil
db:SetProfile(was)
for _, n in ipairs({ "RRL Enh", "RRL Resto" }) do pcall(db.DeleteProfile, db, n, true) end
wipe(_G[RR]); for k, v in pairs(keepRR) do _G[RR][k] = v end
db.global.profileSetups = keepSetups
SP:UpdateAllReadyReminderAppearance()
finish()
