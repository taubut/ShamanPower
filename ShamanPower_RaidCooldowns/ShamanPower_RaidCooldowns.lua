-- ============================================================================
-- ShamanPower [Raid Cooldowns] Module
-- Raid Cooldown Management - BL/Heroism and Mana Tide calling
-- ============================================================================

local SP = ShamanPower
if not SP then
	print("|cff0070ddShamanPower [Raid Cooldowns]:|r Core addon not found!")
	return
end

-- Mark module as loaded
SP.RaidCooldownsLoaded = true

-- WoW: Forever has neither Bloodlust / Heroism nor Drums of Battle, so there
-- the module is Mana Tide only: no BL or Drums button, nothing to call. Both
-- answer true on every other client.
local function HasBloodlust() return not (SPCompat and SPCompat.HasBloodlust) or SPCompat.HasBloodlust() end
local function HasDrums() return not (SPCompat and SPCompat.HasDrums) or SPCompat.HasDrums() end

-- Raid calls (Mana Tide / Bloodlust / Drums) also go out on their own addon
-- prefix, at ChatThrottleLib's ALERT priority: Blizzard throttles addon messages
-- per prefix, so a backlog on the main one (a roster change in a big raid) can
-- never hold a call back. The main prefix still carries them for older versions;
-- a call that arrives on both is acted on once (see isRepeatCall).
local CALL_PREFIX = "SHPWRC"
do
	local register = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or _G.RegisterAddonMessagePrefix
	if register then pcall(register, CALL_PREFIX) end
	local f = CreateFrame("Frame")
	if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(f, "Raid Cooldowns (raid calls)") end
	f:RegisterEvent("CHAT_MSG_ADDON")
	f:SetScript("OnEvent", function(_, _, prefix, message, distribution, source)
		if prefix ~= CALL_PREFIX then return end
		if not (distribution == "PARTY" or distribution == "RAID" or distribution == "INSTANCE_CHAT") then return end
		if type(message) ~= "string" or type(source) ~= "string" then return end
		local sender = SP:RemoveRealmName(Ambiguate(source, "none"))
		if sender == SP.player then return end
		SP:HandleRaidCooldownMessage(prefix, message, sender)
	end)
end

local function sendCall(msg)
	if not (ChatThrottleLib and IsInGroup()) then return end
	local channel
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and IsInInstance() then
		channel = "INSTANCE_CHAT"
	elseif IsInRaid() then
		channel = "RAID"
	else
		channel = "PARTY"
	end
	pcall(ChatThrottleLib.SendAddonMessage, ChatThrottleLib, "ALERT", CALL_PREFIX, msg, channel)
end

-- Every press goes out on both prefixes and alerts once. The main-prefix copy
-- waits at NORMAL priority and can arrive any time later, so once a CALL_PREFIX
-- copy of a call (sender and message) has been acted on, that call's
-- CALL_PREFIX copies alert and its main-prefix copies are ignored. Until then
-- (an older version without CALL_PREFIX, or the first presses of a call) every
-- main copy alerts and is queued, and each CALL_PREFIX copy drops one queued
-- copy instead of alerting: two quick presses arriving main, main, fast, fast
-- alert twice. ChatThrottleLib drops a send that fails for any reason but the
-- prefix throttle, so the queued copy dropped can be one whose own twin was
-- lost, and the CALL_PREFIX copy a re-press's: dropping one marks nothing, and
-- that re-press's main copy still alerts when it lands. A queued copy is
-- forgotten after CALL_PAIR_WINDOW (an older version never sends the twin; a
-- twin later than that alerts again). Without an id per press, a lost
-- CALL_PREFIX copy of a call already acted on is a lost alert.
local CALL_PAIR_WINDOW = 10
local callPrefixCalls = {}     -- [sender .. message] = true once a CALL_PREFIX copy of it was acted on
local unpairedCalls = {}       -- [sender .. message] = { when each unpaired main copy was acted on, oldest first }
local function isRepeatCall(prefix, sender, message)
	sender = sender or ""
	local key = sender .. "\001" .. message
	if prefix ~= CALL_PREFIX and callPrefixCalls[key] then return true end
	local now = GetTime()
	local waiting = unpairedCalls[key]
	if waiting then
		while waiting[1] and now - waiting[1] >= CALL_PAIR_WINDOW do table.remove(waiting, 1) end
	end
	if prefix == CALL_PREFIX then
		if waiting and waiting[1] then
			table.remove(waiting, 1)
			return true
		end
		callPrefixCalls[key] = true
		return false
	end
	if not waiting then waiting = {}; unpairedCalls[key] = waiting end
	waiting[#waiting + 1] = now
	return false
end
local callerRequestEstimates = _G.SPCompat and _G.SPCompat.secretsRegime

-- Preview (settings pane / unlock) sample data. The Bloodlust sample is keyed
-- in callerCooldowns under a name no player can have (it holds a space) so a
-- demo click never touches a real shaman's cooldown.
local DEMO_BL_TARGET = "Srumar"
local DEMO_BL_KEY = "demo bl"
local DEMO_CD = { bl = 14, mt = 10 }

-- ============================================================================
-- RAID COOLDOWN MANAGEMENT
-- ============================================================================

function SP:InitRaidCooldowns()
	if not ShamanPower_RaidCooldowns then
		ShamanPower_RaidCooldowns = {}
	end
	if not ShamanPower_RaidCooldowns.bloodlust then
		ShamanPower_RaidCooldowns.bloodlust = {
			primary = nil,
			backup1 = nil,
			backup2 = nil,
			caller = nil,
		}
	end
	if not ShamanPower_RaidCooldowns.manatide then
		ShamanPower_RaidCooldowns.manatide = {}
	end
	if not ShamanPower_RaidCooldowns.drums then
		ShamanPower_RaidCooldowns.drums = { drummers = {}, caller = nil }
	end
end

-- Check if player can assign raid cooldowns (RL or assist)
function SP:CanAssignRaidCooldowns()
	-- Allow solo players to manage their own settings
	if GetNumGroupMembers() == 0 then
		return true
	end
	return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

-- Check if player can call raid cooldowns
function SP:CanCallRaidCooldowns()
	if self:CanAssignRaidCooldowns() then return true end
	local playerName = self.player
	local bl = ShamanPower_RaidCooldowns.bloodlust
	if bl and bl.caller and bl.caller == playerName then
		return true
	end
	return false
end

-- Get the shaman who should use BL (checks if primary is dead, falls back to backups)
function SP:GetBloodlustTarget()
	local bl = ShamanPower_RaidCooldowns.bloodlust
	if not bl then return nil end

	-- Check primary
	if bl.primary and not UnitIsDeadOrGhost(bl.primary) then
		return bl.primary
	end
	-- Check backup1
	if bl.backup1 and not UnitIsDeadOrGhost(bl.backup1) then
		return bl.backup1
	end
	-- Check backup2
	if bl.backup2 and not UnitIsDeadOrGhost(bl.backup2) then
		return bl.backup2
	end
	return nil
end

-- Toggle the raid cooldown panel
-- The panel lives in ShamanPower_Config (RaidCD.lua), which replaces these
-- two functions; without that module there is no window.
function SP:ToggleRaidCooldownPanel()
	print("|cff0070ddShamanPower|r: the ShamanPower_Config module is required for the Raid Cooldowns window")
end

-- Create the raid cooldown panel UI

-- Get list of shamans in the raid/party
function SP:GetRaidShamans()
	local shamans = {}
	local prefix, maxMembers

	if IsInRaid() then
		prefix = "raid"
		maxMembers = 40
	elseif IsInGroup() then
		prefix = "party"
		maxMembers = 4
		-- Include self
		local _, class = UnitClass("player")
		if class == "SHAMAN" then
			local name = UnitName("player")
			table.insert(shamans, name)
		end
	else
		-- Solo
		local _, class = UnitClass("player")
		if class == "SHAMAN" then
			local name = UnitName("player")
			table.insert(shamans, name)
		end
		return shamans
	end

	for i = 1, maxMembers do
		local unit = prefix .. i
		if UnitExists(unit) then
			local _, class = UnitClass(unit)
			if class == "SHAMAN" then
				local name = UnitName(unit)
				table.insert(shamans, name)
			end
		end
	end

	return shamans
end

-- Get list of all raid/party members
function SP:GetRaidMembers()
	local members = {}
	local prefix, maxMembers

	if IsInRaid() then
		prefix = "raid"
		maxMembers = 40
	elseif IsInGroup() then
		prefix = "party"
		maxMembers = 4
		local name = UnitName("player")
		table.insert(members, name)
	else
		local name = UnitName("player")
		table.insert(members, name)
		return members
	end

	for i = 1, maxMembers do
		local unit = prefix .. i
		if UnitExists(unit) then
			local name = UnitName(unit)
			table.insert(members, name)
		end
	end

	return members
end

-- Update the raid cooldown panel dropdowns
function SP:UpdateRaidCooldownPanel()
	self:UpdateCallerButtons()
end

-- Get shamans who have Mana Tide with their group number
function SP:GetManaTideShamans()
	local mtShamans = {}
	local prefix, maxMembers

	if IsInRaid() then
		prefix = "raid"
		maxMembers = 40
	elseif IsInGroup() then
		prefix = "party"
		maxMembers = 4
		-- Check self
		local _, class = UnitClass("player")
		if class == "SHAMAN" then
			-- Check if we have Mana Tide (spell ID 16190)
			if IsSpellKnown(16190) then
				local name = UnitName("player")
				table.insert(mtShamans, {name = name, group = 1})
			end
		end
	else
		-- Solo
		local _, class = UnitClass("player")
		if class == "SHAMAN" and IsSpellKnown(16190) then
			local name = UnitName("player")
			table.insert(mtShamans, {name = name, group = 1})
		end
		return mtShamans
	end

	for i = 1, maxMembers do
		local unit = prefix .. i
		if UnitExists(unit) then
			local _, class = UnitClass(unit)
			if class == "SHAMAN" then
				local name = UnitName(unit)
				-- Check if this shaman has Mana Tide via AllShamans data
				-- For now, add all shamans and let them self-report MT capability
				local group = 1
				if IsInRaid() then
					local _, _, subgroup = GetRaidRosterInfo(i)
					group = subgroup or 1
				end
				-- Add all shamans - if they don't have MT, assignment just won't work for them
				table.insert(mtShamans, {name = name, group = group})
			end
		end
	end

	return mtShamans
end

-- Update Mana Tide assignment rows

-- Call Mana Tide for a specific shaman
function SP:CallManaTideForShaman(shamanName)
	local mt = ShamanPower_RaidCooldowns.manatide
	local canCall = self:CanAssignRaidCooldowns() or (mt[shamanName] and mt[shamanName].caller == self.player)

	if not canCall then
		print("|cff0070ddShamanPower:|r You don't have permission to call Mana Tide for " .. shamanName)
		return
	end

	if _G.SPK and _G.SPK() == true then
		print("|cff0070ddShamanPower:|r Addon messages are locked right now - call it by voice.")
		return
	end
	local sent = self:SendMessage("MTCALL|" .. shamanName, nil, nil, true)
	sendCall("MTCALL|" .. shamanName)
	if callerRequestEstimates and sent ~= false then
		self:RecordManaTideRequest(shamanName)
		self:UpdateCallerButtonCooldowns()
		self:StartCallerCooldownTracking()
	end

	if shamanName == self.player then
		self:ShowManaTideAlert()
	end

	print("|cff0070ddShamanPower:|r Called Mana Tide from " .. shamanName)
end

-- Send raid cooldown sync to group
function SP:SendRaidCooldownSync()
	local bl = ShamanPower_RaidCooldowns.bloodlust
	local data = string.format("RCSYNC|%s|%s|%s|%s",
		bl.primary or "",
		bl.backup1 or "",
		bl.backup2 or "",
		bl.caller or ""
	)
	self:SendMessage(data)

	-- Also send MT assignments (always send, even if empty, so receivers can clear)
	local mt = ShamanPower_RaidCooldowns.manatide
	local mtParts = {}
	for shamanName, mtData in pairs(mt) do
		if mtData.caller then
			table.insert(mtParts, shamanName .. ":" .. mtData.caller)
		end
	end
	self:SendMessage("MTSYNC|" .. table.concat(mtParts, ","))

	-- Drums: per-group drummers and the caller
	local drums = ShamanPower_RaidCooldowns.drums or { drummers = {} }
	local dParts = {}
	for group, name in pairs(drums.drummers or {}) do
		if name and name ~= "" then table.insert(dParts, tostring(group) .. ":" .. name) end
	end
	self:SendMessage("DRUMSYNC|" .. table.concat(dParts, ",") .. "|" .. (drums.caller or ""))
end

-- Call for Bloodlust/Heroism
-- ---------------------------------------------------------------------------
-- Drums of Battle: one drummer per party group, plus a caller.
-- ---------------------------------------------------------------------------
local DRUMS_ICON = "Interface\\Icons\\INV_Misc_Drum_02"

-- { [group] = { names } } for the current raid (party = group 1)
function SP:GetGroupMembers()
	local groups = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local name, _, subgroup = GetRaidRosterInfo(i)
			if name then
				groups[subgroup] = groups[subgroup] or {}
				table.insert(groups[subgroup], name)
			end
		end
	else
		groups[1] = self:GetRaidMembers()
	end
	for _, list in pairs(groups) do table.sort(list) end
	return groups
end

function SP:GetDrummers()
	local drums = ShamanPower_RaidCooldowns and ShamanPower_RaidCooldowns.drums
	local out = {}
	if not drums or not drums.drummers then return out end
	for _, name in pairs(drums.drummers) do
		if name and name ~= "" then table.insert(out, name) end
	end
	table.sort(out)
	return out
end

function SP:CanCallDrums()
	if self:CanAssignRaidCooldowns() then return true end
	local drums = ShamanPower_RaidCooldowns.drums
	return (drums and drums.caller == self.player) and true or false
end

function SP:ShowDrumsAlert()
	self:ShowCenterScreenAlert(DRUMS_ICON, "USE DRUMS NOW")
end

function SP:IsDrummer(name)
	local drums = ShamanPower_RaidCooldowns and ShamanPower_RaidCooldowns.drums
	if not drums or not drums.drummers then return false end
	for _, n in pairs(drums.drummers) do
		if n == name then return true end
	end
	return false
end

function SP:CallDrums()
	if not HasDrums() then
		print("|cff0070ddShamanPower:|r Drums of Battle do not exist on this client.")
		return
	end
	if not self:CanCallDrums() then
		print("|cff0070ddShamanPower:|r You don't have permission to call for Drums.")
		return
	end
	local drummers = self:GetDrummers()
	if #drummers == 0 then
		print("|cff0070ddShamanPower:|r No drummers assigned!")
		return
	end
	if _G.SPK and _G.SPK() == true then
		print("|cff0070ddShamanPower:|r Addon messages are locked right now - call it by voice.")
		return
	end
	self:SendMessage("DRUMCALL", nil, nil, true)
	sendCall("DRUMCALL")
	if self:IsDrummer(self.player) then
		self:ShowDrumsAlert()
	end
	print("|cff0070ddShamanPower:|r Called Drums of Battle (" .. table.concat(drummers, ", ") .. ")")
end

function SP:CallBloodlust()
	if not HasBloodlust() then
		print("|cff0070ddShamanPower:|r Bloodlust / Heroism does not exist on this client.")
		return
	end
	if not self:CanCallRaidCooldowns() then
		print("|cff0070ddShamanPower:|r You don't have permission to call for Bloodlust.")
		return
	end

	local target = self:GetBloodlustTarget()
	if not target then
		print("|cff0070ddShamanPower:|r No shaman assigned for Bloodlust!")
		return
	end

	-- Send call message
	if _G.SPK and _G.SPK() == true then
		print("|cff0070ddShamanPower:|r Addon messages are locked right now - call it by voice.")
		return
	end
	self:SendMessage("BLCALL|" .. target, nil, nil, true)
	sendCall("BLCALL|" .. target)

	-- Show alert if we're the target
	if target == self.player then
		self:ShowBloodlustAlert()
	end

	local faction = UnitFactionGroup("player")
	local blName = (faction == "Alliance") and "Heroism" or "Bloodlust"
	print("|cff0070ddShamanPower:|r Called " .. blName .. " from " .. target)
end

-- Call for Mana Tide
function SP:CallManaTide()
	if not self:CanCallRaidCooldowns() then
		print("|cff0070ddShamanPower:|r You don't have permission to call for Mana Tide.")
		return
	end

	-- Send call to all shamans with Mana Tide
	if _G.SPK and _G.SPK() == true then
		print("|cff0070ddShamanPower:|r Addon messages are locked right now - call it by voice.")
		return
	end
	local sent = self:SendMessage("MTCALL", nil, nil, true)
	sendCall("MTCALL")
	if callerRequestEstimates and sent ~= false then
		-- The broadcast has no named recipient; estimate only configured shamans.
		for name in pairs(_G.ShamanPower_RaidCooldowns.manatide) do self:RecordManaTideRequest(name) end
		self:UpdateCallerButtonCooldowns()
		self:StartCallerCooldownTracking()
	end
	print("|cff0070ddShamanPower:|r Called for Mana Tide!")
end

-- Show alert when called for Bloodlust
function SP:ShowBloodlustAlert()
	local faction = UnitFactionGroup("player")
	local blName = (faction == "Alliance") and "HEROISM" or "BLOODLUST"
	local icon = (faction == "Alliance") and "Interface\\Icons\\Ability_Shaman_Heroism" or "Interface\\Icons\\Spell_Nature_Bloodlust"

	-- Show center screen alert
	self:ShowCenterScreenAlert(icon, "USE " .. blName .. " NOW!")

	-- Also add glow/shake to cooldown bar button
	local blSpellID = (faction == "Alliance") and 32182 or 2825
	self:AddCooldownButtonAlert(blSpellID)
end

-- WoW: Forever: your own Mana Tide ends the cooldown bar alert (else it pulses its
-- full 10 s; the caller buttons' cast watch only runs where they show). Your own
-- casts are never secret, and this listens only while an alert is up.
local ownTideFrame, ownTideSerial = nil, 0
local function WatchOwnManaTide()
	if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then return end
	if not ownTideFrame then
		ownTideFrame = CreateFrame("Frame")
		ownTideFrame:SetScript("OnEvent", function(f, _, _, _, spellID)
			if issecretvalue and issecretvalue(spellID) then return end
			if spellID == 16190 then
				f:UnregisterAllEvents()
				SP:RemoveCooldownButtonAlert(16190)
			end
		end)
	end
	ownTideFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	ownTideSerial = ownTideSerial + 1
	local serial = ownTideSerial
	C_Timer.After(10, function()
		if ownTideSerial == serial then ownTideFrame:UnregisterAllEvents() end
	end)
end

-- Show alert when called for Mana Tide
function SP:ShowManaTideAlert()
	-- Show center screen alert
	self:ShowCenterScreenAlert("Interface\\Icons\\Spell_Frost_SummonWaterElemental", "USE MANA TIDE NOW!")

	-- Also add glow/shake to cooldown bar button
	self:AddCooldownButtonAlert(16190)  -- Mana Tide Totem spell ID
	WatchOwnManaTide()
end

-- Show a center screen alert with icon and text
function SP:ShowCenterScreenAlert(iconPath, text)
	-- Check if any alerts are enabled
	local showIcon = self.opt.raidCDShowWarningIcon ~= false
	local showText = self.opt.raidCDShowWarningText ~= false
	local playSound = self.opt.raidCDPlaySound ~= false

	-- If nothing to show, just play sound if enabled
	if not showIcon and not showText then
		if playSound then
			ShamanPower:PlaySoundWithVolume(8959, self.opt.raidCDSoundVolume, false)
		end
		return
	end

	if not self.centerAlert then
		local frame = CreateFrame("Frame", "ShamanPowerCenterAlert", UIParent)
		frame:SetSize(150, 150)
		frame:SetPoint("CENTER", 0, 100)
		frame:SetFrameStrata("FULLSCREEN_DIALOG")

		local iconTex = frame:CreateTexture(nil, "ARTWORK")
		iconTex:SetSize(128, 128)
		iconTex:SetPoint("CENTER")
		iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		frame.icon = iconTex

		local alertText = frame:CreateFontString(nil, "OVERLAY")
		SP:SetSPFont(alertText, "alerts", 24, "OUTLINE")
		alertText:SetPoint("TOP", frame, "BOTTOM", 0, -10)
		alertText:SetTextColor(1, 0.3, 0)
		frame.text = alertText

		-- The engine runs the animation (no per-frame Lua):
		-- the whole alert breathes between 100% and 20% opacity, the icon swells
		-- 5% and back, and a separate 5 s timeline hides it at the end.
		local pulse = frame:CreateAnimationGroup()
		pulse:SetLooping("REPEAT")
		local fadeOut = pulse:CreateAnimation("Alpha")
		fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0.2); fadeOut:SetDuration(0.785); fadeOut:SetSmoothing("IN_OUT"); fadeOut:SetOrder(1)
		local fadeIn = pulse:CreateAnimation("Alpha")
		fadeIn:SetFromAlpha(0.2); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.785); fadeIn:SetSmoothing("IN_OUT"); fadeIn:SetOrder(2)
		frame.pulse = pulse

		local swell = iconTex:CreateAnimationGroup()
		swell:SetLooping("REPEAT")
		-- Forever and Anniversary both name these SetScaleFrom/SetScaleTo; clients
		-- before them used SetFromScale/SetToScale (either missing: no swell, no error)
		local function scale(anim, from, to)
			if anim.SetScaleFrom then anim:SetScaleFrom(from, from); anim:SetScaleTo(to, to)
			elseif anim.SetFromScale then anim:SetFromScale(from, from); anim:SetToScale(to, to) end
		end
		local grow = swell:CreateAnimation("Scale")
		scale(grow, 0.95, 1.05); grow:SetDuration(0.628); grow:SetSmoothing("IN_OUT"); grow:SetOrder(1)
		local shrink = swell:CreateAnimation("Scale")
		scale(shrink, 1.05, 0.95); shrink:SetDuration(0.628); shrink:SetSmoothing("IN_OUT"); shrink:SetOrder(2)
		frame.swell = swell

		-- one timeline per alert: a new alert restarts it, so an older alert's
		-- end can no longer hide a newer one early
		local life = frame:CreateAnimationGroup()
		local span = life:CreateAnimation("Animation")
		span:SetDuration(5)
		life:SetScript("OnFinished", function() frame:Hide() end)
		frame.life = life

		frame:SetScript("OnHide", function(f)
			f.pulse:Stop(); f.swell:Stop(); f.life:Stop()
			-- OnHide also fires when UIParent hides (Alt+Z, a cinematic) while the alert
			-- itself stays shown: end it, or it comes back with no timeline to hide it
			if f:IsShown() then f:Hide() end
		end)

		frame:Hide()
		self.centerAlert = frame
	end

	-- Show/hide icon based on option
	if showIcon then
		self.centerAlert.icon:SetTexture(iconPath)
		self.centerAlert.icon:Show()
	else
		self.centerAlert.icon:Hide()
	end

	-- Show/hide text based on option
	if showText then
		self.centerAlert.text:SetText(text)
		self.centerAlert.text:Show()
	else
		self.centerAlert.text:Hide()
	end

	local alert = self.centerAlert
	alert:SetAlpha(1)
	alert:Show()
	-- (re)start: pulse and swell loop until the 5 s timeline hides the alert
	alert.pulse:Stop(); alert.pulse:Play()
	alert.swell:Stop()
	if showIcon then alert.swell:Play() end
	alert.life:Stop(); alert.life:Play()

	-- Play sound if enabled
	if playSound then
		ShamanPower:PlaySoundWithVolume(8959, self.opt.raidCDSoundVolume, false)
	end
end

-- Handle incoming raid cooldown messages
function SP:HandleRaidCooldownMessage(prefix, message, sender)
	local cmd, rest = strsplit("|", message, 2)
	if (cmd == "BLCALL" or cmd == "MTCALL" or cmd == "DRUMCALL") and isRepeatCall(prefix, sender, message) then return end

	if cmd == "RCSYNC" then
		-- Sync from raid leader
		local primary, backup1, backup2, caller = strsplit("|", rest)
		self:InitRaidCooldowns()
		local bl = ShamanPower_RaidCooldowns.bloodlust
		bl.primary = (primary ~= "") and primary or nil
		bl.backup1 = (backup1 ~= "") and backup1 or nil
		bl.backup2 = (backup2 ~= "") and backup2 or nil
		bl.caller = (caller ~= "") and caller or nil

		if self.raidCooldownPanel and self.raidCooldownPanel:IsShown() then
			self:UpdateRaidCooldownPanel()
		end

	elseif cmd == "BLCALL" then
		-- Called for Bloodlust
		local target = rest
		if target == self.player then
			self:ShowBloodlustAlert()
		end

	elseif cmd == "MTCALL" then
		-- Called for Mana Tide - check if it's for us specifically or broadcast
		local targetShaman = rest
		if targetShaman and targetShaman ~= "" then
			-- Specific shaman called
			if targetShaman == self.player and IsSpellKnown(16190) then
				self:ShowManaTideAlert()
			end
		else
			-- Broadcast to all MT shamans
			if IsSpellKnown(16190) then
				self:ShowManaTideAlert()
			end
		end

	elseif cmd == "DRUMCALL" then
		if self:IsDrummer(self.player) then
			self:ShowDrumsAlert()
		end
	elseif cmd == "DRUMSYNC" then
		self:InitRaidCooldowns()
		local list, caller = strsplit("|", rest or "")
		local drums = ShamanPower_RaidCooldowns.drums
		for k in pairs(drums.drummers) do drums.drummers[k] = nil end
		if list and list ~= "" then
			for pair in string.gmatch(list, "[^,]+") do
				local group, name = strsplit(":", pair)
				if group and name then drums.drummers[tonumber(group) or group] = name end
			end
		end
		drums.caller = (caller and caller ~= "") and caller or nil
		if self.raidCooldownPanel and self.raidCooldownPanel:IsShown() then
			self:UpdateRaidCooldownPanel()
		end
		self:UpdateCallerButtons()
	elseif cmd == "MTSYNC" then
		-- Sync MT assignments from raid leader
		self:InitRaidCooldowns()
		local mt = ShamanPower_RaidCooldowns.manatide
		-- Clear existing
		for k in pairs(mt) do mt[k] = nil end
		-- Parse new assignments
		if rest and rest ~= "" then
			for pair in string.gmatch(rest, "[^,]+") do
				local shamanName, callerName = strsplit(":", pair)
				if shamanName and callerName then
					mt[shamanName] = {caller = callerName}
				end
			end
		end

		if self.raidCooldownPanel and self.raidCooldownPanel:IsShown() then
			self:UpdateRaidCooldownPanel()
		end
		self:UpdateCallerButtons()
	end
end

-- Register slash command
SLASH_SPRAID1 = "/spraid"
SlashCmdList["SPRAID"] = function(msg)
	SP:ToggleRaidCooldownPanel()
end

-- ============================================================================
-- FLOATING CALLER BUTTONS
-- Shows buttons on screen for assigned callers to quickly call BL/MT
-- ============================================================================

function SP:CreateCallerButtonFrame()
	if self.callerButtonFrame then return self.callerButtonFrame end

	local frame = CreateFrame("Frame", "ShamanPowerCallerButtons", UIParent, "BackdropTemplate")
	frame:SetSize(100, 60)
	frame:SetPoint("CENTER", UIParent, "CENTER", 200, 200)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) if self:IsMovable() then self:StartMoving() end end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- Save position
		local point, _, relPoint, x, y = self:GetPoint()
		if not ShamanPower_RaidCooldowns.callerButtonPos then
			ShamanPower_RaidCooldowns.callerButtonPos = {}
		end
		ShamanPower_RaidCooldowns.callerButtonPos.point = point
		ShamanPower_RaidCooldowns.callerButtonPos.relPoint = relPoint
		ShamanPower_RaidCooldowns.callerButtonPos.x = x
		ShamanPower_RaidCooldowns.callerButtonPos.y = y
	end)
	frame:SetFrameStrata("HIGH")
	frame:Hide()

	SP:ApplyPanelBackdrop(frame)

	-- Heroism/Bloodlust button
	local faction = UnitFactionGroup("player")
	local blIcon = (faction == "Alliance") and "Interface\\Icons\\Ability_Shaman_Heroism" or "Interface\\Icons\\Spell_Nature_Bloodlust"

	local blBtn = CreateFrame("Button", "ShamanPowerCallerBLBtn", frame)
	blBtn:SetSize(40, 40)
	blBtn:SetPoint("TOPLEFT", 8, -8)

	-- Icon texture (inset from border)
	local blIconTex = blBtn:CreateTexture(nil, "ARTWORK")
	blIconTex:SetPoint("TOPLEFT", 3, -3)
	blIconTex:SetPoint("BOTTOMRIGHT", -3, 3)
	blIconTex:SetTexture(blIcon)
	blIconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	blBtn.icon = blIconTex

	-- Orange border for BL button (4 edge textures)
	local borderSize = 3
	local borderColor = {1, 0.5, 0, 1}  -- Orange

	local blBorderTop = blBtn:CreateTexture(nil, "BORDER")
	blBorderTop:SetPoint("TOPLEFT", 0, 0)
	blBorderTop:SetPoint("TOPRIGHT", 0, 0)
	blBorderTop:SetHeight(borderSize)
	blBorderTop:SetColorTexture(unpack(borderColor))

	local blBorderBottom = blBtn:CreateTexture(nil, "BORDER")
	blBorderBottom:SetPoint("BOTTOMLEFT", 0, 0)
	blBorderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
	blBorderBottom:SetHeight(borderSize)
	blBorderBottom:SetColorTexture(unpack(borderColor))

	local blBorderLeft = blBtn:CreateTexture(nil, "BORDER")
	blBorderLeft:SetPoint("TOPLEFT", 0, 0)
	blBorderLeft:SetPoint("BOTTOMLEFT", 0, 0)
	blBorderLeft:SetWidth(borderSize)
	blBorderLeft:SetColorTexture(unpack(borderColor))

	local blBorderRight = blBtn:CreateTexture(nil, "BORDER")
	blBorderRight:SetPoint("TOPRIGHT", 0, 0)
	blBorderRight:SetPoint("BOTTOMRIGHT", 0, 0)
	blBorderRight:SetWidth(borderSize)
	blBorderRight:SetColorTexture(unpack(borderColor))

	local blHighlight = blBtn:CreateTexture(nil, "HIGHLIGHT")
	blHighlight:SetAllPoints(blIconTex)
	blHighlight:SetColorTexture(1, 1, 1, 0.3)

	blBtn:SetScript("OnClick", function(self)
		if SP.raidCDDemoActive then SP:RaidCDDemoClick("bl", self) else SP:CallBloodlust() end
	end)
	blBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local name = (UnitFactionGroup("player") == "Alliance") and "Heroism" or "Bloodlust"
		GameTooltip:SetText("Call " .. name)
		local target = SP:GetBloodlustTarget()
		if target then
			GameTooltip:AddLine("Will call: " .. target, 0, 1, 0)
		end
		GameTooltip:Show()
	end)
	blBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Name label under BL button (shows who will use BL)
	local blNameLabel = blBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	SP:AdoptSPFont(blNameLabel, "labels")   -- template font = the design; follows the Fonts settings
	blNameLabel:SetPoint("TOP", blBtn, "BOTTOM", 0, -2)
	blNameLabel:SetText("")
	blBtn.nameLabel = blNameLabel

	frame.blBtn = blBtn

	-- Drums button (shown by UpdateCallerButtons when the player may call)
	local drumBtn = CreateFrame("Button", "ShamanPowerCallerDrumBtn", frame)
	drumBtn:SetSize(40, 40)
	drumBtn:SetPoint("TOPLEFT", 8, -8)
	local drumIcon = drumBtn:CreateTexture(nil, "ARTWORK")
	drumIcon:SetPoint("TOPLEFT", 3, -3)
	drumIcon:SetPoint("BOTTOMRIGHT", -3, 3)
	drumIcon:SetTexture(DRUMS_ICON)
	drumIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	drumBtn.icon = drumIcon
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local t = drumBtn:CreateTexture(nil, "BORDER")
		t:SetColorTexture(0.9, 0.65, 0.2, 1)
		if side == "TOP" or side == "BOTTOM" then
			t:SetHeight(3); t:SetPoint(side .. "LEFT", 0, 0); t:SetPoint(side .. "RIGHT", 0, 0)
		else
			t:SetWidth(3); t:SetPoint("TOP" .. side, 0, 0); t:SetPoint("BOTTOM" .. side, 0, 0)
		end
	end
	local drumHl = drumBtn:CreateTexture(nil, "HIGHLIGHT")
	drumHl:SetAllPoints(drumIcon)
	drumHl:SetColorTexture(1, 1, 1, 0.3)
	drumBtn:SetScript("OnClick", function(self)
		if SP.raidCDDemoActive then SP:RaidCDDemoClick("drums", self) else SP:CallDrums() end
	end)
	drumBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Call Drums of Battle")
		local d = SP:GetDrummers()
		GameTooltip:AddLine(#d > 0 and ("Drummers: " .. table.concat(d, ", ")) or "No drummers assigned", 0.9, 0.7, 0.3, true)
		GameTooltip:Show()
	end)
	drumBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local drumLabel = drumBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	SP:AdoptSPFont(drumLabel, "labels")
	drumLabel:SetPoint("TOP", drumBtn, "BOTTOM", 0, -2)
	drumLabel:SetText("")
	drumBtn.nameLabel = drumLabel
	drumBtn:Hide()
	frame.drumBtn = drumBtn

	-- Container for MT buttons (can have multiple)
	frame.mtButtons = {}

	-- Enable/disable caller button systems based on visibility
	frame:HookScript("OnShow", function()
		SP:StartCallerCooldownTracking()
	end)
	frame:HookScript("OnHide", function()
		SP:DisableCallerCooldownTracking()
		SP:DisableUpdateSubsystem("callerButtons")
	end)

	-- Settings button (scale / opacity / hide frame) in the corner.
	local cog = CreateFrame("Button", nil, frame)
	cog:SetSize(12, 12)
	cog:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
	SP:StyleSettingsButton(cog)
	cog:SetScript("OnClick", function() SP:OpenFrameSettings("raidcd", frame) end)
	cog:HookScript("OnEnter", function(self)
		if not SP.opt.ShowTooltips then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Settings")
		GameTooltip:Show()
	end)
	cog:HookScript("OnLeave", function() GameTooltip:Hide() end)
	frame.cogBtn = cog

	self.callerButtonFrame = frame
	self:UpdateCallerButtonFrameStyle()

	-- Apply the saved scale before the saved offsets (they are in frame units).
	frame:SetScale(self.opt.raidCDButtonScale or 1.0)

	-- Restore saved position
	if ShamanPower_RaidCooldowns and ShamanPower_RaidCooldowns.callerButtonPos then
		local pos = ShamanPower_RaidCooldowns.callerButtonPos
		frame:ClearAllPoints()
		frame:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 200, pos.y or 200)
	end

	return frame
end

function SP:BuildCallerMTButton(frame, i, shamanName, xOffset)
	local borderSize = 3
	local mtBorderColor = {0.2, 0.6, 1, 1}  -- Blue

	local mtBtn = CreateFrame("Button", "ShamanPowerCallerMTBtn" .. i, frame)
	mtBtn:SetSize(40, 40)
	mtBtn:SetPoint("TOPLEFT", xOffset, -8)

	-- Icon texture (inset from border)
	local mtIconTex = mtBtn:CreateTexture(nil, "ARTWORK")
	mtIconTex:SetPoint("TOPLEFT", 3, -3)
	mtIconTex:SetPoint("BOTTOMRIGHT", -3, 3)
	mtIconTex:SetTexture("Interface\\Icons\\Spell_Frost_SummonWaterElemental")
	mtIconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	mtBtn.icon = mtIconTex

	-- Blue border for MT button (4 edge textures)
	local mtBorderTop = mtBtn:CreateTexture(nil, "BORDER")
	mtBorderTop:SetPoint("TOPLEFT", 0, 0)
	mtBorderTop:SetPoint("TOPRIGHT", 0, 0)
	mtBorderTop:SetHeight(borderSize)
	mtBorderTop:SetColorTexture(unpack(mtBorderColor))

	local mtBorderBottom = mtBtn:CreateTexture(nil, "BORDER")
	mtBorderBottom:SetPoint("BOTTOMLEFT", 0, 0)
	mtBorderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
	mtBorderBottom:SetHeight(borderSize)
	mtBorderBottom:SetColorTexture(unpack(mtBorderColor))

	local mtBorderLeft = mtBtn:CreateTexture(nil, "BORDER")
	mtBorderLeft:SetPoint("TOPLEFT", 0, 0)
	mtBorderLeft:SetPoint("BOTTOMLEFT", 0, 0)
	mtBorderLeft:SetWidth(borderSize)
	mtBorderLeft:SetColorTexture(unpack(mtBorderColor))

	local mtBorderRight = mtBtn:CreateTexture(nil, "BORDER")
	mtBorderRight:SetPoint("TOPRIGHT", 0, 0)
	mtBorderRight:SetPoint("BOTTOMRIGHT", 0, 0)
	mtBorderRight:SetWidth(borderSize)
	mtBorderRight:SetColorTexture(unpack(mtBorderColor))

	local mtHighlight = mtBtn:CreateTexture(nil, "HIGHLIGHT")
	mtHighlight:SetAllPoints(mtIconTex)
	mtHighlight:SetColorTexture(1, 1, 1, 0.3)

	mtBtn.shamanName = shamanName
	mtBtn:SetScript("OnClick", function(self)
		if SP.raidCDDemoActive then SP:RaidCDDemoClick("mt", self) else SP:CallManaTideForShaman(self.shamanName) end
	end)
	mtBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Call Mana Tide")
		GameTooltip:AddLine("From: " .. self.shamanName, 0, 0.7, 1)
		if callerRequestEstimates then
			_G.GameTooltip:AddLine("Request-based cooldowns are estimates; casts are not confirmed.", 1, 0.8, 0.2, true)
		end
		GameTooltip:Show()
	end)
	mtBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Name label under MT button (shows shaman name)
	local mtNameLabel = mtBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	SP:AdoptSPFont(mtNameLabel, "labels")
	mtNameLabel:SetPoint("TOP", mtBtn, "BOTTOM", 0, -2)
	mtNameLabel:SetText(shamanName)
	mtBtn.nameLabel = mtNameLabel

	return mtBtn
end

function SP:UpdateCallerButtons()
	if self.raidCDDemoActive then return end
	self:InitRaidCooldowns()

	-- Don't show caller buttons when not in a group (or in Windfury-only mode)
	if GetNumGroupMembers() == 0 or (self.WindfuryOnly and self:WindfuryOnly()) then
		if self.callerButtonFrame then
			self.callerButtonFrame:Hide()
		end
		self:DisableCallerCooldownTracking()
		self:DisableUpdateSubsystem("callerButtons")
		return
	end

	local playerName = self.player
	local bl = ShamanPower_RaidCooldowns.bloodlust
	local mt = ShamanPower_RaidCooldowns.manatide
	local drums = ShamanPower_RaidCooldowns.drums or { drummers = {} }
	local drummers = self:GetDrummers()
	local isDrumsCaller = HasDrums() and drums.caller and (self:CanAssignRaidCooldowns() or drums.caller == playerName)
	local showDrumsButton = isDrumsCaller and #drummers > 0

	-- Check if player is a BL caller or MT caller for any shaman
	-- Only consider BL callable if there's a caller assigned AND (player is RL/assist or is the caller)
	local isBLCaller = HasBloodlust() and bl.caller and (self:CanAssignRaidCooldowns() or bl.caller == playerName)
	local mtCallsFor = {}

	-- Check if player is caller for any shaman's MT
	for shamanName, data in pairs(mt) do
		if data.caller == playerName then
			table.insert(mtCallsFor, shamanName)
		end
	end

	-- Also show if RL/assist (they can call anything that has a caller assigned)
	if self:CanAssignRaidCooldowns() then
		-- Get all MT shamans for RL/assist, but only if they have a caller assigned
		local mtShamans = self:GetManaTideShamans()
		for _, info in ipairs(mtShamans) do
			-- Only add if this shaman has a caller assigned
			if mt[info.name] and mt[info.name].caller then
				local found = false
				for _, name in ipairs(mtCallsFor) do
					if name == info.name then found = true break end
				end
				if not found then
					table.insert(mtCallsFor, info.name)
				end
			end
		end
	end

	-- Determine if buttons will actually be shown
	local showBLButton = isBLCaller and (bl.primary or bl.backup1 or bl.backup2)
	local showFrame = showBLButton or #mtCallsFor > 0 or showDrumsButton

	if not showFrame then
		if self.callerButtonFrame then
			self.callerButtonFrame:Hide()
		end
		self:DisableCallerCooldownTracking()
		self:DisableUpdateSubsystem("callerButtons")
		return
	end

	local frame = self:CreateCallerButtonFrame()

	-- Show/hide BL button
	if showBLButton then
		frame.blBtn:Show()
	else
		frame.blBtn:Hide()
	end

	-- Clear old MT buttons
	for _, btn in ipairs(frame.mtButtons) do
		btn:Hide()
	end
	frame.mtButtons = {}

	-- Create MT buttons
	local xOffset = isBLCaller and (bl.primary or bl.backup1 or bl.backup2) and 52 or 8
	for i, shamanName in ipairs(mtCallsFor) do
		local mtBtn = self:BuildCallerMTButton(frame, i, shamanName, xOffset)
		table.insert(frame.mtButtons, mtBtn)
		xOffset = xOffset + 44
	end

	-- Drums button after the Mana Tide buttons
	if showDrumsButton and frame.drumBtn then
		frame.drumBtn:ClearAllPoints()
		frame.drumBtn:SetPoint("TOPLEFT", xOffset, -8)
		frame.drumBtn.nameLabel:SetText(#drummers == 1 and drummers[1] or (#drummers .. " drummers"))
		frame.drumBtn:Show()
		xOffset = xOffset + 44
	elseif frame.drumBtn then
		frame.drumBtn:Hide()
	end

	-- Update BL button's name label with the active target
	if frame.blBtn and frame.blBtn.nameLabel then
		local activeTarget = self:GetBloodlustTarget()
		if activeTarget then
			frame.blBtn.nameLabel:SetText(activeTarget)
		else
			frame.blBtn.nameLabel:SetText("")
		end
	end

	-- Resize frame based on buttons (taller to fit name labels)
	local numButtons = (isBLCaller and (bl.primary or bl.backup1 or bl.backup2) and 1 or 0) + #mtCallsFor + (showDrumsButton and 1 or 0)
	local width = math.max(60, numButtons * 44 + 16)
	frame:SetSize(width, 62)  -- 40 button + 2 gap + 12 text + 8 padding

	frame:Show()
	-- Icon-only: new Mana Tide buttons at an unchanged size fire nothing the
	-- hover-only settings button hears, so have the core hook them now.
	if self.opt.raidCDButtonHideFrame then self:SetSettingsButtonHoverOnly(frame, frame.cogBtn, true) end

	-- Apply scale and opacity settings
	self:UpdateCallerButtonScale()
	self:UpdateCallerButtonOpacity()

	-- Start cooldown tracking update
	self:StartCallerCooldownTracking()
end

-- ============================================================================
-- CALLER BUTTON COOLDOWN TRACKING
-- Tracks when BL/MT are used and shows cooldown on caller buttons
-- ============================================================================

SP.callerCooldowns = {}  -- {[shamanName] = {bl = {start, duration}, mt = {start, duration}}}

-- Cooldown durations
local BL_COOLDOWN = 600  -- 10 minutes
local MT_COOLDOWN = 300  -- 5 minutes

-- UNVERIFIED: a request is not a confirmed cast. These local estimates are
-- never persisted as observed cooldowns, and do not read another unit's casts.
function SP:RecordManaTideRequest(shamanName)
	if not callerRequestEstimates then return end
	if _G.issecretvalue and _G.issecretvalue(shamanName) then return end
	if type(shamanName) ~= "string" then return end
	self.callerCooldowns[shamanName] = self.callerCooldowns[shamanName] or {}
	self.callerCooldowns[shamanName].mt = { start = _G.GetTime(), duration = MT_COOLDOWN }
end

local function HasLiveCallerCooldown(self, now)
	for _, cooldowns in pairs(self.callerCooldowns) do
		for _, cooldown in pairs(cooldowns) do
			if cooldown.start + cooldown.duration > now then return true end
		end
	end
	return false
end

-- Track the shamans' Bloodlust / Heroism / Mana Tide casts. This used to read
-- the whole combat log (thousands of events a second in a raid) to find a few
-- shaman casts; it now listens to UNIT_SPELLCAST_SUCCEEDED from the shamans'
-- own unit tokens only: one small frame per shaman in the group, rebuilt once
-- the roster settles, and nothing registered while the caller buttons are hidden.
local castFrames = {}     -- pooled frames, one per watched shaman unit
local rosterHooked = false

local function watchUnit(i, unit, alias)
	local f = castFrames[i]
	if not f then
		f = CreateFrame("Frame")
		if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(f, "Raid Cooldowns (shaman casts)") end
		f:SetScript("OnEvent", function(_, _, u, _, spellID) SP:OnShamanCooldownCast(u, spellID) end)
		castFrames[i] = f
	end
	f:UnregisterAllEvents()
	if f.RegisterUnitEvent then
		-- also the unit's other name: in a raid your own casts may arrive as "player"
		-- and your subgroup's as "partyN" rather than their raid token
		if alias then f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit, alias)
		else f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit) end
	end
end

local function unwatchAll()
	for _, f in ipairs(castFrames) do f:UnregisterAllEvents() end
end

-- every shaman in the group (the player included), by the tokens this client uses
local function rebuildWatchedShamans()
	unwatchAll()
	-- WoW: Forever: other players' casts are secret whenever a restriction is on
	-- (combat, instances, PvP matches), so only your own casts (never secret) are
	-- watched there; the others' buttons keep the request estimates.
	if SPCompat and SPCompat.secretsRegime then
		if select(2, UnitClass("player")) == "SHAMAN" then watchUnit(1, "player") end
		return
	end
	local n = 0
	local function aliasOf(unit)
		if not IsInRaid() then return nil end
		if UnitIsUnit(unit, "player") then return "player" end
		for k = 1, 4 do if UnitIsUnit(unit, "party" .. k) then return "party" .. k end end
		return nil
	end
	local function consider(unit)
		if UnitExists(unit) and select(2, UnitClass(unit)) == "SHAMAN" then
			n = n + 1
			watchUnit(n, unit, aliasOf(unit))
		end
	end
	if IsInRaid() then
		for i = 1, 40 do consider("raid" .. i) end
	else
		consider("player")
		for i = 1, 4 do consider("party" .. i) end
	end
end

function SP:SetupCallerCooldownTracking()
	if rosterHooked then return end
	rosterHooked = true
	-- The core's one pass a second after the roster settles (a raid forming fires
	-- dozens of GROUP_ROSTER_UPDATEs), not every raw event.
	hooksecurefunc(self, "OnRosterSettled", function()
		if SP.callerCooldownTrackingEnabled then rebuildWatchedShamans() end
	end)
end

-- Enable cast tracking (called when caller buttons are shown)
function SP:EnableCallerCooldownTracking()
	self:SetupCallerCooldownTracking()
	if not self.callerCooldownTrackingEnabled then
		rebuildWatchedShamans()
		self.callerCooldownTrackingEnabled = true
	end
end

-- Disable cast tracking (called when caller buttons are hidden)
function SP:DisableCallerCooldownTracking()
	if self.callerCooldownTrackingEnabled then
		unwatchAll()
		self.callerCooldownTrackingEnabled = false
	end
end

-- A watched shaman cast something: Bloodlust / Heroism or Mana Tide start that
-- shaman's cooldown on the caller buttons.
function SP:OnShamanCooldownCast(unit, spellID)
	if type(spellID) ~= "number" or (issecretvalue and (issecretvalue(spellID) or issecretvalue(unit))) then return end
	local cdType, duration
	if spellID == 2825 or spellID == 32182 then
		cdType, duration = "bl", BL_COOLDOWN
	elseif spellID == 16190 then
		cdType, duration = "mt", MT_COOLDOWN
	else
		return
	end
	local sourceName = UnitName(unit)
	if not sourceName or (issecretvalue and issecretvalue(sourceName)) then return end
	sourceName = self:RemoveRealmName(sourceName)
	if not self.callerCooldowns[sourceName] then
		self.callerCooldowns[sourceName] = {}
	end
	self.callerCooldowns[sourceName][cdType] = {
		start = GetTime(),
		duration = duration
	}
	-- Save to SavedVariables (use time() for persistence across reloads)
	self:SaveCallerCooldown(sourceName, cdType, duration)
	-- Also clear the alert on this shaman's cooldown bar button
	if sourceName == self.player then
		if cdType == "bl" then
			local blSpellID = (UnitFactionGroup("player") == "Alliance") and 32182 or 2825
			self:RemoveCooldownButtonAlert(blSpellID)
		else
			self:RemoveCooldownButtonAlert(16190)
		end
	end
	-- a cooldown to count down: wake the caller buttons' refresh
	self:StartCallerCooldownTracking()
end

-- Save cooldown to SavedVariables for persistence across reloads
function SP:SaveCallerCooldown(shamanName, cdType, duration)
	if not ShamanPower_RaidCooldowns.cooldownTimes then
		ShamanPower_RaidCooldowns.cooldownTimes = {}
	end
	if not ShamanPower_RaidCooldowns.cooldownTimes[shamanName] then
		ShamanPower_RaidCooldowns.cooldownTimes[shamanName] = {}
	end
	-- Store using time() (Unix epoch) so it persists across reloads
	ShamanPower_RaidCooldowns.cooldownTimes[shamanName][cdType] = {
		timestamp = time(),
		duration = duration
	}
end

-- Restore cooldowns from SavedVariables on login/reload
function SP:RestoreCallerCooldowns()
	if not ShamanPower_RaidCooldowns or not ShamanPower_RaidCooldowns.cooldownTimes then
		return
	end

	local now = time()
	local gameNow = GetTime()

	for shamanName, cds in pairs(ShamanPower_RaidCooldowns.cooldownTimes) do
		if not self.callerCooldowns[shamanName] then
			self.callerCooldowns[shamanName] = {}
		end

		for cdType, cdData in pairs(cds) do
			local elapsed = now - cdData.timestamp
			local remaining = cdData.duration - elapsed

			if remaining > 0 then
				-- Cooldown still active, restore it
				-- Calculate what GetTime() would have been when it started
				local adjustedStart = gameNow - elapsed
				self.callerCooldowns[shamanName][cdType] = {
					start = adjustedStart,
					duration = cdData.duration
				}
			else
				-- Cooldown expired, clear it
				ShamanPower_RaidCooldowns.cooldownTimes[shamanName][cdType] = nil
			end
		end
	end
	self:UpdateCallerButtonCooldowns()
	self:StartCallerCooldownTracking()
end

-- Caller buttons shown: casts are watched (events only) the whole time, and the
-- 0.2 s refresh runs only while a button has a cooldown to count down. Whatever
-- starts one (a cast, a request, a restore, a demo click) calls this to wake it;
-- UpdateCallerButtonCooldowns puts it back to sleep when the last one ends.
function SP:StartCallerCooldownTracking()
	local frame = self.callerButtonFrame
	if not frame then return end

	-- Register caller button updates with consolidated update system (5fps)
	if not self.updateSystem.subsystems["callerButtons"] then
		self:RegisterUpdateSubsystem("callerButtons", 0.2, function()
			SP:UpdateCallerButtonCooldowns()
		end)
	end
	if not frame:IsShown() then
		self:DisableCallerCooldownTracking()
		self:DisableUpdateSubsystem("callerButtons")
		return
	end
	self:EnableCallerCooldownTracking()
	-- the settings sample's cooldowns live in callerCooldowns too, so this covers them
	if HasLiveCallerCooldown(self, _G.GetTime()) then
		self:EnableUpdateSubsystem("callerButtons")
	else
		self:DisableUpdateSubsystem("callerButtons")
	end
end

-- Update cooldown displays on caller buttons
function SP:UpdateCallerButtonCooldowns()
	local frame = self.callerButtonFrame
	if not frame or not frame:IsShown() then return end

	local now = GetTime()

	-- Update BL button cooldown
	if frame.blBtn and frame.blBtn:IsShown() then
		local activeTarget = self.raidCDDemoActive and DEMO_BL_KEY or self:GetBloodlustTarget()
		local cdInfo = activeTarget and self.callerCooldowns[activeTarget] and self.callerCooldowns[activeTarget].bl

		if cdInfo then
			local elapsed = now - cdInfo.start
			local remaining = cdInfo.duration - elapsed

			if remaining > 0 then
				-- Show cooldown
				self:SetCallerButtonCooldown(frame.blBtn, cdInfo.start, cdInfo.duration)
			else
				-- Cooldown done
				self:ClearCallerButtonCooldown(frame.blBtn)
				self.callerCooldowns[activeTarget].bl = nil
			end
		else
			self:ClearCallerButtonCooldown(frame.blBtn)
		end
	end

	-- Update MT button cooldowns
	for _, mtBtn in ipairs(frame.mtButtons or {}) do
		if mtBtn:IsShown() then
			local shamanName = mtBtn.shamanName
			local cdInfo = shamanName and self.callerCooldowns[shamanName] and self.callerCooldowns[shamanName].mt

			if cdInfo then
				local elapsed = now - cdInfo.start
				local remaining = cdInfo.duration - elapsed

				if remaining > 0 then
					self:SetCallerButtonCooldown(mtBtn, cdInfo.start, cdInfo.duration)
				else
					self:ClearCallerButtonCooldown(mtBtn)
					self.callerCooldowns[shamanName].mt = nil
				end
			else
				self:ClearCallerButtonCooldown(mtBtn)
			end
		end
	end
	if not HasLiveCallerCooldown(self, now) then
		self:DisableUpdateSubsystem("callerButtons")
	end
end

-- Set cooldown display on a caller button
function SP:SetCallerButtonCooldown(btn, start, duration)
	-- Check if animation is enabled
	if self.opt.raidCDShowButtonAnimation == false then
		return
	end

	-- Create cooldown frame if needed
	if not btn.cooldownFrame then
		local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
		cd:SetAllPoints(btn.icon or btn)
		cd:SetDrawEdge(false)
		cd:SetDrawBling(false)
		cd:SetDrawSwipe(true)
		cd:SetSwipeColor(0, 0, 0, 0.8)
		btn.cooldownFrame = cd
	end

	local cd = btn.cooldownFrame
	cd:SetCooldown(start, duration)
	-- the game draws the countdown numbers (Show Numbers for Cooldowns): its own
	-- font is the design, and they follow the Fonts settings' timer font. Taken once
	-- the string has a font, which may be only after a countdown starts (a string
	-- with none would get a made-up size); until then each refresh tries again.
	if not cd.spFontAdopted then
		local ok, fs = pcall(cd.GetCountdownFontString, cd)
		if ok and fs and fs:GetFont() then
			SP:AdoptSPFont(fs, "timers")
			cd.spFontAdopted = true
		end
	end

	-- Desaturate the icon
	if btn.icon then
		btn.icon:SetDesaturated(true)
	end
end

-- Clear cooldown display on a caller button
function SP:ClearCallerButtonCooldown(btn)
	if btn.cooldownFrame then
		btn.cooldownFrame:Clear()
	end

	-- Restore icon color
	if btn.icon then
		btn.icon:SetDesaturated(false)
	end
end

-- Update opacity of caller button frame
-- Panel or icons-only, per opt.raidCDButtonHideFrame.
function SP:UpdateCallerButtonFrameStyle()
	local frame = self.callerButtonFrame
	if not frame then return end
	if self.opt.raidCDButtonHideFrame then
		frame:SetBackdrop(nil)
		self:SetSettingsButtonHoverOnly(frame, frame.cogBtn, true)
	else
		self:ApplyPanelBackdrop(frame)
		self:SetSettingsButtonHoverOnly(frame, frame.cogBtn, false)
	end
end

function SP:UpdateCallerButtonOpacity()
	if self.callerButtonFrame then
		local opacity = self.opt.raidCDButtonOpacity or 1.0
		self.callerButtonFrame:SetAlpha(opacity)
	end
end

-- Update scale of caller button frame
function SP:UpdateCallerButtonScale()
	local frame = self.callerButtonFrame
	if frame then
		local scale = self.opt.raidCDButtonScale or 1.0
		-- Only compensate on an actual change; the creation path already
		-- applied the saved scale before restoring the saved offsets.
		if math.abs(frame:GetScale() - scale) > 0.001 then
			self:SetFrameScaleKeepCenter(frame, scale)
			local point, _, relPoint, x, y = frame:GetPoint()
			if point then
				ShamanPower_RaidCooldowns.callerButtonPos = { point = point, relPoint = relPoint, x = x, y = y }
			end
		end
	end
end

-- ============================================================================
-- SETUP WIZARD PREVIEW
-- ============================================================================

-- Fill the caller-button frame with representative sample data so the setup
-- wizard can show what the callers look like without a real group/assignments.
-- Builds from local fake data only: no comms, no SavedVar writes, no timers.
-- A sample caller button pressed in the settings pane (or while unlocked)
-- shows the assigned player's REAL centre-screen alert - icon, text, sound and
-- volume exactly as set on the Raid Cooldowns page - and puts the button on
-- the same cooldown sweep a real call would (Show Button Animation applies).
-- So the page's options can be judged without a raid. The tutorial's Raid
-- Cooldowns step has its own mock and is not involved.
function SP:RaidCDDemoClick(kind, btn)
	if kind == "bl" then
		local faction = UnitFactionGroup("player")
		local icon = (faction == "Alliance") and "Interface\\Icons\\Ability_Shaman_Heroism" or "Interface\\Icons\\Spell_Nature_Bloodlust"
		self:ShowCenterScreenAlert(icon, "USE " .. ((faction == "Alliance") and "HEROISM" or "BLOODLUST") .. " NOW!")
		self.callerCooldowns[DEMO_BL_KEY] = self.callerCooldowns[DEMO_BL_KEY] or {}
		self.callerCooldowns[DEMO_BL_KEY].bl = { start = GetTime(), duration = DEMO_CD.bl }
	elseif kind == "mt" then
		self:ShowCenterScreenAlert("Interface\\Icons\\Spell_Frost_SummonWaterElemental", "USE MANA TIDE NOW!")
		local name = btn and btn.shamanName
		if name then
			self.callerCooldowns[name] = self.callerCooldowns[name] or {}
			self.callerCooldowns[name].mt = { start = GetTime(), duration = DEMO_CD.mt }
		end
	elseif kind == "drums" then
		-- the real Drums button has no cooldown sweep either
		self:ShowDrumsAlert()
	end
	self:UpdateCallerButtonCooldowns()
	self:StartCallerCooldownTracking()   -- wakes the refresh for the sample sweep
end

function SP:RaidCDDemo(on)
	if on then
		self.raidCDDemoActive = true
		local frame = self:CreateCallerButtonFrame()
		if frame and frame.cogBtn then frame.cogBtn:Hide() end

		local xOffset, numButtons = 8, 0

		-- Sample Bloodlust/Heroism button (reuses the persistent BL button);
		-- a client without the spell never shows one
		if frame.blBtn then
			if HasBloodlust() then
				if frame.blBtn.nameLabel then frame.blBtn.nameLabel:SetText(DEMO_BL_TARGET) end
				frame.blBtn:Show()
				xOffset = xOffset + 44
				numButtons = numButtons + 1
			else
				frame.blBtn:Hide()
			end
		end

		-- Clear any existing MT buttons, then build sample ones
		for _, btn in ipairs(frame.mtButtons) do btn:Hide() end
		frame.mtButtons = {}

		local sampleMT = { "Group 1", "Group 3" }
		for i, name in ipairs(sampleMT) do
			-- Clickable: a press shows the sample alert (see RaidCDDemoClick)
			local mtBtn = self:BuildCallerMTButton(frame, i, name, xOffset)
			table.insert(frame.mtButtons, mtBtn)
			xOffset = xOffset + 44
			numButtons = numButtons + 1
		end

		-- Sample Drums button (reuses the persistent drum button)
		if frame.drumBtn then
			if HasDrums() then
				frame.drumBtn:ClearAllPoints()
				frame.drumBtn:SetPoint("TOPLEFT", xOffset, -8)
				if frame.drumBtn.nameLabel then frame.drumBtn.nameLabel:SetText("Kabum") end
				frame.drumBtn:Show()
				xOffset = xOffset + 44
				numButtons = numButtons + 1
			else
				frame.drumBtn:Hide()
			end
		end

		local width = math.max(60, numButtons * 44 + 16)
		frame:SetSize(width, 62)
		frame:Show()
		self:UpdateCallerButtonOpacity()
		-- one pass now: the refresh sleeps unless a cooldown is live, and the kept
		-- Bloodlust button may still be dimmed from a real one that ran out while hidden
		self:UpdateCallerButtonCooldowns()
		self:StartCallerCooldownTracking()
	else
		self.raidCDDemoActive = false
		local frame = self.callerButtonFrame
		if frame then
			for _, btn in ipairs(frame.mtButtons) do
				btn:Hide()
				-- sample names hold a space, so these are never a real shaman's
				if btn.shamanName then self.callerCooldowns[btn.shamanName] = nil end
				self:ClearCallerButtonCooldown(btn)
			end
			frame.mtButtons = {}
			if frame.blBtn then
				if frame.blBtn.nameLabel then frame.blBtn.nameLabel:SetText("") end
				self:ClearCallerButtonCooldown(frame.blBtn)
			end
			if frame.drumBtn then frame.drumBtn:Hide() end
			self.callerCooldowns[DEMO_BL_KEY] = nil
		end
		-- Let real data take over (hides the frame when solo / unassigned)
		self:UpdateCallerButtons()
	end
end

if ShamanPower.RegisterPreview then
	ShamanPower:RegisterPreview("raidcd", { frame = "ShamanPowerCallerButtons", demo = "SP:RaidCDDemo", pad = 24 })
end
