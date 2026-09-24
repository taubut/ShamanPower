-- ============================================================================
-- Trainer Reminder (WoW: Forever): after a level-up, say which shaman spells
-- and ranks are waiting at the trainer; once at login, one summary line.
-- Forever characters all level from 1, so this is a levelling helper.
--
-- The table is Forever's trainer list (build 1.60.1, SkillLineAbility +
-- SpellLevels, ~/.claude/shamanpower/beta-ui-1.60.1/forever-shaman-trainer-by-level.md).
-- What you already know is read from the spellbook by name and "Rank N"
-- subtext, so no per-rank spell IDs are needed. Runs only on the level-up and
-- login events: nothing while you play.
-- ============================================================================

local SP = ShamanPower
if not SP then return end
if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then return end
if select(2, UnitClass("player")) ~= "SHAMAN" then return end

-- [level] = { "Name", rank (0 = no ranks) , ... } pairs, as a flat list per level
local TRAINER = {
	[4]  = { "Earth Shock", 1, "Stoneskin Totem", 1 },
	[6]  = { "Earthbind Totem", 0, "Healing Wave", 2 },
	[8]  = { "Earth Shock", 2, "Lightning Bolt", 2, "Lightning Shield", 1, "Rockbiter Weapon", 2, "Stoneclaw Totem", 1 },
	[10] = { "Flame Shock", 1, "Flametongue Weapon", 1, "Searing Totem", 1, "Strength of Earth Totem", 1 },
	[12] = { "Ancestral Spirit", 1, "Fire Nova", 1, "Healing Wave", 3, "Purge", 1 },
	[14] = { "Earth Shock", 3, "Lightning Bolt", 3, "Stoneskin Totem", 2 },
	[16] = { "Cure Poison", 0, "Lightning Shield", 2, "Rockbiter Weapon", 3 },
	[18] = { "Flame Shock", 2, "Flametongue Weapon", 2, "Healing Wave", 4, "Stoneclaw Totem", 2, "Tremor Totem", 0 },
	[20] = { "Call of the Elements", 0, "Frost Shock", 1, "Frostbrand Weapon", 1, "Ghost Wolf", 0, "Healing Stream Totem", 1,
	         "Lesser Healing Wave", 1, "Lightning Bolt", 4, "Searing Totem", 2, "Totemic Recall", 0 },
	[22] = { "Cure Disease", 0, "Fire Nova", 2, "Poison Cleansing Totem", 0, "Totemic Projection", 0, "Water Breathing", 0 },
	[24] = { "Ancestral Spirit", 2, "Earth Shock", 4, "Frost Resistance Totem", 1, "Healing Wave", 5, "Lightning Shield", 3,
	         "Rockbiter Weapon", 4, "Stoneskin Totem", 3, "Strength of Earth Totem", 2 },
	[26] = { "Far Sight", 0, "Flametongue Weapon", 3, "Lightning Bolt", 5, "Magma Totem", 1, "Mana Spring Totem", 1 },
	[28] = { "Fire Resistance Totem", 1, "Flame Shock", 3, "Flametongue Totem", 1, "Frostbrand Weapon", 2, "Lesser Healing Wave", 2,
	         "Stoneclaw Totem", 3, "Water Walking", 0 },
	[30] = { "Astral Recall", 0, "Call of the Ancestors", 0, "Grounding Totem", 0, "Healing Stream Totem", 2, "Nature Resistance Totem", 1,
	         "Reincarnation", 0, "Searing Totem", 3, "Windfury Weapon", 1 },
	[32] = { "Chain Lightning", 1, "Fire Nova", 3, "Healing Wave", 6, "Lightning Bolt", 6, "Lightning Shield", 4, "Purge", 2, "Windfury Totem", 1 },
	[34] = { "Frost Shock", 2, "Rockbiter Weapon", 5, "Sentry Totem", 0, "Stoneskin Totem", 4 },
	[36] = { "Ancestral Spirit", 3, "Earth Shock", 5, "Flametongue Weapon", 4, "Lesser Healing Wave", 3, "Magma Totem", 2,
	         "Mana Spring Totem", 2, "Windwall Totem", 1 },
	[38] = { "Disease Cleansing Totem", 0, "Flametongue Totem", 2, "Frost Resistance Totem", 2, "Frostbrand Weapon", 3, "Lightning Bolt", 7,
	         "Stoneclaw Totem", 4, "Strength of Earth Totem", 3 },
	[40] = { "Call of the Spirits", 0, "Chain Heal", 1, "Chain Lightning", 2, "Flame Shock", 4, "Healing Stream Totem", 3, "Healing Wave", 7,
	         "Lightning Shield", 5, "Searing Totem", 4, "Windfury Weapon", 2 },
	[42] = { "Fire Nova", 4, "Fire Resistance Totem", 2, "Grace of Air Totem", 1, "Windfury Totem", 2 },
	[44] = { "Lesser Healing Wave", 4, "Lightning Bolt", 8, "Nature Resistance Totem", 2, "Rockbiter Weapon", 6, "Stoneskin Totem", 5 },
	[46] = { "Chain Heal", 2, "Flametongue Weapon", 5, "Frost Shock", 3, "Magma Totem", 3, "Mana Spring Totem", 3, "Windwall Totem", 2 },
	[48] = { "Ancestral Spirit", 4, "Chain Lightning", 3, "Earth Shock", 6, "Flametongue Totem", 3, "Frostbrand Weapon", 4, "Healing Wave", 8,
	         "Lightning Shield", 6, "Stoneclaw Totem", 5 },
	[50] = { "Healing Stream Totem", 4, "Lava Burst", 2, "Lightning Bolt", 9, "Riptide", 2, "Searing Totem", 5, "Windfury Weapon", 3 },
	[52] = { "Fire Nova", 5, "Flame Shock", 5, "Lesser Healing Wave", 5, "Strength of Earth Totem", 4, "Windfury Totem", 3 },
	[54] = { "Chain Heal", 3, "Frost Resistance Totem", 3, "Rockbiter Weapon", 7, "Stoneskin Totem", 6 },
	[56] = { "Chain Lightning", 4, "Flametongue Weapon", 6, "Grace of Air Totem", 2, "Healing Wave", 9, "Lightning Bolt", 10,
	         "Lightning Shield", 7, "Magma Totem", 4, "Mana Spring Totem", 4, "Windwall Totem", 3 },
	[58] = { "Fire Resistance Totem", 3, "Flametongue Totem", 4, "Frost Shock", 4, "Frostbrand Weapon", 5, "Mana Tide Totem", 2, "Stoneclaw Totem", 6 },
	[60] = { "Ancestral Spirit", 5, "Earth Shock", 7, "Flame Shock", 6, "Grace of Air Totem", 3, "Healing Stream Totem", 5, "Healing Wave", 10,
	         "Lava Burst", 3, "Lesser Healing Wave", 6, "Nature Resistance Totem", 3, "Riptide", 3, "Searing Totem", 6,
	         "Strength of Earth Totem", 5, "Windfury Weapon", 4 },
}

-- Rank 1 of these comes from a talent, not the trainer: their later ranks are
-- only for shamans who already have the spell.
local TALENT_SPELL = { ["Lava Burst"] = true, ["Riptide"] = true, ["Mana Tide Totem"] = true }

local function cfg()
	SP.opt.trainerReminder = SP.opt.trainerReminder or {}
	return SP.opt.trainerReminder
end
local function on(key, default)
	local v = cfg()[key]
	if v == nil then return default end
	return v
end

-- The rank of spellbook item i: its "Rank N" subtext, from the item or from the spell.
local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
local function itemRank(i, sub)
	local r = type(sub) == "string" and tonumber(sub:match("(%d+)"))
	if r then return r end
	local id
	if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
		local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, i, bank)
		id = ok and type(info) == "table" and info.spellID or nil
	end
	local getSub = (C_Spell and C_Spell.GetSpellSubtext) or GetSpellSubtext
	if id and getSub then
		local ok, s = pcall(getSub, id)
		r = ok and type(s) == "string" and tonumber(s:match("(%d+)")) or nil
	end
	return r
end

-- name -> highest rank known (0 = known, rank not readable or no ranks), from the
-- spellbook; sawRanks = whether this client shows ranks at all
local function knownSpells()
	local known, sawRanks = {}, false
	if not GetSpellBookItemName then return known, sawRanks end
	for i = 1, 600 do
		local ok, name, sub = pcall(GetSpellBookItemName, i, BOOKTYPE_SPELL or "spell")
		if not ok or not name then break end
		if type(name) == "string" then
			local rank = itemRank(i, sub)
			if rank then sawRanks = true end
			rank = rank or 0
			if (known[name] or -1) < rank then known[name] = rank end
		end
	end
	return known, sawRanks
end

-- what can be trained at or below `level` and is not known: { new = {...}, older = {...} }
local function missing(level, newLevel)
	local known, sawRanks = knownSpells()
	local out = { new = {}, older = {} }
	for lvl = 2, level do
		local row = TRAINER[lvl]
		if row then
			for i = 1, #row, 2 do
				local name, rank = row[i], row[i + 1]
				local have = known[name]
				local wanted
				if TALENT_SPELL[name] then
					wanted = have ~= nil and have < rank
				else
					-- no rank text anywhere in the spellbook: only spells not known at all
					-- (never nag about ranks the client cannot show)
					wanted = (have == nil) or (sawRanks and rank > 0 and have < rank)
				end
				-- a lower rank of something already bought at a higher rank is not missing
				if wanted then
					local label = rank > 0 and (name .. " (Rank " .. rank .. ")") or name
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
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, event, a1)
	if event == "PLAYER_LEVEL_UP" then
		local lvl = tonumber(a1) or UnitLevel("player")
		-- the spellbook can lag the level-up by a moment
		C_Timer.After(1, function() report(lvl, lvl) end)
	elseif a1 then   -- isInitialLogin
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
