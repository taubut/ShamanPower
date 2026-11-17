-- client: both
-- (3.0.9.16) The owner, 11-16: imported a friend's code (a new profile), set it for Enhancement, switched back to
-- their own profile, and kept the friend's Ready Reminders, placements and all. Only the profile itself switched;
-- every module's own table, the themes and the Call picks stayed. Now a profile is the whole setup: switching puts
-- the one you leave away with its profile and brings the new one's back. Ready Reminders (with where the grid
-- sits on screen), Reactive Totems, the other module tables, your themes and the Call picks, through an import,
-- switching both ways, edits on each, a new profile, Copy From and logging out.
local SP = ShamanPower
local W = __sim.W
local db = SP.db
if not (db and SP.ImportShare) then skip("no profiles here") end
local start = db:GetCurrentProfile()
local RR, RT = "ShamanPower_ReadyReminders", "ShamanPower_ReactiveTotems"
_G[RR] = _G[RR] or {}
_G[RT] = _G[RT] or {}
local keepSetups = db.global.profileSetups
local keepThemes, keepKept = db.global.themes, db.char.callKept
local keepRR = {}
for k, v in pairs(_G[RR]) do keepRR[k] = v end

-- one whole setup, named by `who`
local function setUp(who, x)
	_G[RR].spTestWho = who
	_G[RR].arrange = "grid"
	_G[RR].gridPos = { point = "BOTTOMLEFT", x = x, y = 300 }
	_G[RT].spTestWho = who
	db.global.themes = { { id = 9000 + x, name = who .. "'s theme", base = "standard", flat = {} } }
	db.char.callKept = { [2] = { [1] = x } }
	if SP.UpdateAllReadyReminderAppearance then SP:UpdateAllReadyReminderAppearance() end
end
-- what is on screen now, in one line (the grid's real spot; every theme's name)
local function onScreen()
	local g = _G.ShamanPowerReadyGrid
	local gx = g and select(4, g:GetPoint(1))
	local names = {}
	for _, th in ipairs(db.global.themes or {}) do names[#names + 1] = tostring(th.name) end
	return ("RR=%s RT=%s themes=%s callKept=%s gridX=%s"):format(tostring(_G[RR].spTestWho), tostring(_G[RT].spTestWho),
		table.concat(names, "+"), tostring(db.char.callKept and db.char.callKept[2] and db.char.callKept[2][1]),
		tostring(gx and math.floor(gx + 0.5)))
end

SP:SetReadyRemindersEnabled(true)
SP:ReadyReminderSetSpell("earthshock", true)
setUp("mine", 100)
__sim.advance(0.2)
setUp("mine", 100)   -- (the grid settles its spot the first time it is placed: read it after that)
__sim.advance(0.2)
local mine = onScreen()
check("my setup on screen", mine:find("RR=mine RT=mine themes=mine's theme callKept=100", 1, true) ~= nil, mine)

-- a friend's code (their whole setup), made and imported as a new profile, the way the owner did
setUp("miska", 500)
__sim.advance(0.2)
local miskaGrid = onScreen():match("gridX=(%-?%d+)")
local code = SP:ExportCurrentProfile()
setUp("mine", 100)
__sim.advance(0.2)
checkEq("mine again before the import", onScreen(), mine)
local ok, miska = SP:ImportShare(code, "newProfile", "Miska")
__sim.advance(0.2)
check("the import made its profile", ok and db:GetCurrentProfile() == miska, tostring(miska))
db.char.callKept = { [2] = { [1] = 500 } }   -- (a code carries no Call picks: set on Miska's profile)
local theirs = onScreen()
check("the import: Miska's Ready Reminders, Reactive Totems, grid spot and themes", theirs:find("RR=miska RT=miska", 1, true)
	and theirs:find("miska's theme", 1, true) and theirs:find("gridX=" .. tostring(miskaGrid), 1, true) and true or false, theirs)

-- back to my own profile: ALL of mine again (the report: Miska's Ready Reminders stayed)
db:SetProfile(start)
__sim.advance(0.2)
checkEq("back on my profile: my whole setup", onScreen(), mine)
db:SetProfile(miska)
__sim.advance(0.2)
checkEq("on Miska's again: Miska's whole setup", onScreen(), theirs)

-- an edit stays with its profile
_G[RR].spTestWho = "miska edited"
db:SetProfile(start)
checkEq("my profile untouched by Miska's edit", _G[RR].spTestWho, "mine")
db:SetProfile(miska)
checkEq("Miska's edit kept on Miska's profile", _G[RR].spTestWho, "miska edited")
_G[RR].spTestWho = "miska"

-- a new profile starts from what is on screen; then it is its own
db:SetProfile("Fresh Test")
__sim.advance(0.2)
checkEq("a new profile: what was on screen", onScreen(), theirs)
setUp("fresh", 700)
__sim.advance(0.2)
local fresh = onScreen()
db:SetProfile(start)
__sim.advance(0.2)
checkEq("mine again after the new one", onScreen(), mine)
db:SetProfile("Fresh Test")
__sim.advance(0.2)
checkEq("the new one kept its own", onScreen(), fresh)

-- Copy From: that profile's whole setup into this one
db:CopyProfile(miska)
__sim.advance(0.2)
checkEq("Copy From Miska: Miska's whole setup here", onScreen(), theirs)
db:SetProfile(start)
db:SetProfile("Fresh Test")
__sim.advance(0.2)
checkEq("and it stays after switching away and back", onScreen(), theirs)

-- logging out keeps what is on screen with its profile
setUp("fresh at logout", 900)
-- (what PLAYER_LOGOUT runs; firing the real event here would also strip the database's defaults mid-session)
check("logging out keeps the setup with its profile", SP.KeepProfileSetup ~= nil)
if SP.KeepProfileSetup then SP:KeepProfileSetup() end
db:SetProfile(start)
db:SetProfile("Fresh Test")
checkEq("logging out keeps it with its profile", _G[RR].spTestWho, "fresh at logout")

-- put everything back
db:SetProfile(start)
for _, name in ipairs({ "Fresh Test", miska }) do pcall(db.DeleteProfile, db, name, true) end
for k in pairs(_G[RR]) do _G[RR][k] = nil end
for k, v in pairs(keepRR) do _G[RR][k] = v end
_G[RT].spTestWho = nil
db.global.profileSetups, db.global.themes, db.char.callKept = keepSetups, keepThemes, keepKept
SP:ReadyReminderSetSpell("earthshock", false)
if SP.UpdateAllReadyReminderAppearance then SP:UpdateAllReadyReminderAppearance() end
finish()
