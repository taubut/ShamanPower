-- client: both
-- The Support Code (/sp support) and the setup code it carries, for 3.0.9.1's additions:
-- the keys Keybinds Still Work took over (x.ko), the cooldown number color scale (n.cc, only
-- where the game has duration text), and the setup code's new feature bits (146 now: 3 more in 3.0.9.5).
local SP = ShamanPower
local o = SP.opt
local LS, LD = LibStub("LibSerialize", true), LibStub("LibDeflate", true)
if not (LS and LD) then skip("LibSerialize / LibDeflate not loaded") end

local function decodeSupport(code)
	local body = code and code:match("^SPH1:(.+)$")
	if not body then return nil end
	local raw = LD:DecompressDeflate(LD:DecodeForPrint(body))
	local ok, payload = LS:Deserialize(raw)
	return ok and payload or nil
end

-- three bound keys: two taken over by a stand-in, one casting from its own button
local bindings = {
	{ "SHAMANPOWER_CD_SHIELD", "SHIFT-8", "CLICK ShamanPowerKeyOnlyCD1:LeftButton" },
	{ "CLICK ShamanPowerFlyout1Btn2:LeftButton", "CTRL-1", "CLICK ShamanPowerKeyNone:LeftButton" },
	{ "SHAMANPOWER_FIRE_TOTEM", "SHIFT-3", "CLICK ShamanPowerTotemBtn2:LeftButton" },
}
local realNum, realGet, realAction = GetNumBindings, GetBinding, GetBindingAction
GetNumBindings = function() return #bindings end
GetBinding = function(i) local b = bindings[i]; return b[1], "ShamanPower", b[2] end
GetBindingAction = function(key, override)
	for _, b in ipairs(bindings) do if b[2] == key then return override and b[3] or b[1] end end
	return ""
end
local okBuild, code = pcall(SP.BuildSupportCode, SP)
GetNumBindings, GetBinding, GetBindingAction = realNum, realGet, realAction

check("the Support Code builds", okBuild and type(code) == "string", tostring(code))
local p = decodeSupport(okBuild and code or nil)
check("the Support Code decodes", type(p) == "table")
local x, n = p and p.x or {}, p and p.n or {}
checkEq("ko: the shield key's stand-in", x.ko and x.ko.SHAMANPOWER_CD_SHIELD, "ShamanPowerKeyOnlyCD1")
checkEq("ko: the hidden flyout totem's key does nothing", x.ko and x.ko["CLICK ShamanPowerFlyout1Btn2:LeftButton"], "ShamanPowerKeyNone")
check("ko: a key casting from its own button is not listed", not (x.ko and x.ko.SHAMANPOWER_FIRE_TOTEM))
checkEq("kb still lists ShamanPower's own bindings", x.kb and x.kb.SHAMANPOWER_FIRE_TOTEM, "SHIFT-3")

-- the color scale: only where the game draws duration text (the sim has none: no reading, no error)
local D = C_DurationUtil
if D and D.CreateDurationTextBinding then
	check("cc: the scale is 100 or 1", n.cc and (n.cc.s == 100 or n.cc.s == 1), tostring(n.cc and n.cc.s))
else
	check("cc: no duration text, no reading", n.cc == nil and SP:CountdownScale() == nil)
end

-- the setup code: the new features' bits
local saved = {}
local function set(k, v) if saved[k] == nil then saved[k] = { v = o[k] } end; o[k] = v end
set("iconScreens", true); set("keybindsWorkWhenOff", true); set("loadoutsRememberOrder", true)
set("raidCoverage", { enabled = true }); set(SP.COUNTDOWN_SWITCHES.cdbar, true)
set("totemBarClickThrough", "combat"); set("dropAllResetSeconds", 30)
local share = SP:BuildShareCode()
for k, s in pairs(saved) do o[k] = s.v end

local A = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local bits, bytes = {}, {}
for c in share:sub(6):gmatch(".") do
	local v = A:find(c, 1, true) - 1
	for i = 5, 0, -1 do bits[#bits + 1] = math.floor(v / 2 ^ i) % 2 end
end
for i = 1, math.floor(#bits / 8) do
	local b = 0
	for j = 0, 7 do b = b * 2 + bits[(i - 1) * 8 + j + 1] end
	bytes[i] = b
end
local function bitOf(key)
	for i, f in ipairs(SP.SHARE_FEATURES) do
		if f.key == key then
			local byte = bytes[9 + math.floor((i - 1) / 8)] or 0
			return math.floor(byte / 2 ^ ((i - 1) % 8)) % 2 == 1
		end
	end
	return nil
end
checkEq("the setup code counts every feature", bytes[8], #SP.SHARE_FEATURES)
checkEq("146 features (126 through 3.0.8, 17 through 3.0.9.4, 3 in 3.0.9.5)", #SP.SHARE_FEATURES, 146)
for _, key in ipairs({ "iconScreens", "keysWhenOff", "loadoutsRememberOrder", "raidCoverage", "countdownColors",
	"totemBarClickThrough", "dropAllStartOver" }) do
	checkEq("setup code: " .. key .. " on", bitOf(key), true)
end
checkEq("setup code: buff timers stay off", bitOf("buffTimerColors"), false)
finish()
