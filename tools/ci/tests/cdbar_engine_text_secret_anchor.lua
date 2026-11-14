-- client: forever
-- (3.0.9.13) interslice's report (Discord, 11-13): "FontString:SetPoint(): Usage" from ShamanPower.lua
-- PlaceEngineBarText, through FeedEngineBarCooldown and UpdateCooldownButtons. On WoW: Forever the game draws the
-- cooldown bar's countdown number, put where the addon's own time text would be: its spot was read with GetPoint
-- every time a cooldown started, and in a fight that read can come back as secret values, which SetPoint refuses.
-- Now the spot read outside a fight is used there; the number lands where it always did, and nothing errors.
local SP = ShamanPower
if not SP:EngineCooldownsOn() then skip("no engine-drawn cooldowns on this client") end

local btn
for _, b in ipairs(SP.cooldownButtons or {}) do
	if b.spellID and b.insideText and b.cooldown and b.cooldown.GetCountdownFontString then btn = b break end
end
if not btn then skip("no cooldown bar button with a spell here") end

-- a running cooldown, as the game hands it to the engine
local realDur = C_Spell.GetSpellCooldownDuration
C_Spell.GetSpellCooldownDuration = function()
	local d = C_DurationUtil.CreateDuration()
	d:SetTimeFromStart(GetTime(), 30)
	return d
end
local fs = btn.cooldown:GetCountdownFontString()

-- 1. outside a fight: the number takes the inside text's spot
btn._ebSpell = nil
local ok, err = pcall(SP.FeedEngineBarCooldown, SP, btn, GetTime(), 30, true, true, "inside", false, "bottom")
check("outside a fight: no error", ok, tostring(err))
local p1, _, rp1, x1, y1 = fs:GetPoint(1)
check("outside a fight: the number placed", p1 ~= nil)

-- 2. in a fight: the inside text's spot reads back as secret values
local realGetPoint = btn.insideText.GetPoint
btn.insideText.GetPoint = function() return "CENTER", __sim.secret("rel"), "CENTER", __sim.secret("x"), __sim.secret("y") end
btn._ebSpell = nil   -- (a new cooldown: the feed places the number again)
ok, err = pcall(SP.FeedEngineBarCooldown, SP, btn, GetTime(), 30, true, true, "inside", false, "bottom")
check("in a fight, the spot secret: no error", ok, tostring(err))
local p2, _, rp2, x2, y2 = fs:GetPoint(1)
check("the number stays where it was placed outside the fight", p2 == p1 and rp2 == rp1 and x2 == x1 and y2 == y1,
	string.format("%s %s %s %s -> %s %s %s %s", tostring(p1), tostring(rp1), tostring(x1), tostring(y1), tostring(p2), tostring(rp2), tostring(x2), tostring(y2)))

btn.insideText.GetPoint = realGetPoint
C_Spell.GetSpellCooldownDuration = realDur
btn._ebSpell = nil
finish()
