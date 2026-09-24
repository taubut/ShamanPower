-- ============================================================================
-- Cooldown Announce: tell the group when you use Mana Tide (or Bloodlust /
-- Heroism where the game has them), warn them shortly before it is back, answer
-- "tide?" in group chat with the time left, and show the Mana Tide call on your
-- own screen when a group member asks for it.
--
-- Everything is event driven: one C_Timer per cast for the "ready soon" line,
-- nothing polls. Every chat send is optional, off by default, and never fires
-- while the game has chat messaging locked down. Shamans only.
--
-- WoW: Forever hides party / raid chat from addons while
-- C_ChatInfo.InChatMessagingLockdown() is true (the event payload is secret),
-- and SendChatMessage is restricted then too: both are checked before use.
-- ============================================================================

local SP = ShamanPower
if not SP then return end
if select(2, UnitClass("player")) ~= "SHAMAN" then return end

local FOREVER = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
local GetCD = (SPCompat and SPCompat.GetSpellCooldown) or GetSpellCooldown
local secret = issecretvalue or function() return false end

-- The cooldowns we speak about, by name (every rank shares it). Bloodlust and
-- Heroism only where the client has them.
local SPELLS = {
	{ key = "manatide",  id = 16190, opt = "manaTide" },
	{ key = "bloodlust", id = 2825,  opt = "bloodlust", lust = true },
	{ key = "heroism",   id = 32182, opt = "bloodlust", lust = true },
}
local function hasLust()
	if SPCompat and SPCompat.HasBloodlust then return SPCompat.HasBloodlust() end
	return not FOREVER
end
local byName = {}
for _, s in ipairs(SPELLS) do
	s.name = GetSpellInfo(s.id)
	if s.name then byName[s.name] = s end
end
local MANA_TIDE = SPELLS[1]

local DEFAULTS = {
	announceUse = false,
	useText = "{spell} used!",
	announceSoon = false,
	soonSeconds = 30,
	soonText = "{spell} ready in {sec} s.",
	channel = "group",
	manaTide = true,
	bloodlust = true,
	reply = false,
	triggers = "tide, mana tide, mtt",
	replyReadyText = "{spell} is ready.",
	replyCooldownText = "{spell} ready in {sec} s.",
	replyThrottle = 10,
	localCall = false,
}

local function cfg()
	local o = SP.opt
	if not o then return DEFAULTS end
	if not o.announce then o.announce = {} end
	local a = o.announce
	for k, v in pairs(DEFAULTS) do
		if a[k] == nil then a[k] = v end
	end
	return a
end

local function fill(text, spell, sec)
	text = tostring(text or "")
	text = text:gsub("{spell}", spell or "")
	text = text:gsub("{sec}", sec and tostring(sec) or "")
	return text
end

-- ---------------------------------------------------------------------------
-- Chat out
-- ---------------------------------------------------------------------------
local function chatLocked()
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
		local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
		if ok and locked == true then return true end
	end
	return false
end

local function groupChannel()
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
	return nil
end

local function send(msg, channel)
	if not msg or msg == "" or not channel then return false end
	if chatLocked() then return false end
	local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	if not fn then return false end
	local ok = pcall(fn, msg, channel)
	return ok
end

local function announceChannel()
	-- the game only lets addons /say inside instances; the group is the default
	if cfg().channel == "say" then return "SAY" end
	return groupChannel()
end

-- ---------------------------------------------------------------------------
-- Time left on a cooldown, as plain numbers: the compat shim answers from its
-- own cast record while the game hides cooldowns (combat on Forever).
-- ---------------------------------------------------------------------------
local function remainingOn(spellName)
	if not spellName or not GetCD then return nil end
	local ok, start, duration = pcall(GetCD, spellName)
	if not ok or type(start) ~= "number" or type(duration) ~= "number" then return nil end
	if secret(start) or secret(duration) then return nil end
	if start <= 0 or duration <= 2.5 then return 0 end   -- ready (a GCD is not a cooldown)
	local left = start + duration - GetTime()
	if left < 0 then left = 0 end
	return left
end

local function knows(spell)
	if not spell or not spell.name then return false end
	if IsPlayerSpell and IsPlayerSpell(spell.id) then return true end
	return GetSpellInfo(spell.name) ~= nil   -- a name lookup finds any known rank
end

-- ---------------------------------------------------------------------------
-- Cast: "used" now, and one timer for "ready in N s"
-- ---------------------------------------------------------------------------
local soonGen = {}   -- [spell key] = generation; a newer cast cancels an older timer

local function baseLength(spellID)
	if not GetSpellBaseCooldown then return nil end
	local ok, ms = pcall(GetSpellBaseCooldown, spellID)
	if ok and type(ms) == "number" and not secret(ms) and ms > 2500 then return ms / 1000 end
	return nil
end

local function scheduleSoon(spell, castAt, spellID, gen, tries)
	local a = cfg()
	local lead = tonumber(a.soonSeconds) or 30
	local left = remainingOn(spell.name)
	if not left or left <= 0 then
		-- nothing readable yet (the cooldown lands just after the cast event): use the spell data
		local len = baseLength(spellID)
		if not len then return end
		left = castAt + len - GetTime()
	end
	if left <= lead + 1 then return end   -- a cooldown shorter than the warning: nothing to warn about
	C_Timer.After(left - lead, function()
		if soonGen[spell.key] ~= gen then return end
		local c = cfg()
		if not c.announceSoon then return end
		local now = remainingOn(spell.name)
		if now and now <= 0 then return end   -- reset early: it is already ready
		if now and now > lead + 1.5 and (tries or 0) < 3 then
			-- the real cooldown turned out longer than first read: try again at the right time
			scheduleSoon(spell, castAt, spellID, gen, (tries or 0) + 1)
			return
		end
		local sec = math.floor((now or lead) + 0.5)
		send(fill(c.soonText, spell.name, sec), announceChannel())
	end)
end

local function onCast(spellID)
	if type(spellID) ~= "number" or secret(spellID) then return end
	local name = GetSpellInfo(spellID)
	local spell = name and byName[name]
	if not spell then return end
	if spell.lust and not hasLust() then return end
	local a = cfg()
	if not a[spell.opt] then return end
	if a.announceUse then send(fill(a.useText, spell.name), announceChannel()) end
	if a.announceSoon then
		local castAt = GetTime()
		soonGen[spell.key] = (soonGen[spell.key] or 0) + 1
		local gen = soonGen[spell.key]
		-- a moment later, so the cooldown the cast started is readable (or recorded)
		C_Timer.After(0.3, function()
			if soonGen[spell.key] == gen then scheduleSoon(spell, castAt, spellID, gen, 0) end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Chat in: trigger words
-- ---------------------------------------------------------------------------
local CHAT_CHANNEL = {
	CHAT_MSG_PARTY = "PARTY", CHAT_MSG_PARTY_LEADER = "PARTY",
	CHAT_MSG_RAID = "RAID", CHAT_MSG_RAID_LEADER = "RAID",
	CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT", CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
}

local parsedFrom, parsedTriggers = nil, {}
local function triggers()
	local raw = cfg().triggers or ""
	if raw ~= parsedFrom then
		parsedFrom, parsedTriggers = raw, {}
		for word in raw:gmatch("[^,]+") do
			word = strtrim(word):lower()
			if word ~= "" then
				-- whole words only: "tide" matches "tide pls", never "tides" or "stride"
				parsedTriggers[#parsedTriggers + 1] = "%f[%w]" .. word:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1") .. "%f[%W]"
			end
		end
	end
	return parsedTriggers
end

local function mentionsTrigger(text)
	local lower = text:lower()
	for _, pattern in ipairs(triggers()) do
		if lower:find(pattern) then return true end
	end
	return false
end

local lastReplyAt, lastCallAt = 0, 0

local function onChat(event, text, sender)
	local a = cfg()
	if not (a.reply or a.localCall) then return end
	if chatLocked() then return end
	if type(text) ~= "string" or type(sender) ~= "string" or secret(text) or secret(sender) then return end
	local short = strsplit("-", sender)
	if short == UnitName("player") then return end   -- never answer yourself
	if not mentionsTrigger(text) then return end
	if not knows(MANA_TIDE) then return end
	local left = remainingOn(MANA_TIDE.name)
	local now = GetTime()
	if a.reply and now - lastReplyAt >= (tonumber(a.replyThrottle) or 10) then
		local msg
		if left and left > 0 then
			msg = fill(a.replyCooldownText, MANA_TIDE.name, math.ceil(left))
		else
			msg = fill(a.replyReadyText, MANA_TIDE.name)
		end
		if send(msg, CHAT_CHANNEL[event]) then lastReplyAt = now end
	end
	-- the Mana Tide call on your own screen, as if an assigned caller pressed the button
	if a.localCall and (not left or left <= 0) and now - lastCallAt >= 5 and SP.ShowManaTideAlert then
		lastCallAt = now
		pcall(SP.ShowManaTideAlert, SP)
	end
end

-- ---------------------------------------------------------------------------
-- Events: registered only while a feature that needs them is on
-- ---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, a1, a2, a3)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if a1 == "player" then onCast(a3) end
	elseif CHAT_CHANNEL[event] then
		onChat(event, a1, a2)
	elseif event == "PLAYER_LOGIN" then
		SP:UpdateAnnounceEvents()
	end
end)
ev:RegisterEvent("PLAYER_LOGIN")

function SP:UpdateAnnounceEvents()
	local a = cfg()
	if a.announceUse or a.announceSoon then
		ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	else
		ev:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	end
	for event in pairs(CHAT_CHANNEL) do
		if a.reply or a.localCall then ev:RegisterEvent(event) else ev:UnregisterEvent(event) end
	end
end

-- Shows every message with sample values in your own chat window only.
function SP:PreviewAnnounceMessages()
	local a = cfg()
	local mt = MANA_TIDE.name or "Mana Tide Totem"
	local lead = tonumber(a.soonSeconds) or 30
	local out = DEFAULT_CHAT_FRAME
	if not out then return end
	out:AddMessage("|cff0070ddShamanPower|r announce preview (only you see this):")
	out:AddMessage("  used: " .. fill(a.useText, mt))
	out:AddMessage("  ready soon: " .. fill(a.soonText, mt, lead))
	out:AddMessage("  reply, ready: " .. fill(a.replyReadyText, mt))
	out:AddMessage("  reply, cooling down: " .. fill(a.replyCooldownText, mt, 42))
	local list = {}
	for word in (a.triggers or ""):gmatch("[^,]+") do word = strtrim(word); if word ~= "" then list[#list + 1] = word end end
	out:AddMessage("  answers to: " .. (#list > 0 and table.concat(list, ", ") or "(no words set)"))
end

-- ---------------------------------------------------------------------------
-- Options: Modules > Cooldown Announce
-- ---------------------------------------------------------------------------
do
	local fluffy = SP.options and SP.options.args and SP.options.args.fluffy
	if fluffy and fluffy.args then
		local function get(key) return function() return cfg()[key] end end
		local function set(key) return function(_, v) cfg()[key] = v; SP:UpdateAnnounceEvents() end end
		local function textSet(key) return function(_, v)
			v = strtrim(v or "")
			if v == "" then v = DEFAULTS[key] end
			cfg()[key] = v
		end end
		local sendsOff = function() local a = cfg(); return not (a.announceUse or a.announceSoon) end
		fluffy.args.announce_section = {
			order = 18.5,
			name = "|cff0070ddCooldown Announce|r",
			type = "group",
			args = {
				forever_note = {
					order = 0.01, type = "description", width = "full",
					name = "|cffffa040In dungeons and raids the game may hide chat from addons; replies then only work in the open world. Announces are not sent while the game has chat locked down.|r",
					hidden = function() return not FOREVER end,
				},
				desc = {
					order = 0.1, type = "description", width = "full",
					name = "Tell your group when you use Mana Tide" .. (hasLust() and " or Bloodlust / Heroism" or "") .. ", warn them shortly before it is back, and answer when someone asks for it in chat. Everything here is off until you turn it on.",
				},
				hdr_announce = { order = 1, type = "header", name = "Announce to the Group" },
				announceUse = {
					order = 1.1, type = "toggle", width = "full", name = "Announce When I Use It",
					desc = "Say in group chat when you use one of the cooldowns below.",
					get = get("announceUse"), set = set("announceUse"),
				},
				useText = {
					order = 1.2, type = "input", width = "full", name = "Message",
					desc = "{spell} becomes the spell's name.",
					disabled = function() return not cfg().announceUse end,
					get = get("useText"), set = textSet("useText"),
				},
				announceSoon = {
					order = 1.3, type = "toggle", width = "full", name = "Announce Before It Is Ready",
					desc = "A set time before the cooldown is back, tell the group. Works in combat: the time comes from your own cast, not from anything the game hides.",
					get = get("announceSoon"), set = set("announceSoon"),
				},
				soonSeconds = {
					order = 1.4, type = "range", name = "Seconds Before", min = 5, max = 120, step = 5,
					disabled = function() return not cfg().announceSoon end,
					get = get("soonSeconds"), set = set("soonSeconds"),
				},
				soonText = {
					order = 1.5, type = "input", width = "full", name = "Message",
					desc = "{spell} becomes the spell's name, {sec} the seconds left.",
					disabled = function() return not cfg().announceSoon end,
					get = get("soonText"), set = textSet("soonText"),
				},
				channel = {
					order = 1.6, type = "select", name = "Where", width = 1.5,
					desc = "Group chat picks party, raid or instance chat by itself. The game only lets addons use /say inside instances.",
					values = { group = "Group chat", say = "Say (instances only)" },
					sorting = { "group", "say" },
					disabled = sendsOff,
					get = get("channel"), set = set("channel"),
				},
				manaTide = {
					order = 1.7, type = "toggle", name = "Mana Tide Totem", width = 1.2,
					disabled = sendsOff,
					get = get("manaTide"), set = set("manaTide"),
				},
				bloodlust = {
					order = 1.8, type = "toggle", name = "Bloodlust / Heroism", width = 1.2,
					hidden = function() return not hasLust() end,
					disabled = sendsOff,
					get = get("bloodlust"), set = set("bloodlust"),
				},
				hdr_reply = { order = 2, type = "header", name = "When Someone Asks" },
				reply = {
					order = 2.1, type = "toggle", width = "full", name = "Reply in Chat",
					desc = "When a group member's message has one of the words below, answer in the same chat with whether Mana Tide is ready or how long is left. At most one reply per the time set below.",
					get = get("reply"), set = set("reply"),
				},
				localCall = {
					order = 2.2, type = "toggle", width = "full", name = "Show the Mana Tide Call on My Screen",
					desc = "When a group member's message has one of the words below and Mana Tide is ready, show the same \"use Mana Tide\" alert a Raid Cooldowns caller's button shows, even if they are not an assigned caller. Only you see it.",
					get = get("localCall"), set = set("localCall"),
				},
				triggers = {
					order = 2.3, type = "input", width = "full", name = "Words to Listen For",
					desc = "Separated by commas. Whole words, any capitals: \"tide\" matches \"TIDE pls\" but not \"stride\".",
					disabled = function() local a = cfg(); return not (a.reply or a.localCall) end,
					get = get("triggers"), set = textSet("triggers"),
				},
				replyReadyText = {
					order = 2.4, type = "input", width = "full", name = "Reply When Ready",
					desc = "{spell} becomes the spell's name.",
					disabled = function() return not cfg().reply end,
					get = get("replyReadyText"), set = textSet("replyReadyText"),
				},
				replyCooldownText = {
					order = 2.5, type = "input", width = "full", name = "Reply When Cooling Down",
					desc = "{spell} becomes the spell's name, {sec} the seconds left.",
					disabled = function() return not cfg().reply end,
					get = get("replyCooldownText"), set = textSet("replyCooldownText"),
				},
				replyThrottle = {
					order = 2.6, type = "range", name = "Seconds Between Replies", min = 5, max = 60, step = 1,
					disabled = function() return not cfg().reply end,
					get = get("replyThrottle"), set = set("replyThrottle"),
				},
				preview = {
					order = 3, type = "execute", width = "full", name = "Preview My Messages",
					desc = "Prints every message with sample values in your own chat window. Nothing is sent.",
					func = function() SP:PreviewAnnounceMessages() end,
				},
			},
		}
	end
end
