-- ShamanPowerShieldSound
-- Sound When Your Shield Drops: a sound the moment your Lightning Shield or Water
-- Shield leaves you (its last charge used, run out, canceled or replaced), in
-- combat too. ONE setting (SP.opt.shieldDropSound / shieldDropSoundName), shown on
-- Shield Charges and on Expiring Alerts > Sound: Shields (ShamanPowerOptions.lua).
-- It plays with Expiring Alerts on, off or not loaded. Until 3.0.6 it was Expiring
-- Alerts' own (shields.sound / soundName): Migrate carries it over, once.
--  * WoW: Forever: in combat the addon cannot see the shield fall (aura reads come
--    back empty, nothing fires), so the GAME plays it: C_UnitAuras.AddAuraSound with
--    the Removed trigger, one registration per shield rank on the list (measured
--    2026-09-22: registered out of combat, it played the moment the last orb was
--    used; 2026-10-01: every rank, as asking whether a rank exists failed at login).
--    Registered out of combat only (in combat inside instanced PvE it is a blocked
--    action), again when the sound changes, removed when the setting or ShamanPower
--    goes off and at logout (the engine kept counting IDs across /reload).
--  * TBC Anniversary (no such call): auras are readable in combat, and UNIT_AURA says
--    which ones came and went. The shields' aura instances are kept, nothing is read
--    for any other change, and a shield whose instance goes plays the sound. The
--    look after login, a reload, a loading screen or a switch is silent, and so is a
--    full update (it only takes a fresh look).

local SP = ShamanPower
if not SP then return end

local IS_SHAMAN = select(2, UnitClass("player")) == "SHAMAN"
local DEFAULT_SOUND = "Raid Warning"
local THROTTLE = 1      -- seconds: one sound per drop (the game's own throttle too)
local CONFIRM = 0.15    -- a shield taken off and put back within this was refreshed, not dropped
local issecret = _G.issecretvalue
local function isSecret(v) return issecret ~= nil and issecret(v) == true end

-- the game plays it (WoW: Forever)
local ENGINE = SPCompat.FOREVER and C_UnitAuras ~= nil and C_UnitAuras.AddAuraSound ~= nil
	and Enum ~= nil and Enum.UnitAuraSoundTrigger ~= nil and Enum.UnitAuraSoundTrigger.Removed ~= nil

-- 3.0.8: one setting PER SHIELD (Lightning, Water, Earth Shield), the same one on
-- Shield Charges and Expiring Alerts: opt.shieldDropSound<S> / shieldDropSoundName<S>
-- (S = LS, WS, ES), empty until changed, using the shared opt.shieldDropSound /
-- shieldDropSoundName until then, so every shield starts with today's one sound.
-- Earth Shield's plays only through Expiring Alerts' Earth Shield alert (as before),
-- so its starting value is the shared one only while that alert is on (A16): it never
-- starts sounding for someone who had that alert off.
local SOUND_ON = { "shieldDropSoundLS", "shieldDropSoundWS", "shieldDropSoundES" }
local SOUND_NAME = { "shieldDropSoundNameLS", "shieldDropSoundNameWS", "shieldDropSoundNameES" }
local function EarthAlertOn()
	local ea = rawget(_G, "ShamanPowerExpiringAlertsDB")
	if type(ea) ~= "table" or ea.enabled == false then return false end
	local s = ea.shields
	return type(s) == "table" and s.enabled ~= false and s.earthShield ~= false
end
-- the value a shield starts from (until it has its own): the shared Sound When Your Shield Drops
function SP:ShieldSoundShared(which)
	local o = self.opt
	local on = o ~= nil and o.shieldDropSound == true
	if which == 3 and on then on = EarthAlertOn() end
	return on, (o and o.shieldDropSoundName) or DEFAULT_SOUND
end
function SP:ShieldSoundOn(which)
	local o = self.opt
	if not o or not SOUND_ON[which] then return false end
	local v = o[SOUND_ON[which]]
	if v == nil then return (self:ShieldSoundShared(which)) end
	return v == true
end
function SP:ShieldSoundName(which)
	local o = self.opt
	local v = o and SOUND_NAME[which] and o[SOUND_NAME[which]]
	if v == nil then v = o and o.shieldDropSoundName end
	return v or DEFAULT_SOUND
end
-- name: "sound" (on / off), "soundName", or "reset" (back to the shared one)
function SP:SetShieldSoundOpt(which, name, v)
	local o = self.opt
	if not o or not SOUND_ON[which] then return end
	if name == "sound" then
		o[SOUND_ON[which]] = v and true or false
	elseif name == "soundName" then
		o[SOUND_NAME[which]] = v
	elseif name == "reset" then
		o[SOUND_ON[which]], o[SOUND_NAME[which]] = nil, nil
	end
	self:UpdateShieldSounds()
end
-- the blue corner: this shield's sound is its own and not the shared one
function SP:ShieldSoundOwnChanged(which)
	local o = self.opt
	if not o or not SOUND_ON[which] then return false end
	local on, name = o[SOUND_ON[which]], o[SOUND_NAME[which]]
	local sharedOn, sharedName = self:ShieldSoundShared(which)
	if on ~= nil and on ~= sharedOn then return true end
	if name ~= nil and name ~= sharedName then return true end
	return false
end
-- each shield's Test Sound (shield = "LS" / "WS" / "ES")
local SHIELD_WHICH = { LS = 1, WS = 2, ES = 3 }
function SP:TestShieldSound(shield)
	local which = SHIELD_WHICH[shield] or shield
	local vol = 100
	local ea = rawget(_G, "ShamanPowerExpiringAlertsDB")
	if not ENGINE or which == 3 then
		local v = type(ea) == "table" and ea.soundVolume or nil
		if type(v) == "number" then vol = v end
	end
	self:PlaySoundWithVolume(self:GetSoundFile(self:ShieldSoundName(which)), vol, true)
end

local function Wanted()
	local o = SP.opt
	return IS_SHAMAN and o ~= nil and (SP:ShieldSoundOn(1) or SP:ShieldSoundOn(2)) and not SP:IsOff()
end

-- ---------------------------------------------------------------------------
-- The setting (both pages' rows call these)
-- ---------------------------------------------------------------------------
function SP:ShieldDropSoundName()
	return (self.opt and self.opt.shieldDropSoundName) or DEFAULT_SOUND
end

function SP:SetShieldDropSound(on)
	self.opt.shieldDropSound = on and true or false
	-- off: the old 3.0.5 switch it came from goes off too, or a profile made later
	-- (which migrates from it) would come back on
	if not on then
		local ea = rawget(_G, "ShamanPowerExpiringAlertsDB")
		if type(ea) == "table" and type(ea.shields) == "table" then ea.shields.sound = false end
	end
	self:UpdateShieldSounds()
end

function SP:SetShieldDropSoundName(name)
	self.opt.shieldDropSoundName = name
	self:UpdateShieldSounds()   -- the game's registrations carry the sound
end

-- How loud: the game's own sound (WoW: Forever) has no volume; on Anniversary it
-- keeps the Expiring Alerts shared volume it always played at, while that module is there.
local function Volume()
	if ENGINE then return 100 end
	local ea = rawget(_G, "ShamanPowerExpiringAlertsDB")
	local v = type(ea) == "table" and ea.soundVolume or nil
	return type(v) == "number" and v or 100
end

-- the Test Sound buttons
function SP:TestShieldDropSound()
	self:PlaySoundWithVolume(self:GetSoundFile(self:ShieldDropSoundName()), Volume(), true)
end

-- 3.0.6: the sound moved here from Expiring Alerts (account-wide). Once per profile:
-- a player who heard it keeps it (Expiring Alerts and its Shield Alerts on, a shield
-- picked), nobody else gets a new sound. A mark, not "is it nil": AceDB copies every
-- default into the profile when it loads and drops them at logout, so an "off" chosen
-- later looks the same as never set, and must not come back on at the next login.
local function Migrate()
	local o = SP.opt
	if not IS_SHAMAN or not o or rawget(o, "shieldDropSoundMigrated") then return end
	o.shieldDropSoundMigrated = true
	if o.shieldDropSound == true then return end   -- already on (a profile from a newer copy)
	local ea = rawget(_G, "ShamanPowerExpiringAlertsDB")
	local s = type(ea) == "table" and ea.shields
	if type(s) ~= "table" or s.sound ~= true or s.enabled == false or ea.enabled == false then return end
	if s.lightning == false and s.water == false and s.earthShield == false then return end   -- it sounded for none of them
	o.shieldDropSound = true
	if type(s.soundName) == "string" and s.soundName ~= "" then o.shieldDropSoundName = s.soundName end
end

local frame   -- the events (made below, for shamans only)

-- ---------------------------------------------------------------------------
-- WoW: Forever: the game plays it
-- ---------------------------------------------------------------------------
local engineIDs = {}
local engineKey          -- the sound the registrations were made with
local enginePending = false
local engineLog = {}     -- one entry per rank tried, read by /spalerts sound
local engineInfo = { unitToken = "player", outputChannel = "Master", throttleSeconds = THROTTLE }

function SP:RemoveShieldSounds()
	if C_UnitAuras and C_UnitAuras.RemoveAuraSound then
		for i = 1, #engineIDs do pcall(C_UnitAuras.RemoveAuraSound, engineIDs[i]) end
	end
	wipe(engineIDs)
	engineKey = nil
	self.shieldSoundEngineActive = nil
end

local function EngineUpdate()
	if not Wanted() then
		enginePending = false
		if #engineIDs > 0 then SP:RemoveShieldSounds() end
		return
	end
	-- each shield its own sound (or none): the key covers both
	local onL, onW = SP:ShieldSoundOn(1), SP:ShieldSoundOn(2)
	local soundL = onL and SP:GetSoundFile(SP:ShieldSoundName(1)) or nil
	local soundW = onW and SP:GetSoundFile(SP:ShieldSoundName(2)) or nil
	local key = tostring(soundL) .. "|" .. tostring(soundW)
	if key == engineKey and #engineIDs > 0 then return end
	if InCombatLockdown() then
		enginePending = true
		frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	enginePending = false
	SP:RemoveShieldSounds()
	wipe(engineLog)
	local info = engineInfo
	for _, set in ipairs(SP.ShieldAuraSets or {}) do
		local sound = (set.name == "Lightning Shield" and soundL) or (set.name == "Water Shield" and soundW) or nil
		if sound then
			if type(sound) == "number" then
				info.soundFileID, info.soundFileName = sound, nil
			else
				info.soundFileID, info.soundFileName = nil, sound
			end
			for _, spellID in ipairs(set.ids) do
				if SP.shieldSoundSolo and spellID ~= SP.shieldSoundSolo then
					engineLog[#engineLog + 1] = spellID .. " solo-off"
				else
					-- every rank on the list, known or not: the game ignores one that never shows up
					info.spellID = spellID
					local ok, id = pcall(C_UnitAuras.AddAuraSound, Enum.UnitAuraSoundTrigger.Removed, info)
					if ok and type(id) == "number" then
						engineIDs[#engineIDs + 1] = id
						engineLog[#engineLog + 1] = spellID .. "=" .. id
					else
						engineLog[#engineLog + 1] = spellID .. (ok and "=nil" or (":" .. tostring(id)))
					end
				end
			end
		end
	end
	engineKey = key
	SP.shieldSoundEngineActive = (#engineIDs > 0) or nil
end

-- ---------------------------------------------------------------------------
-- TBC Anniversary: ShamanPower plays it
-- ---------------------------------------------------------------------------
local KIND_BY_ID, KIND_BY_NAME = {}, {}   -- 1 Lightning Shield, 2 Water Shield
local RANKS = { {}, {} }
for _, set in ipairs(SP.ShieldAuraSets or {}) do
	local kind = (set.name == "Lightning Shield" and 1) or (set.name == "Water Shield" and 2) or nil
	if kind then
		KIND_BY_NAME[set.name] = kind
		for _, id in ipairs(set.ids) do
			KIND_BY_ID[id] = kind
			RANKS[kind][#RANKS[kind] + 1] = id
		end
	end
end
local namesLearned = false
local auraByID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID

local watch                 -- the UNIT_AURA frame, made the first time it is wanted
local watching = false
local inWorld = false       -- false from login and through every loading screen
local primed = false        -- instL / instW known; until then the next look is silent
local instL, instW          -- the aura instance of your Lightning / Water Shield (nil = not on you)
local goneL, goneW, confirmQueued = false, false, false
local lastPlayed = -THROTTLE

-- your shield of this kind: true, its aura instance (nil = not on you); false = cannot tell
local function Find(kind)
	if not auraByID then return false end
	local ranks = RANKS[kind]
	for i = 1, #ranks do
		local ok, a = pcall(auraByID, ranks[i])
		if not ok or isSecret(a) then return false end
		if a ~= nil then
			local id = type(a) == "table" and a.auraInstanceID
			if isSecret(id) or type(id) ~= "number" then return false end
			return true, id
		end
	end
	return true, nil
end

-- a silent look
local function Prime()
	if not namesLearned then
		-- the client's own names (a German client has its own), for auras the rank list misses
		namesLearned = true
		local getName = GetSpellInfo or (C_Spell and C_Spell.GetSpellName)
		for kind = 1, 2 do
			local ok, name = false, nil
			if getName and RANKS[kind][1] then ok, name = pcall(getName, RANKS[kind][1]) end
			if ok and type(name) == "string" and not isSecret(name) then KIND_BY_NAME[name] = kind end
		end
	end
	local okL, l = Find(1)
	local okW, w = Find(2)
	if okL and okW then
		instL, instW, primed = l, w, true
	else
		instL, instW, primed = nil, nil, false
	end
	goneL, goneW = false, false
end

local function Play(kind)
	local now = GetTime()
	if now - lastPlayed < THROTTLE then return end
	lastPlayed = now
	SP:PlaySoundWithVolume(SP:GetSoundFile(SP:ShieldSoundName(kind)), Volume(), true)
	if SP.shieldSoundDebug then SP:Print("shield drop: sound played") end
end

-- a moment after a shield went: still gone (not put straight back) = dropped
local function Confirm()
	confirmQueued = false
	local l, w = goneL, goneW
	goneL, goneW = false, false
	if not (watching and inWorld and primed and Wanted()) then return end
	-- each shield's own setting and sound
	if l and instL == nil and SP:ShieldSoundOn(1) then Play(1)
	elseif w and instW == nil and SP:ShieldSoundOn(2) then Play(2) end
end

-- 1 Lightning, 2 Water, 0 another aura, -1 cannot tell (secret)
local function KindOf(a)
	if type(a) ~= "table" or isSecret(a) then return -1 end
	local id, name = a.spellId, a.name
	if isSecret(id) or isSecret(name) then return -1 end
	return KIND_BY_ID[id] or KIND_BY_NAME[name] or 0
end

local function OnAura(info)
	if not inWorld then return end   -- login and loading screens: the look after them is silent
	if not primed or type(info) ~= "table" or isSecret(info) then Prime() return end
	local full = info.isFullUpdate
	if isSecret(full) or full then Prime() return end
	local lostL, lostW, newL, newW = false, false, nil, nil
	local removed = info.removedAuraInstanceIDs
	if isSecret(removed) then Prime() return end   -- test before comparing: a secret cannot be compared
	if removed ~= nil then
		if type(removed) ~= "table" then Prime() return end
		for i = 1, #removed do
			local id = removed[i]
			if isSecret(id) then Prime() return end
			if id == instL then lostL = true elseif id == instW then lostW = true end
		end
	end
	local added = info.addedAuras
	if isSecret(added) then Prime() return end
	if added ~= nil then
		if type(added) ~= "table" then Prime() return end
		for i = 1, #added do
			local a = added[i]
			local kind = KindOf(a)
			if kind == -1 then Prime() return end
			if kind > 0 then
				local id = a.auraInstanceID
				if isSecret(id) or type(id) ~= "number" then Prime() return end
				if kind == 1 then newL = id else newW = id end
			end
		end
	end
	if lostL then instL = nil end
	if lostW then instW = nil end
	if newL then instL = newL end
	if newW then instW = newW end
	-- gone and not back in the same update (a swap for the other shield still counts)
	if lostL and not newL then goneL = true end
	if lostW and not newW then goneW = true end
	if (goneL or goneW) and not confirmQueued then
		confirmQueued = true
		C_Timer.After(CONFIRM, Confirm)
	end
end

local function TrackerUpdate()
	if Wanted() then
		if watching then return end
		if not watch then
			watch = CreateFrame("Frame")
			watch:SetScript("OnEvent", function(_, _, unit, info)
				if unit == "player" then OnAura(info) end
			end)
			if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(watch, "core (shield sound)") end
		end
		if watch.RegisterUnitEvent then
			watch:RegisterUnitEvent("UNIT_AURA", "player")
		else
			watch:RegisterEvent("UNIT_AURA")   -- no unit filter on this client: the handler checks the unit
		end
		watching = true
		primed = false
		if inWorld then Prime() end   -- switched on: what is on you now is not a drop
	elseif watching then
		watch:UnregisterEvent("UNIT_AURA")
		watching = false
		primed, instL, instW, goneL, goneW = false, nil, nil, false, false
	end
end

-- ---------------------------------------------------------------------------
-- Both
-- ---------------------------------------------------------------------------
-- the setting, ShamanPower switched on or off, a profile, the sound: set up to match
function SP:UpdateShieldSounds()
	if not (IS_SHAMAN and self.opt) then return end   -- (before the profile is loaded: nothing yet)
	if ENGINE then EngineUpdate() else TrackerUpdate() end
end

-- /spalerts sound [solo | all]: what the sound is doing, for testing. "solo" registers
-- Lightning Shield 324 alone on WoW: Forever, "all" every rank again.
function SP:ShieldSoundCommand(arg)
	self.shieldSoundDebug = true
	if arg == "solo" then self.shieldSoundSolo = 324 elseif arg == "all" then self.shieldSoundSolo = nil end
	if arg == "solo" or arg == "all" then self:RemoveShieldSounds() end
	self:UpdateShieldSounds()
	self:ShieldSoundReport()
end

function SP:ShieldSoundReport()
	local o = self.opt or {}
	self:Print(("Shield drop sound: on=%s wanted=%s off=%s combat=%s played by=%s"):format(
		tostring(o.shieldDropSound == true) .. " LS=" .. tostring(self:ShieldSoundOn(1)) .. " WS=" .. tostring(self:ShieldSoundOn(2))
			.. " ES=" .. tostring(self:ShieldSoundOn(3)), tostring(Wanted()), tostring(self:IsOff()),
		tostring(InCombatLockdown()), ENGINE and "the game" or "ShamanPower"))
	local sound = self:GetSoundFile(self:ShieldDropSoundName())
	self:Print(("  sound=%s (%s) name=%s volume=%s"):format(tostring(sound), type(sound),
		tostring(self:ShieldDropSoundName()), tostring(Volume())))
	if ENGINE then
		self:Print(("  engine=%s pending=%s key=%s"):format(tostring(self.shieldSoundEngineActive),
			tostring(enginePending), tostring(engineKey)))
		self:Print("  registered " .. #engineIDs .. ": " .. table.concat(engineLog, ", "))
	else
		self:Print(("  watching=%s inWorld=%s primed=%s lightning=%s water=%s"):format(tostring(watching),
			tostring(inWorld), tostring(primed), tostring(instL), tostring(instW)))
	end
end

if not IS_SHAMAN then return end

-- A profile switched, copied, reset or imported (an import calls the core's handler
-- itself, not through the database): the new profile's setting, a moment later so
-- every part of the import is in place first.
local function ProfileSwitched()
	Migrate()
	SP:UpdateShieldSounds()
end
if hooksecurefunc and SP.OnProfileChanged then
	hooksecurefunc(SP, "OnProfileChanged", function() C_Timer.After(0, ProfileSwitched) end)
end

frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")
if ENGINE then frame:RegisterEvent("PLAYER_LOGOUT") end
frame:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		-- every addon's saved settings are loaded by now (Expiring Alerts' too)
		Migrate()
		if SP.db and SP.db.RegisterCallback then
			-- Reset Profile means the defaults: nothing is carried into it (marked now,
			-- before the look ProfileSwitched takes a moment later)
			local key = {}   -- own key: registering with SP itself would replace the core's handler
			SP.db.RegisterCallback(key, "OnProfileReset", function()
				local p = SP.db.profile
				if p then p.shieldDropSoundMigrated = true end
			end)
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		inWorld = true
		SP:UpdateShieldSounds()
		if watching and not primed then Prime() end
	elseif event == "PLAYER_LEAVING_WORLD" then
		inWorld, primed, goneL, goneW = false, false, false, false
	elseif event == "PLAYER_REGEN_ENABLED" then
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		if enginePending then SP:UpdateShieldSounds() end
	elseif event == "PLAYER_LOGOUT" then
		SP:RemoveShieldSounds()
	end
end)

-- Enable ShamanPower switched (out of combat): off removes the game's registrations
-- and stops the watch; on sets them up again (what is on you then is not a drop)
SP:OnOnOff(function() SP:UpdateShieldSounds() end)
