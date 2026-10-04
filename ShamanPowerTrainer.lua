-- ============================================================================
-- Trainer Reminder (WoW: Forever): after a level-up, say which shaman spells
-- and ranks are waiting at the trainer; once at login, one summary line.
-- Forever characters all level from 1, so this is a levelling helper.
--
-- The table is Forever's trainer list by exact spell ID, read from Forever's own
-- game data (SkillLineAbility + SpellLevels, build 1.60.1.70205). What you know is
-- asked by spell ID too (this rank or a higher one, SPCompat.SpellRanks), never by
-- name. Runs only on the level-up and login events: nothing while you play.
-- ============================================================================

local SP = ShamanPower
if not SP then return end
if not SPCompat.FOREVER then return end
if select(2, UnitClass("player")) ~= "SHAMAN" then return end

-- [level] = { spellID, rank, ... }: each rank Forever's trainer teaches at that level, by its
-- exact spell ID (rank 0 = a spell without ranks). The comments only name them for reading.
local TRAINER = {
	[4] = { 8042, 1, 8071, 1 },
		-- Earth Shock 1, Stoneskin Totem 1
	[6] = { 2484, 0, 332, 2 },
		-- Earthbind Totem, Healing Wave 2
	[8] = { 8044, 2, 529, 2, 324, 1, 8018, 2, 5730, 1 },
		-- Earth Shock 2, Lightning Bolt 2, Lightning Shield 1, Rockbiter Weapon 2, Stoneclaw Totem 1
	[10] = { 8050, 1, 8024, 1, 3599, 1, 8075, 1 },
		-- Flame Shock 1, Flametongue Weapon 1, Searing Totem 1, Strength of Earth Totem 1
	[12] = { 2008, 1, 408341, 1, 547, 3, 370, 1 },
		-- Ancestral Spirit 1, Fire Nova 1, Healing Wave 3, Purge 1
	[14] = { 8045, 3, 548, 3, 8154, 2 },
		-- Earth Shock 3, Lightning Bolt 3, Stoneskin Totem 2
	[16] = { 526, 0, 325, 2, 8019, 3 },
		-- Cure Poison, Lightning Shield 2, Rockbiter Weapon 3
	[18] = { 8052, 2, 8027, 2, 913, 4, 6390, 2, 8143, 0 },
		-- Flame Shock 2, Flametongue Weapon 2, Healing Wave 4, Stoneclaw Totem 2, Tremor Totem
	[20] = { 66842, 0, 8056, 1, 8033, 1, 2645, 0, 5394, 1, 8004, 1, 915, 4, 6363, 2, 36936, 0 },
		-- Call of the Elements, Frost Shock 1, Frostbrand Weapon 1, Ghost Wolf, Healing Stream Totem 1, Lesser Healing Wave 1, Lightning Bolt 4, Searing Totem 2, Totemic Recall
	[22] = { 2870, 0, 408342, 2, 8166, 0, 437009, 0, 131, 0 },
		-- Cure Disease, Fire Nova 2, Poison Cleansing Totem, Totemic Projection, Water Breathing
	[24] = { 20609, 2, 8046, 4, 8181, 1, 939, 5, 905, 3, 10399, 4, 8155, 3, 8160, 2 },
		-- Ancestral Spirit 2, Earth Shock 4, Frost Resistance Totem 1, Healing Wave 5, Lightning Shield 3, Rockbiter Weapon 4, Stoneskin Totem 3, Strength of Earth Totem 2
	[26] = { 6196, 0, 8030, 3, 943, 5, 8190, 1, 5675, 1 },
		-- Far Sight, Flametongue Weapon 3, Lightning Bolt 5, Magma Totem 1, Mana Spring Totem 1
	[28] = { 8184, 1, 8053, 3, 8227, 1, 8038, 2, 8008, 2, 6391, 3, 546, 0 },
		-- Fire Resistance Totem 1, Flame Shock 3, Flametongue Totem 1, Frostbrand Weapon 2, Lesser Healing Wave 2, Stoneclaw Totem 3, Water Walking
	[30] = { 556, 0, 66843, 0, 8177, 0, 6375, 2, 10595, 1, 20608, 0, 6364, 3, 8232, 1 },
		-- Astral Recall, Call of the Ancestors, Grounding Totem, Healing Stream Totem 2, Nature Resistance Totem 1, Reincarnation, Searing Totem 3, Windfury Weapon 1
	[32] = { 421, 1, 408343, 3, 959, 6, 6041, 6, 945, 4, 8012, 2, 8512, 1 },
		-- Chain Lightning 1, Fire Nova 3, Healing Wave 6, Lightning Bolt 6, Lightning Shield 4, Purge 2, Windfury Totem 1
	[34] = { 8058, 2, 16314, 5, 6495, 0, 10406, 4 },
		-- Frost Shock 2, Rockbiter Weapon 5, Sentry Totem, Stoneskin Totem 4
	[36] = { 20610, 3, 10412, 5, 16339, 4, 8010, 3, 10585, 2, 10495, 2, 15107, 1 },
		-- Ancestral Spirit 3, Earth Shock 5, Flametongue Weapon 4, Lesser Healing Wave 3, Magma Totem 2, Mana Spring Totem 2, Windwall Totem 1
	[38] = { 8170, 0, 8249, 2, 10478, 2, 10456, 3, 10391, 7, 6392, 4, 8161, 3 },
		-- Disease Cleansing Totem, Flametongue Totem 2, Frost Resistance Totem 2, Frostbrand Weapon 3, Lightning Bolt 7, Stoneclaw Totem 4, Strength of Earth Totem 3
	[40] = { 66844, 0, 1064, 1, 930, 2, 10447, 4, 6377, 3, 8005, 7, 8134, 5, 6365, 4, 8235, 2 },
		-- Call of the Spirits, Chain Heal 1, Chain Lightning 2, Flame Shock 4, Healing Stream Totem 3, Healing Wave 7, Lightning Shield 5, Searing Totem 4, Windfury Weapon 2
	[42] = { 408344, 4, 10537, 2, 8835, 1, 10613, 2 },
		-- Fire Nova 4, Fire Resistance Totem 2, Grace of Air Totem 1, Windfury Totem 2
	[44] = { 10466, 4, 10392, 8, 10600, 2, 16315, 6, 10407, 5 },
		-- Lesser Healing Wave 4, Lightning Bolt 8, Nature Resistance Totem 2, Rockbiter Weapon 6, Stoneskin Totem 5
	[46] = { 10622, 2, 16341, 5, 10472, 3, 10586, 3, 10496, 3, 15111, 2 },
		-- Chain Heal 2, Flametongue Weapon 5, Frost Shock 3, Magma Totem 3, Mana Spring Totem 3, Windwall Totem 2
	[48] = { 20776, 4, 2860, 3, 10413, 6, 10526, 3, 16355, 4, 10395, 8, 10431, 6, 17354, 2, 10427, 5 },
		-- Ancestral Spirit 4, Chain Lightning 3, Earth Shock 6, Flametongue Totem 3, Frostbrand Weapon 4, Healing Wave 8, Lightning Shield 6, Mana Tide Totem 2, Stoneclaw Totem 5
	[50] = { 10462, 4, 1238299, 2, 15207, 9, 1239242, 2, 10437, 5, 10486, 3 },
		-- Healing Stream Totem 4, Lava Burst 2, Lightning Bolt 9, Riptide 2, Searing Totem 5, Windfury Weapon 3
	[52] = { 408345, 5, 10448, 5, 10467, 5, 10442, 4, 10614, 3 },
		-- Fire Nova 5, Flame Shock 5, Lesser Healing Wave 5, Strength of Earth Totem 4, Windfury Totem 3
	[54] = { 10623, 3, 10479, 3, 16316, 7, 10408, 6 },
		-- Chain Heal 3, Frost Resistance Totem 3, Rockbiter Weapon 7, Stoneskin Totem 6
	[56] = { 10605, 4, 16342, 6, 10627, 2, 10396, 9, 15208, 10, 10432, 7, 10587, 4, 10497, 4, 15112, 3 },
		-- Chain Lightning 4, Flametongue Weapon 6, Grace of Air Totem 2, Healing Wave 9, Lightning Bolt 10, Lightning Shield 7, Magma Totem 4, Mana Spring Totem 4, Windwall Totem 3
	[58] = { 10538, 3, 16387, 4, 10473, 4, 16356, 5, 17359, 3, 10428, 6 },
		-- Fire Resistance Totem 3, Flametongue Totem 4, Frost Shock 4, Frostbrand Weapon 5, Mana Tide Totem 3, Stoneclaw Totem 6
	[60] = { 20777, 5, 10414, 7, 29228, 6, 25359, 3, 10463, 5, 25357, 10, 1238300, 3, 10468, 6, 10601, 3, 1239243, 3, 10438, 6, 25361, 5, 16362, 4 },
		-- Ancestral Spirit 5, Earth Shock 7, Flame Shock 6, Grace of Air Totem 3, Healing Stream Totem 5, Healing Wave 10, Lava Burst 3, Lesser Healing Wave 6, Nature Resistance Totem 3, Riptide 3, Searing Totem 6, Strength of Earth Totem 5, Windfury Weapon 4
}

-- Rank 1 of these comes from a talent, not the trainer: their later ranks are
-- only for shamans who already have the spell (Lava Burst, Riptide, Mana Tide Totem).
local TALENT_SPELL = { [408490] = true, [408521] = true, [16190] = true }

local function cfg()
	SP.opt.trainerReminder = SP.opt.trainerReminder or {}
	return SP.opt.trainerReminder
end
local function on(key, default)
	local v = cfg()[key]
	if v == nil then return default end
	return v
end

local knowsExact = SPCompat.KnowsExactSpellID

-- this rank or a higher one of the same spell is known, by spell ID (this client's rank list)
local function haveRankOrHigher(id)
	local ranks = SPCompat.SpellRanks(id)
	if not ranks then return knowsExact(id) end
	local from = 1
	for i = 1, #ranks do
		if ranks[i] == id then from = i break end
	end
	for i = from, #ranks do
		if knowsExact(ranks[i]) then return true end
	end
	return false
end

-- what can be trained at or below `level` and is not known: { new = {...}, older = {...} }
local function missing(level, newLevel)
	local out = { new = {}, older = {} }
	for lvl = 2, level do
		local row = TRAINER[lvl]
		if row then
			for i = 1, #row, 2 do
				local id, rank = row[i], row[i + 1]
				local wanted = not haveRankOrHigher(id)
				-- a talent's later rank: only once its first rank is known
				local ranks = SPCompat.SpellRanks(id)
				local first = ranks and ranks[1] or id
				if wanted and TALENT_SPELL[first] then wanted = SPCompat.KnowsSpellID(id) end
				local name = wanted and SPCompat.SpellName(id)
				if name then
					local label = name
					if rank > 0 then label = name .. " (" .. string.format(TRADESKILL_RANK_HEADER or "Rank %d", rank) .. ")" end
					if newLevel and lvl == newLevel then out.new[#out.new + 1] = label else out.older[#out.older + 1] = label end
				end
			end
		end
	end
	return out
end

local function say(text)
	if on("chat", true) and DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cff0070ddShamanPower|r: " .. text)
	end
end

local function report(level, newLevel, manual)
	if not on("enabled", true) then return end
	if SP:IsOff() and not manual then return end   -- switched off: only Check Now answers
	local m = missing(level, newLevel)
	if newLevel then
		if #m.new > 0 then
			say("new at your trainer: |cffffffff" .. table.concat(m.new, ", ") .. "|r")
			if on("screen", false) and RaidNotice_AddMessage and RaidWarningFrame then
				RaidNotice_AddMessage(RaidWarningFrame, "New at your trainer: " .. #m.new .. (#m.new == 1 and " spell" or " spells"), { r = 1, g = 0.82, b = 0 })
			end
		end
		if #m.older > 0 and on("older", true) then
			say("still waiting from earlier levels: |cffbbbbbb" .. table.concat(m.older, ", ") .. "|r")
		end
	else
		-- login: one quiet line
		local all = {}
		for _, v in ipairs(m.older) do all[#all + 1] = v end
		for _, v in ipairs(m.new) do all[#all + 1] = v end
		if #all > 0 then
			say(#all .. (#all == 1 and " spell is" or " spells are") .. " waiting at your trainer: |cffbbbbbb" .. table.concat(all, ", ") .. "|r")
		elseif manual then
			say("nothing new at your trainer - you are up to date.")
		end
	end
end

function SP:TrainerReminderReport() report(UnitLevel("player") or 1, nil, true) end

local f = CreateFrame("Frame")
if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(f, "Trainer Reminder") end
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, event, a1)
	if SP:IsOff() or not on("enabled", true) then return end
	if event == "PLAYER_LEVEL_UP" then
		local lvl = tonumber(a1) or UnitLevel("player")
		-- the spellbook can lag the level-up by a moment
		C_Timer.After(1, function() report(lvl, lvl) end)
	elseif a1 and on("login", true) then   -- isInitialLogin
		C_Timer.After(6, function() if on("login", true) then report(UnitLevel("player") or 1, nil) end end)
	end
end)

-- ---------------------------------------------------------------------------
-- Options: Modules > Trainer Reminder
-- ---------------------------------------------------------------------------
local fluffy = SP.options and SP.options.args and SP.options.args.fluffy
if fluffy and fluffy.args then
	local function toggle(order, key, default, name, desc)
		return {
			order = order, type = "toggle", width = "full", name = name, desc = desc,
			disabled = key ~= "enabled" and function() return not on("enabled", true) end or nil,
			get = function() return on(key, default) end,
			set = function(_, v) cfg()[key] = v end,
		}
	end
	fluffy.args.trainer_section = {
		order = 19.8,
		name = "|cff0070ddTrainer Reminder|r",
		type = "group",
		args = {
			desc = {
				order = 0, type = "description", width = "full",
				name = "When you level up, ShamanPower lists the shaman spells and ranks now waiting at your trainer. Only you see it.",
			},
			enabled = toggle(1, "enabled", true, "Enable Trainer Reminder", "Tell me what is new at the trainer when I level up."),
			chat    = toggle(2, "chat", true, "Line in My Chat Window", "The list of new spells and ranks, in your own chat window."),
			screen  = toggle(3, "screen", false, "Big Text on My Screen", "Raid-warning-style text at the top of your screen on a level-up with something new. Drawn only on your screen."),
			older   = toggle(4, "older", true, "Also List What I Skipped Earlier", "After the new spells, list ranks from earlier levels you have not bought yet."),
			login   = toggle(5, "login", true, "One Summary Line at Login", "At login, one line with everything waiting at your trainer (nothing when you are up to date)."),
			check   = {
				order = 6, type = "execute", name = "Check Now",
				desc = "List everything waiting at your trainer now.",
				disabled = function() return not on("enabled", true) end,
				func = function() report(UnitLevel("player") or 1, nil, true) end,
			},
		},
	}
end
