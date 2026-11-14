-- client: both
-- (3.0.9.13) The Support Code's z part: everything ShamanPower can tell about itself (the owner, 11-12: "everything").
-- It builds and decodes, every part is there and none failed, ShamanPower's own read-only probes are in it
-- without a copy window opening or anything printed, and no name of the player's is in it anywhere.
local SP = ShamanPower
local LS, LD = LibStub("LibSerialize", true), LibStub("LibDeflate", true)
if not (LS and LD) then skip("LibSerialize / LibDeflate not loaded") end

local function decodeSupport(code)
	local body = code and code:match("^SPH1:(.+)$")
	if not body then return nil end
	local raw = LD:DecompressDeflate(LD:DecodeForPrint(body))
	local ok, payload = LS:Deserialize(raw)
	return ok and payload or nil
end

local printed = 0
local print0 = SP.Print
local addMessage = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage
if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME.AddMessage = function(...) printed = printed + 1 return addMessage(...) end end
local okBuild, code = pcall(SP.BuildSupportCode, SP)
if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME.AddMessage = addMessage end

check("the Support Code builds", okBuild and type(code) == "string", tostring(code))
local p = decodeSupport(okBuild and code or nil)
check("and decodes", type(p) == "table")
local z = p and p.z or {}
check("the z part is there", next(z) ~= nil)
check("no part of it failed", z.fail == nil, z.fail and table.concat(z.fail, " | ") or "")
for _, part in ipairs({ "spells", "talents", "auras", "weapons", "buttons", "frames", "state", "sounds", "probes" }) do
	check("z." .. part, z[part] ~= nil)
end
check("every frame counted", type(z.framesN) == "number" and z.framesN > 0, tostring(z.framesN))
check("the totem bar's first button is in the frame list", z.frames and z.frames.ShamanPowerTotemBtn1 ~= nil)
check("the spells: Maelstrom Weapon's talent spell is asked about", z.spells and z.spells.kn and z.spells.kn[408498] ~= nil)
check("each element's totems, learned or not", z.spells and z.spells.tx and type(z.spells.tx[1]) == "string")
check("the totem bar's buttons", z.buttons and z.buttons.tb and z.buttons.tb[1] ~= nil)
if SP.ReadyRemindersDiag then
	check("the Ready Reminders probe is in it", z.probes and z.probes.ready and #z.probes.ready > 1)
end
if SP.ReactiveEngineReport then
	check("the Reactive Totems report is in it", z.probes and z.probes.reactive and #z.probes.reactive > 0)
end
check("ShamanPower's Print is put back", SP.Print == print0)
check("no copy window opened", not (ShamanPowerCopyWindow and ShamanPowerCopyWindow:IsShown()))
checkEq("nothing printed in the chat", printed, 0)
check("the capture switch is off again", SPCompat.copyCapture == nil)

-- nothing personal: the player's name and realm nowhere in it
local me, realm = UnitName("player"), GetRealmName and GetRealmName()
local found
local function scan(v, path)
	if found then return end
	if type(v) == "string" then
		if (me and #me > 2 and v:find(me, 1, true)) or (realm and #realm > 2 and v:find(realm, 1, true)) then found = path end
	elseif type(v) == "table" then
		for k, x in pairs(v) do scan(k, path .. "[key]"); scan(x, path .. "." .. tostring(k)) end
	end
end
scan(p or {}, "code")
check("no name or realm anywhere in it", found == nil, tostring(found))
check("it stays a size a Discord message file takes", #code < 120000, tostring(#code))
finish()
