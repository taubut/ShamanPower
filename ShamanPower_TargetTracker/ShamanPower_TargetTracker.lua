-- ============================================================================
-- ShamanPower Target Tracker
-- Your Flame Shock, Frost Shock and Stormstrike on your target (yours only, with
-- the time left and Stormstrike's charges); each spell's Missing Warning (a faded
-- icon with a red edge while yours is not on an enemy); each spell's Every
-- Nameplate (on every enemy nameplate: your debuff with its time where it is on,
-- its Missing Warning where it is not; Purge on every enemy with a Magic buff you
-- can remove); and a big Purge icon that lights up while your target (or, in a
-- boss fight, a boss) has a Magic buff you can remove. Each spell has its own When
-- (in a fight or out of it; the open world, dungeons, raids, Battlegrounds,
-- Arenas) and Look; Rules turn a part on or off in a place or against a boss.
--
-- Nothing here polls. On WoW: Forever the game draws every aura itself: ONE aura
-- container on your target (a slot each for Flame Shock, Frost Shock, Stormstrike
-- and Purge), one per boss during a boss fight, one per enemy nameplate with Every
-- Nameplate (made ahead, out of combat). A Missing Warning sits under its spell's
-- slot, so the real debuff, drawn on top by the game, covers it: nothing is read.
-- ONE state driver shows what is on your target only while you have an
-- attackable, living target, and only while the module needs one. In a fight no
-- ShamanPower code runs for them. On Anniversary auras can be read, so the icons
-- are filled in from UNIT_AURA (the target only, and the plates or bosses that
-- need it), from the event's own list of what changed. The time left is the
-- game's: a duration text binding and a Cooldown sweep, both updated by the game.
-- The only timers: the settings preview's demo while it is open, and one-shot
-- deferrals.
-- ============================================================================

local SP = ShamanPower
if not SP then return end
-- Only for Shamans (the settings page says the module is not loaded otherwise)
if select(2, UnitClass("player")) ~= "SHAMAN" then return end
SP.TargetTrackerLoaded = true

local FOREVER = SPCompat and SPCompat.FOREVER and true or false
local secret = issecretvalue or function() return false end
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil

-- WoW's own colors: its gold (the Purge glow and word), its red (Flame Shock
-- missing) and Magic's blue (a Magic buff's edge in the preview)
local GOLD, RED, MAGIC
do
	local function RGB(c, r, g, b)
		if type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b end
		return r, g, b
	end
	GOLD = { RGB(NORMAL_FONT_COLOR, 1, 0.82, 0) }
	RED = { RGB(RED_FONT_COLOR, 1, 0.125, 0.125) }
	MAGIC = { RGB(DebuffTypeColor and DebuffTypeColor.Magic, 0.2, 0.6, 1) }
end

-- ---------------------------------------------------------------------------
-- The spells. ids: the ranks a player learns (TT_Known, the settings icons);
-- auraIDs: every ID the debuff can have on the target, on either game version
-- (an ID a client does not have matches nothing).
-- ---------------------------------------------------------------------------
local SPELLS = {
	{ key = "fs", name = "Flame Shock", icon = "Interface\\Icons\\Spell_Fire_FlameShock",
		ids = { 8050, 8052, 8053, 10447, 10448, 29228, 25457 },
		auraIDs = { 8050, 8052, 8053, 10447, 10448, 29228, 25457, 1213482, 1222942, 1248000 } },
	{ key = "frs", name = "Frost Shock", icon = "Interface\\Icons\\Spell_Frost_FrostShock",
		ids = { 8056, 8058, 10472, 10473, 25464 },
		auraIDs = { 8056, 8058, 10472, 10473, 25464, 1248001 } },
	{ key = "ss", name = "Stormstrike", icon = "Interface\\Icons\\Ability_Shaman_Stormstrike",
		ids = { 17364 }, auraIDs = { 17364 } },
	{ key = "purge", name = "Purge", icon = "Interface\\Icons\\Spell_Nature_Purge", ids = { 370, 8012 } },
}
SP.TT_SPELLS = SPELLS
local SPELL = {}
for _, s in ipairs(SPELLS) do
	s.name = SPCompat.SpellLabel(s.ids[1], s.name)
	SPELL[s.key] = s
end
local DEBUFFS = { "fs", "frs", "ss" }
local AURA_KEY, AURA_IDS = {}, {}   -- [aura ID] = debuff key; [key] = { [aura ID] = true } (the slots' lists)
for _, key in ipairs(DEBUFFS) do
	AURA_IDS[key] = {}
	for _, id in ipairs(SPELL[key].auraIDs) do
		AURA_KEY[id] = key
		AURA_IDS[key][id] = true
	end
end
local DEMON_ARMOR = "Interface\\Icons\\Spell_Shadow_RagingScream"   -- the preview's pretend Magic buff

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
ShamanPower_TargetTracker = ShamanPower_TargetTracker or {}

local DEFAULTS = {
	enabled = false,   -- new in 3.0.6: off until turned on (the switch beside Target Tracker in the settings)
	showOn = "spot",   -- your debuffs: spot (a spot you place) | plate (your target's nameplate) | frame (under the target frame)
	arrange = "row",   -- row | column
	spacing = 6,
	plateSpot = "above",  -- on your target's nameplate: above (its name) | below | left | right (of its health bar)
	plateX = 0, plateY = 0,   -- and nudged from there (the page's Left / Right and Up / Down)
	hideGame = true,      -- WoW's own nameplate icons for the spells Target Tracker shows: hidden (nothing twice)
	-- debuffsPos, purgePos, nsPos = { anchor, x, y }: the spots (Next Shock's is nsPos; nil = where they start)
	spells = {},       -- [key] = { [setting] = value }: only what a spell sets for itself
	hidden = {},       -- [key] = true: a spell clicked off on the page
	rules = {},        -- { place =, who =, name =, part = }, in order: a later rule wins
}
-- the support code (/sp support) reports only what differs from these
if SP.SUPPORT_MODULE_DEFAULTS then SP.SUPPORT_MODULE_DEFAULTS.ShamanPower_TargetTracker = DEFAULTS end

-- Each spell's settings and what they start as. w_<kind>: it shows in that kind
-- of place. Every spell starts everywhere.
local KINDS = { "world", "dungeon", "raid", "bg", "arena" }
-- missing: the spell's Missing Warning; everyPlate: the spell on every enemy nameplate (Purge has no
-- Missing Warning: it shows a buff of the enemy's, not a debuff of yours)
local OPT = {
	fs = { show = "always", size = 36, timeLeft = true, sweep = "radial", missing = false, everyPlate = false,
		sweepDirection = "top", missLook = "edge", border = "thin" },
	frs = { show = "always", size = 36, timeLeft = true, sweep = "radial", missing = false, everyPlate = false,
		sweepDirection = "top", missLook = "edge", border = "thin" },
	ss = { show = "always", size = 36, timeLeft = true, sweep = "radial", charges = true, missing = false, everyPlate = false,
		sweepDirection = "top", missLook = "edge", border = "thin" },
	purge = { show = "always", size = 64, glow = true, buffPicture = true, skipLong = true, longerThan = 2,
		watchBosses = true, showOn = "screen", everyPlate = false, border = "thin" },
	-- Next Shock (D49): one icon that shows which shock to press. Not one of the spells (never in SPELLS:
	-- the Spells row, rules, Every Nameplate and copy / paste know nothing of it); its settings are saved
	-- like a spell's own (spells.ns). on: Show Next Shock, off to start; whenOn: the shock it shows while
	-- your Flame Shock is on your target; refresh: Flame Shock again with this many seconds left (0 =
	-- never); noTarget: with no enemy target; castLook: its look when it's time to cast; gray: grayed out
	-- while Flame Shock is missing; showOn: its spot (a box you move, your target's nameplate, under the
	-- target frame)
	ns = { on = false, whenOn = "earth", refresh = 3, noTarget = "show", castLook = "gold", gray = true,
		showOn = "screen", size = 64 },
}
for _, key in ipairs(DEBUFFS) do
	for _, k in ipairs(KINDS) do OPT[key]["w_" .. k] = true end
end
for _, k in ipairs(KINDS) do OPT.purge["w_" .. k] = true end
local CHOICE = {
	show = { always = true, combat = true, nocombat = true },
	sweep = { radial = true, greys = true, fills = true, none = true },
	sweepDirection = { top = true, bottom = true },
	showOn = { screen = true, plate = true, frame = true },
	missLook = { edge = true, dotted = true, faded = true, glow = true, tint = true, slash = true, outline = true, pulse = true },
	border = { thin = true, none = true, thick = true, dotted = true, spell = true },
	-- Next Shock's: Earth Shock or Frost Shock; Flame Shock or nothing; Gold Dotted Edge or a Missing look
	whenOn = { earth = true, frost = true },
	noTarget = { show = true, hide = true },
	castLook = { gold = true, edge = true, dotted = true, faded = true, glow = true, tint = true, slash = true, outline = true, pulse = true },
}
local SIZE = { fs = { 16, 64 }, frs = { 16, 64 }, ss = { 16, 64 }, purge = { 32, 128 }, ns = { 24, 128 } }
-- how a part looks: changed on the parts already there (nothing is made again)
local LOOK = { size = true, timeLeft = true, sweep = true, sweepDirection = true, charges = true, glow = true, buffPicture = true, showOn = true,
	missLook = true, border = true, castLook = true, whenOn = true, gray = true,
	on = true }   -- (Next Shock's own switch: Flame Shock's sweep copies the shock it shows)
-- what Purge counts as a buff to light for: the game's own slot filter, updated in place
local FILTER = { skipLong = true, longerThan = true }
local GROUPS = {
	when = { show = true, w_world = true, w_dungeon = true, w_raid = true, w_bg = true, w_arena = true },
	look = { size = true, timeLeft = true, sweep = true, sweepDirection = true, charges = true, glow = true, buffPicture = true, missLook = true,
		border = true },
}
local PAGE = { showOn = { spot = true, plate = true, frame = true }, arrange = { row = true, column = true },
	plateSpot = { above = true, below = true, left = true, right = true } }

-- the value as it is saved, or nil when it is not one this setting takes
local function Normalize(key, opt, v)
	local d = OPT[key] and OPT[key][opt]
	if d == nil then return nil end
	if opt == "size" or opt == "longerThan" or opt == "refresh" then
		v = tonumber(v)
		if not v or v ~= v then return nil end
		local lo, hi = 1, 10
		if opt == "size" then lo, hi = SIZE[key][1], SIZE[key][2] elseif opt == "refresh" then lo, hi = 0, 6 end
		return min(hi, max(lo, floor(v + 0.5)))
	end
	if type(d) == "boolean" then
		if type(v) ~= "boolean" then return nil end
		return v
	end
	local c = CHOICE[opt]
	if c and c[v] then return v end
	return nil
end

-- a saved table as this version reads it: what it does not know or cannot use is dropped
-- (an old or damaged import must never make a layout fail)
local function Clean(sv)
	for _, k in ipairs({ "spells", "hidden", "rules" }) do
		if type(sv[k]) ~= "table" then sv[k] = {} end
	end
	for key, own in pairs(sv.spells) do
		if not OPT[key] or type(own) ~= "table" then
			sv.spells[key] = nil
		else
			for opt, v in pairs(own) do
				local nv = Normalize(key, opt, v)
				if nv == nil or (opt ~= "sweepDirection" and nv == OPT[key][opt]) then own[opt] = nil else own[opt] = nv end
			end
			if next(own) == nil then sv.spells[key] = nil end
		end
	end
	for key, v in pairs(sv.hidden) do
		if not SPELL[key] or v ~= true then sv.hidden[key] = nil end
	end
	for i = #sv.rules, 1, -1 do
		local r = sv.rules[i]
		if type(r) ~= "table" or type(r.place) ~= "string" or type(r.who) ~= "string" or type(r.part) ~= "string" then
			table.remove(sv.rules, i)
		elseif r.name ~= nil and type(r.name) ~= "string" then
			r.name = nil
		end
	end
	local sp = tonumber(sv.spacing)
	if sp and sp == sp then sv.spacing = min(40, max(0, floor(sp + 0.5))) else sv.spacing = DEFAULTS.spacing end
	if not PAGE.showOn[sv.showOn] then sv.showOn = DEFAULTS.showOn end
	if not PAGE.arrange[sv.arrange] then sv.arrange = DEFAULTS.arrange end
	if not PAGE.plateSpot[sv.plateSpot] then sv.plateSpot = DEFAULTS.plateSpot end
	local px, py = tonumber(sv.plateX), tonumber(sv.plateY)
	if px and px == px then sv.plateX = min(80, max(-80, floor(px + 0.5))) else sv.plateX = DEFAULTS.plateX end
	if py and py == py then sv.plateY = min(120, max(-60, floor(py + 0.5))) else sv.plateY = DEFAULTS.plateY end
	if type(sv.hideGame) ~= "boolean" then sv.hideGame = DEFAULTS.hideGame end
	if type(sv.enabled) ~= "boolean" then sv.enabled = DEFAULTS.enabled end
	for _, k in ipairs({ "debuffsPos", "purgePos", "nsPos" }) do
		local p = sv[k]
		if p ~= nil and (type(p) ~= "table" or type(p.anchor) ~= "string") then sv[k] = nil end
	end
end

local filledFor
local function SV()
	local sv = ShamanPower_TargetTracker
	if type(sv) ~= "table" then
		sv = {}
		ShamanPower_TargetTracker = sv
	end
	if sv ~= filledFor then
		for k, v in pairs(DEFAULTS) do
			if sv[k] == nil then
				if type(v) == "table" then sv[k] = {} else sv[k] = v end
			end
		end
		Clean(sv)
		filledFor = sv
	end
	return sv
end

local function Own(key, create)
	local spells = SV().spells
	local own = spells[key]
	if type(own) ~= "table" then
		if not create then return nil end
		own = {}
		spells[key] = own
	end
	return own
end

local function Get(key, opt)
	if opt == "shown" then return not SV().hidden[key] end
	local own = Own(key)
	local v = own and own[opt]
	if v ~= nil then return v end
	local d = OPT[key]
	-- An unset direction preserves each old look: gray from the top, color from the bottom.
	if opt == "sweepDirection" and d and d.sweepDirection then
		if (own and own.sweep or d.sweep) == "fills" then return "bottom" end
		return "top"
	end
	return d and d[opt]
end

-- v already normalized; nil (or the default) = back to the default. True when it changed.
local function SetOwn(key, opt, v)
	-- Keep an explicit direction even when it is "top": the inherited default changes with the look.
	if opt ~= "sweepDirection" and v ~= nil and v == OPT[key][opt] then v = nil end
	local own = Own(key, v ~= nil)
	if not own or own[opt] == v then return false end
	own[opt] = v
	if next(own) == nil then SV().spells[key] = nil end
	return true
end

-- ---------------------------------------------------------------------------
-- The places and bosses a rule can name: every raid and dungeon of this game
-- version with its bosses (the client's own Map and DungeonEncounter tables,
-- 2026-10-02), then the kinds of place.
-- ---------------------------------------------------------------------------
-- WoW: Forever 1.60.1 (build 70170): from the client's own DB2 tables (Map, DungeonEncounter)
local function ForeverPlaces()
	return {
		raids = {
			409, "Molten Core",
			249, "Onyxia's Lair",
			469, "Blackwing Lair",
			309, "Zul'Gurub",
			509, "Ruins of Ahn'Qiraj",
			531, "Temple of Ahn'Qiraj",
			533, "Naxxramas",
			2789, "The Tainted Scar",
			2791, "Storm Cliffs",
			2804, "The Crystal Vale",
			2832, "Nightmare Grove",
			2856, "Scarlet Enclave",
		},
		dungeons = {
			48, "Blackfathom Deeps",
			230, "Blackrock Depths",
			229, "Blackrock Spire",
			2807, "Burning of Andorhal",
			269, "Caverns of Time",
			2959, "City of Dalaran",
			36, "Deadmines",
			2853, "Deadwind Pass",
			2784, "Demon Fall Canyon",
			429, "Dire Maul",
			2998, "Excavation Site: Wetlands",
			90, "Gnomeregan",
			3065, "The Hall of Thanes",
			2875, "Karazhan Crypts",
			3109, "Manor Mistmantle",
			349, "Maraudon",
			2921, "Naxxramas (dungeon)",
			389, "Ragefire Chasm",
			129, "Razorfen Downs",
			47, "Razorfen Kraul",
			2999, "Ruins of Lordaeron",
			2902, "The Scarab Dais",
			189, "Scarlet Monastery",
			289, "Scholomance",
			2806, "Shadow Hold",
			33, "Shadowfang Keep",
			2817, "Starfall Barrow Den",
			34, "Stormwind Stockade",
			329, "Stratholme",
			109, "Sunken Temple",
			70, "Uldaman",
			43, "Wailing Caverns",
			209, "Zul'Farrak",
		},
		bosses = {
			[409] = { 663, "Lucifron", 664, "Magmadar", 665, "Gehennas", 666, "Garr", 667, "Shazzrah", 668, "Baron Geddon", 669, "Sulfuron Harbinger", 670, "Golemagg the Incinerator", 671, "Majordomo Executus", 672, "Ragnaros" },
			[249] = { 1084, "Onyxia" },
			[469] = { 610, "Razorgore the Untamed", 611, "Vaelastrasz the Corrupt", 612, "Broodlord Lashlayer", 613, "Firemaw", 614, "Ebonroc", 615, "Flamegor", 616, "Chromaggus", 617, "Nefarian" },
			[309] = { 785, "High Priestess Jeklik", 784, "High Priest Venoxis", 786, "High Priestess Mar'li", 787, "Bloodlord Mandokir", 788, "Edge of Madness", 789, "High Priest Thekal", 790, "Gahz'ranka", 791, "High Priestess Arlokk", 792, "Jin'do the Hexxer", 793, "Hakkar" },
			[509] = { 718, "Kurinnaxx", 719, "General Rajaxx", 720, "Moam", 721, "Buru the Gorger", 722, "Ayamiss the Hunter", 723, "Ossirian the Unscarred" },
			[531] = { 709, "The Prophet Skeram", 710, "Silithid Royalty", 711, "Battleguard Sartura", 712, "Fankriss the Unyielding", 713, "Viscidus", 714, "Princess Huhuran", 715, "Twin Emperors", 716, "Ouro", 717, "C'thun" },
			[533] = { 1107, "Anub'Rekhan", 1110, "Grand Widow Faerlina", 1116, "Maexxna", 1117, "Noth the Plaguebringer", 1112, "Heigan the Unclean", 1115, "Loatheb", 1113, "Instructor Razuvious", 1109, "Gothik the Harvester", 1121, "The Four Horsemen", 1118, "Patchwerk", 1111, "Grobbulus", 1108, "Gluth", 1120, "Thaddius", 1119, "Sapphiron", 1114, "Kel'Thuzad" },
			[2789] = { 3026, "Lord Kazzak" },
			[2791] = { 3027, "Azuregos" },
			[2804] = { 3079, "Prince Thunderaan" },
			[2832] = { 3111, "Emeriss", 3112, "Lethon", 3113, "Taerar", 3114, "Ysondre" },
			[2856] = { 3185, "Balnazzar", 3187, "Beatrix", 3196, "Beastmaster", 3186, "Solistrasza", 3197, "Mason", 3188, "Reborn Council", 3190, "Lillian Voss", 3189, "Caldoran" },
			[48] = { 2916, "Ghamoo-ra", 2915, "Lady Sarevess", 2914, "Geilhast", 2913, "Lorgus Jett", 2912, "Old Serra'kis", 2911, "Twilight Lord Kelris", 2910, "Aku'mai", 2694, "Baron Aquanis", 2704, "Gelihast" },
			[230] = { 227, "High Interrogator Gerstahn", 228, "Lord Roccor", 229, "Houndmaster Grebmar", 230, "Ring of Law", 231, "Pyromancer Loregrain", 232, "Lord Incendius", 233, "Warder Stilgiss", 234, "Fineous Darkvire", 235, "Bael'Gar", 236, "General Angerforge", 237, "Golem Lord Argelmach", 238, "Hurley Blackbreath", 239, "Phalanx", 240, "Ribbly Screwspigot", 241, "Plugger Spazzring", 2791, "The Vault", 242, "Ambassador Flamelash", 243, "The Seven", 244, "Magmus", 2789, "Princess Moira Bronzebeard", 2790, "Emperor Dagran Thaurissan" },
			[229] = { 267, "Highlord Omokk", 268, "Shadow Hunter Vosh'gajin", 269, "War Master Voone", 270, "Mother Smolderweb", 271, "Urok Doomhowl", 272, "Quartermaster Zigris", 274, "Halycon", 273, "Gizrul the Slavener", 275, "Overlord Wyrmthalak", 3062, "Pyroguard Emberseer", 3063, "Warchief Rend Blackhand", 3068, "The Beast", 3069, "General Drakkisath", 3070, "Lord Valthalak" },
			[2807] = {  },
			[269] = {  },
			[2959] = { 3298, "Arcane Anomaly", 3299, "Fel Ancient", 3300, "Mana Devourer", 3301, "Mana Elemental", 3302, "Unstable Sentinel", 3303, "Shade of the Archmage", 3310, "Lyn the Ignored", 3311, "Atrexis the Grave Knight", 3312, "Mana Wraith" },
			[36] = { 2741, "Rhahk'Zor", 2742, "Sneed", 3676, "Miner Johnson", 2743, "Gilnid", 2744, "Captain Greenskin", 2745, "Mr. Smite", 2746, "Cookie", 2747, "Edwin VanCleef" },
			[2853] = {  },
			[2784] = { 3023, "Grimroot", 3028, "Destructor's Wraith", 3029, "Zilbagob", 3030, "Pyranis", 3024, "Diathorus the Seeker", 3031, "Hellscream's Phantom", 3080, "Azgaloth" },
			[429] = { 343, "Zevrim Thornhoof", 344, "Hydrospawn", 345, "Lethtendris", 2792, "Pusillin", 346, "Alzzin the Wildshaper", 350, "Tendris Warpwood", 347, "Illyanna Ravenoak", 348, "Magister Kalendris", 349, "Immol'thar", 361, "Prince Tortheldrin", 362, "Guard Mol'dar", 363, "Stomper Kreeg", 364, "Guard Fengus", 365, "Guard Slip'kik", 366, "Captain Kromcrush", 367, "Cho'Rush the Observer", 368, "King Gordok", 2793, "Lord Hel'nurath", 2794, "Tsu'zee" },
			[2998] = { 3480, "Saltspine", 3481, "Shadetooth", 3644, "Highland Horror", 3482, "Relic Guardian" },
			[90] = { 2925, "Grubbis", 2928, "Viscous Fallout", 2899, "Crowd Pummeler 9-60", 2927, "Electrocutioner 6000", 2935, "Mechanical Menagerie", 2940, "Mekgineer Thermaplugg" },
			[3065] = { 3493, "Faldrim Anvilmar", 3495, "Infurnus", 3494, "Plunder", 3496, "Durgen Dirgehammer" },
			[2875] = { 3141, "Harbinger of Sin", 3146, "Creeping Malison", 3144, "Three Little Wolves", 3145, "Dark Rider", 3143, "Kharon", 3152, "Unk'omon", 3168, "Hans and Greta", 3169, "The Ugly Goblin", 3170, "Kaigy Maryla", 3171, "Sairuh Maryla", 3172, "Barian Maryla" },
			[3109] = {  },
			[349] = { 422, "Noxxion", 423, "Razorlash", 427, "Tinkerer Gizlock", 424, "Lord Vyletongue", 425, "Celebras the Cursed", 426, "Landslide", 428, "Rotgrip", 429, "Princess Theradras" },
			[2921] = { 3296, "Spirit of Mograine" },
			[389] = { 2732, "Oggleflint", 2733, "Taragaman the Hungerer", 2734, "Jergosh the Invoker", 2735, "Bazzalan" },
			[129] = { 2780, "Tuten'kash", 2781, "Plaguemaw the Rotting", 2782, "Mordresh Fire Eye", 2783, "Ragglesnout", 2784, "Glutton", 2785, "Amnennar the Coldbringer" },
			[47] = { 2773, "Roogug", 2774, "Aggem Thorncurse", 2775, "Death Speaker Jargba", 2776, "Overlord Ramtusk", 2777, "Agathelos the Raging", 2778, "Charlga Razorflank" },
			[2999] = { 3353, "Witherfang", 3357, "The Abandoned", 3355, "The Butcher", 3354, "Rath'mael", 3408, "Lordaeron Captain", 3411, "Viktor the Vile", 3412, "Bjork" },
			[2902] = {  },
			[189] = { 444, "Interrogator Vishas", 2779, "Bloodmage Thalnos", 446, "Houndmaster Loksey", 447, "Arcanist Doan", 448, "Herod", 449, "High Inquisitor Fairbanks", 450, "High Inquisitor Whitemane" },
			[289] = { 2805, "Kirtonos", 2804, "Jandice Barov", 2811, "Rattlegore", 2809, "Marduk Blackpool", 2813, "Vectus", 3055, "Kormok", 2810, "Ras Frostwhisperer", 2803, "Instructor Malicia", 2802, "Doctor Theolen Krastinov", 2808, "Lorekeeper Polkelt", 2812, "The Ravenian", 2807, "Lord Alexei Barov", 2806, "Lady Illucia Barov", 2801, "Darkmaster Gandling" },
			[2806] = {  },
			[33] = { 2748, "Rethilgore", 2749, "Razorclaw the Butcher", 2750, "Baron Silverlaine", 2751, "Commander Springvale", 2752, "Odo the Blindwatcher", 2753, "Fenrus the Devourer", 2754, "Wolf Master Nandos", 2755, "Archmage Arugal" },
			[2817] = {  },
			[34] = { 2756, "Targorr the Dread", 2757, "Kam Deepfury", 2758, "Hamhock", 2759, "Dextren Ward", 2760, "Bazil Thredd" },
			[329] = { 473, "Hearthsinger Forresten", 474, "Timmy the Cruel", 476, "Malor the Zealous", 475, "Cannon Master Willey", 477, "Archivist Galford", 478, "Balnazzar", 472, "The Unforgiven", 479, "Baroness Anastari", 480, "Nerub'enkan", 481, "Maleki the Pallid", 482, "Magistrate Barthilas", 483, "Ramstein the Gorger", 484, "Baron Rivendare", 2795, "Black Guard Swordsmith", 2796, "Crimson Hammersmith", 2797, "Ezra Grimm", 2798, "Postmaster Malown", 2799, "Skul", 2800, "Stonespine" },
			[109] = { 3582, "Atal'alarion", 3583, "Avatar of Hakkar", 3584, "Shade of Eranikus", 3585, "Hazzas", 3586, "Morphaz", 3587, "Weaver", 3588, "Dreamscythe", 3589, "Jammal'an the Prophet", 2953, "Festering Rotslime", 2954, "Atal'ai Defenders", 2955, "Dreamscythe and Weaver", 2957, "Jammal'an and Ogom", 2958, "Morphaz and Hazzas" },
			[70] = { 547, "Revelosh", 548, "The Lost Dwarves", 549, "Ironaya", 1887, "Obsidian Sentinel", 551, "Ancient Stone Keeper", 552, "Galgann Firehammer", 553, "Grimlok", 554, "Archaedas" },
			[43] = { 585, "Lady Anacondra", 586, "Lord Cobrahn", 587, "Kresh", 588, "Lord Pythas", 589, "Skum", 590, "Lord Serpentis", 591, "Verdan the Everliving", 592, "Mutanus the Devourer" },
			[209] = { 593, "Hydromancer Velratha", 594, "Gahz'rilla", 595, "Antu'sul", 596, "Theka the Martyr", 597, "Witch Doctor Zum'rah", 598, "Nekrum Gutchewer", 599, "Shadowpriest Sezz'ziz", 600, "Chief Ukorz Sandscalp" },
		},
		alias = { [486] = 3588, [487] = 3587, [488] = 3589, [490] = 3586, [491] = 3585, [492] = 3583, [493] = 3584, [2697] = 2916, [2699] = 2915, [2710] = 2913, [2761] = 2916, [2762] = 2915, [2763] = 2914, [2764] = 2913, [2765] = 2912, [2766] = 2911, [2767] = 2910, [2768] = 2925, [2769] = 2928, [2770] = 2927, [2771] = 2899, [2772] = 2940, [2814] = 3582, [2825] = 2911, [2891] = 2910, [2952] = 3582, [2956] = 3583, [2959] = 3584 },
	}
end

-- Anniversary 2.5.5: from the client's own DB2 tables (Map, DungeonEncounter)
local function AnniversaryPlaces()
	return {
		raids = {
			409, "Molten Core",
			249, "Onyxia's Lair",
			469, "Blackwing Lair",
			309, "Zul'Gurub",
			509, "Ruins of Ahn'Qiraj",
			531, "Temple of Ahn'Qiraj",
			533, "Naxxramas",
			532, "Karazhan",
			565, "Gruul's Lair",
			544, "Magtheridon's Lair",
			548, "Serpentshrine Cavern",
			550, "Tempest Keep",
			534, "Hyjal Summit",
			564, "Black Temple",
			568, "Zul'Aman",
			580, "Sunwell Plateau",
		},
		dungeons = {
			552, "The Arcatraz",
			558, "Auchenai Crypts",
			269, "The Black Morass",
			48, "Blackfathom Deeps",
			230, "Blackrock Depths",
			229, "Blackrock Spire",
			542, "The Blood Furnace",
			553, "The Botanica",
			36, "Deadmines",
			429, "Dire Maul",
			90, "Gnomeregan",
			543, "Hellfire Ramparts",
			585, "Magisters' Terrace",
			557, "Mana-Tombs",
			349, "Maraudon",
			554, "The Mechanar",
			560, "Old Hillsbrad Foothills",
			389, "Ragefire Chasm",
			129, "Razorfen Downs",
			47, "Razorfen Kraul",
			189, "Scarlet Monastery",
			289, "Scholomance",
			556, "Sethekk Halls",
			555, "Shadow Labyrinth",
			33, "Shadowfang Keep",
			540, "The Shattered Halls",
			547, "The Slave Pens",
			545, "The Steamvault",
			34, "Stormwind Stockade",
			329, "Stratholme",
			109, "Sunken Temple",
			70, "Uldaman",
			546, "The Underbog",
			43, "Wailing Caverns",
			209, "Zul'Farrak",
		},
		bosses = {
			[409] = { 663, "Lucifron", 664, "Magmadar", 665, "Gehennas", 666, "Garr", 667, "Shazzrah", 668, "Baron Geddon", 669, "Sulfuron Harbinger", 670, "Golemagg the Incinerator", 671, "Majordomo Executus", 672, "Ragnaros" },
			[249] = { 1084, "Onyxia" },
			[469] = { 610, "Razorgore the Untamed", 611, "Vaelastrasz the Corrupt", 612, "Broodlord Lashlayer", 613, "Firemaw", 614, "Ebonroc", 615, "Flamegor", 616, "Chromaggus", 617, "Nefarian" },
			[309] = { 785, "High Priestess Jeklik", 784, "High Priest Venoxis", 786, "High Priestess Mar'li", 787, "Bloodlord Mandokir", 788, "Edge of Madness", 789, "High Priest Thekal", 790, "Gahz'ranka", 791, "High Priestess Arlokk", 792, "Jin'do the Hexxer", 793, "Hakkar" },
			[509] = { 718, "Kurinnaxx", 719, "General Rajaxx", 720, "Moam", 721, "Buru the Gorger", 722, "Ayamiss the Hunter", 723, "Ossirian the Unscarred" },
			[531] = { 709, "The Prophet Skeram", 710, "Silithid Royalty", 711, "Battleguard Sartura", 712, "Fankriss the Unyielding", 713, "Viscidus", 714, "Princess Huhuran", 715, "Twin Emperors", 716, "Ouro", 717, "C'thun" },
			[533] = { 1107, "Anub'Rekhan", 1110, "Grand Widow Faerlina", 1116, "Maexxna", 1117, "Noth the Plaguebringer", 1112, "Heigan the Unclean", 1115, "Loatheb", 1113, "Instructor Razuvious", 1109, "Gothik the Harvester", 1121, "The Four Horsemen", 1118, "Patchwerk", 1111, "Grobbulus", 1108, "Gluth", 1120, "Thaddius", 1119, "Sapphiron", 1114, "Kel'Thuzad" },
			[532] = { 652, "Attumen the Huntsman", 653, "Moroes", 654, "Maiden of Virtue", 655, "Opera Hall", 656, "The Curator", 657, "Terestian Illhoof", 658, "Shade of Aran", 659, "Netherspite", 660, "Chess Event", 661, "Prince Malchezaar", 662, "Nightbane" },
			[565] = { 649, "High King Maulgar", 650, "Gruul the Dragonkiller" },
			[544] = { 651, "Magtheridon" },
			[548] = { 623, "Hydross the Unstable", 624, "The Lurker Below", 625, "Leotheras the Blind", 626, "Fathom-Lord Karathress", 627, "Morogrim Tidewalker", 628, "Lady Vashj" },
			[550] = { 730, "Al'ar", 731, "Void Reaver", 732, "High Astromancer Solarian", 733, "Kael'thas Sunstrider" },
			[534] = { 618, "Rage Winterchill", 619, "Anetheron", 620, "Kaz'rogal", 621, "Azgalor", 622, "Archimonde" },
			[564] = { 601, "High Warlord Naj'entus", 602, "Supremus", 603, "Shade of Akama", 604, "Teron Gorefiend", 605, "Gurtogg Bloodboil", 606, "Reliquary of Souls", 607, "Mother Shahraz", 608, "The Illidari Council", 609, "Illidan Stormrage" },
			[568] = { 1189, "Akil'zon", 1190, "Nalorakk", 1191, "Jan'alai", 1192, "Halazzi", 1193, "Hex Lord Malacrass", 1194, "Zul'jin" },
			[580] = { 724, "Kalecgos", 725, "Brutallus", 726, "Felmyst", 727, "Eredar Twins", 728, "M'uru", 729, "Kil'jaeden" },
			[552] = { 1913, "Dalliah the Doomsayer", 1914, "Harbinger Skyriss", 1915, "Wrath-Scryer Soccothrates", 1916, "Zereketh the Unbound" },
			[558] = { 1889, "Exarch Maladaar", 1890, "Shirrak the Dead Watcher" },
			[269] = { 1919, "Aeonus", 1920, "Chrono Lord Deja", 1921, "Temporus" },
			[48] = { 219, "Ghamoo-ra", 220, "Lady Sarevess", 221, "Gelihast", 222, "Lorgus Jett", 224, "Old Serra'kis", 225, "Twilight Lord Kelris", 226, "Aku'mai" },
			[230] = { 227, "High Interrogator Gerstahn", 228, "Lord Roccor", 229, "Houndmaster Grebmar", 230, "Ring of Law", 231, "Pyromancer Loregrain", 232, "Lord Incendius", 233, "Warder Stilgiss", 234, "Fineous Darkvire", 235, "Bael'Gar", 236, "General Angerforge", 237, "Golem Lord Argelmach", 238, "Hurley Blackbreath", 239, "Phalanx", 240, "Ribbly Screwspigot", 241, "Plugger Spazzring", 242, "Ambassador Flamelash", 243, "The Seven", 244, "Magmus", 245, "Emperor Dagran Thaurissan" },
			[229] = { 267, "Highlord Omokk", 268, "Shadow Hunter Vosh'gajin", 269, "War Master Voone", 270, "Mother Smolderweb", 271, "Urok Doomhowl", 272, "Quartermaster Zigris", 274, "Halycon", 273, "Gizrul the Slavener", 275, "Overlord Wyrmthalak", 276, "Pyroguard Emberseer", 277, "Solakar Flamewreath", 278, "Warchief Rend Blackhand", 279, "The Beast", 280, "General Drakkisath" },
			[542] = { 1922, "The Maker", 1923, "Keli'dan the Breaker", 1924, "Broggok" },
			[553] = { 1925, "Commander Sarannis", 1926, "High Botanist Freywinn", 1927, "Laj", 1928, "Thorngrin the Tender", 1929, "Warp Splinter" },
			[36] = { 161, "Rhahk'zor", 162, "Sneed", 163, "Gilnid", 164, "Mr. Smite", 165, "Cookie", 166, "Captain Greenskin", 167, "Edwin VanCleef" },
			[429] = { 343, "Zevrim Thornhoof", 344, "Hydrospawn", 345, "Lethtendris", 346, "Alzzin the Wildshaper", 350, "Tendris Warpwood", 347, "Illyanna Ravenoak", 348, "Magister Kalendris", 349, "Immol'thar", 361, "Prince Tortheldrin", 362, "Guard Mol'dar", 363, "Stomper Kreeg", 364, "Guard Fengus", 365, "Guard Slip'kik", 366, "Captain Kromcrush", 367, "Cho'Rush the Observer", 368, "King Gordok" },
			[90] = { 379, "Grubbis", 378, "Viscous Fallout", 380, "Electrocutioner 6000", 381, "Crowd Pummeler 9-60", 382, "Mekgineer Thermaplugg" },
			[543] = { 1891, "Omor the Unscarred", 1892, "Vazruden the Herald", 1893, "Watchkeeper Gargolmar" },
			[585] = { 1894, "Kael'thas Sunstrider", 1895, "Priestess Delrissa", 1897, "Selin Fireheart", 1898, "Vexallus" },
			[557] = { 1899, "Nexus-Prince Shaffar", 1900, "Pandemonius", 1901, "Tavarok", 250, "Yor" },
			[349] = { 422, "Noxxion", 423, "Razorlash", 427, "Tinkerer Gizlock", 424, "Lord Vyletongue", 425, "Celebras the Cursed", 426, "Landslide", 428, "Rotgrip", 429, "Princess Theradras" },
			[554] = { 1930, "Nethermancer Sepethrea", 1931, "Pathaleon the Calculator", 1932, "Mechano-Lord Capacitus", 1933, "Gatewatcher Gyro-Kill", 1934, "Gatewatcher Iron-Hand" },
			[560] = { 1905, "Lieutenant Drake", 1906, "Epoch Hunter", 1907, "Captain Skarloc" },
			[389] = { 430, "Oggleflint", 432, "Jergosh the Invoker", 433, "Bazzalan", 431, "Taragaman the Hungerer" },
			[129] = { 434, "Tuten'kash", 435, "Mordresh Fire Eye", 436, "Glutton", 437, "Amnennar the Coldbringer" },
			[47] = { 438, "Roogug", 440, "Death Speaker Jargba", 439, "Aggem Thorncurse", 441, "Overlord Ramtusk", 883, "Agathelos the Raging", 443, "Charlga Razorflank" },
			[189] = { 445, "Bloodmage Thalnos", 444, "Interrogator Vishas", 446, "Houndmaster Loksey", 447, "Arcanist Doan", 448, "Herod", 449, "High Inquisitor Fairbanks", 450, "High Inquisitor Whitemane" },
			[289] = {  },
			[556] = { 1902, "Talon King Ikiss", 1903, "Darkweaver Syth", 1904, "Anzu" },
			[555] = { 1908, "Ambassador Hellmaw", 1909, "Blackheart the Inciter", 1910, "Murmur", 1911, "Grandmaster Vorpil" },
			[33] = { 464, "Rethilgore", 465, "Razorclaw the Butcher", 466, "Baron Silverlaine", 467, "Commander Springvale", 468, "Odo the Blindwatcher", 469, "Fenrus the Devourer", 470, "Wolf Master Nandos", 471, "Archmage Arugal" },
			[540] = { 1935, "Blood Guard Porung", 1936, "Grand Warlock Nethekurse", 1937, "Warbringer O'mrogg", 1938, "Warchief Kargath Bladefist" },
			[547] = { 1939, "Mennu the Betrayer", 1940, "Quagmirran", 1941, "Rokmar the Crackler" },
			[545] = { 1942, "Hydromancer Thespia", 1943, "Mekgineer Steamrigger", 1944, "Warlord Kalithresh" },
			[34] = {  },
			[329] = { 473, "Hearthsinger Forresten", 474, "Timmy the Cruel", 476, "Commander Malor", 475, "Willey Hopebreaker", 477, "Instructor Galford", 478, "Balnazzar", 472, "The Unforgiven", 479, "Baroness Anastari", 480, "Nerub'enkan", 481, "Maleki the Pallid", 482, "Magistrate Barthilas", 483, "Ramstein the Gorger", 484, "Lord Aurius Rivendare" },
			[109] = { 492, "Avatar of Hakkar", 488, "Jammal'an the Prophet", 486, "Dreamscythe", 487, "Weaver", 490, "Morphaz", 491, "Hazzas", 493, "Shade of Eranikus" },
			[70] = { 547, "Revelosh", 548, "The Lost Dwarves", 549, "Ironaya", 551, "Ancient Stone Keeper", 552, "Galgann Firehammer", 553, "Grimlok", 554, "Archaedas" },
			[546] = { 1945, "Ghaz'an", 1946, "Hungarfen", 1947, "Swamplord Musel'ek", 1948, "The Black Stalker" },
			[43] = { 585, "Lady Anacondra", 586, "Lord Cobrahn", 587, "Kresh", 588, "Lord Pythas", 589, "Skum", 590, "Lord Serpentis", 591, "Verdan the Everliving", 592, "Mutanus the Devourer" },
			[209] = { 593, "Hydromancer Velratha", 594, "Ghaz'rilla", 595, "Antu'sul", 596, "Theka the Martyr", 597, "Witch Doctor Zum'rah", 598, "Nekrum Gutchewer", 599, "Shadowpriest Sezz'ziz", 600, "Chief Ukorz Sandscalp" },
		},
		alias = {},
	}
end

local GENERIC_PLACES = {
	{ key = "anyraid", text = "Any Raid" }, { key = "anydungeon", text = "Any Dungeon" },
	{ key = "bg", text = "Battlegrounds" }, { key = "arena", text = "Arenas" }, { key = "world", text = "Open World" },
}
-- (Missing Warnings and Every Nameplate: every spell's; the saved keys stay missing:on / plates:on)
local PARTS = {
	{ key = "purge:on", text = "Purge Reminder On" }, { key = "purge:off", text = "Purge Reminder Off" },
	{ key = "missing:on", text = "Missing Warnings On" }, { key = "missing:off", text = "Missing Warnings Off" },
	{ key = "plates:on", text = "Every Enemy's Nameplate On" }, { key = "plates:off", text = "Every Enemy's Nameplate Off" },
	{ key = "fs:on", text = "Flame Shock On" }, { key = "fs:off", text = "Flame Shock Off" },
	{ key = "frs:on", text = "Frost Shock On" }, { key = "frs:off", text = "Frost Shock Off" },
	{ key = "ss:on", text = "Stormstrike On" }, { key = "ss:off", text = "Stormstrike Off" },
}
local PART = {}   -- ["purge:on"] = { part, on, text }
for _, p in ipairs(PARTS) do
	local part, state = p.key:match("^(%a+):(%a+)$")
	PART[p.key] = { part, state == "on", p.text }
end

local places   -- built once: list (the place dropdown), name / bosses per map ID, boss names, aliases
local function LocalizedPlaceName(id, fallback)
	local locale = GetLocale and GetLocale()
	if not locale or locale == "enUS" or locale == "enGB" or not GetRealZoneText then return fallback end
	local ok, name = pcall(GetRealZoneText, id)
	if ok and not secret(name) and type(name) == "string" and name ~= "" then return name end
	return fallback
end
local function Places()
	if places then return places end
	local d
	if FOREVER then d = ForeverPlaces() else d = AnniversaryPlaces() end
	local p = { list = {}, name = {}, kind = {}, bosses = d.bosses, alias = d.alias, bossName = {}, who = {} }
	for _, group in ipairs({ { d.raids, "raid" }, { d.dungeons, "dungeon" } }) do
		local t = group[1]
		for i = 1, #t, 2 do
			local id, name = t[i], t[i + 1]
			name = LocalizedPlaceName(id, name)
			p.name[id], p.kind[id] = name, group[2]
			p.list[#p.list + 1] = { key = "map:" .. id, text = name }
		end
	end
	for _, g in ipairs(GENERIC_PLACES) do p.list[#p.list + 1] = { key = g.key, text = g.text } end
	for _, list in pairs(d.bosses) do
		for i = 1, #list, 2 do p.bossName[list[i]] = list[i + 1] end
	end
	places = p
	return p
end

local function MapOf(place)
	return type(place) == "string" and tonumber(place:match("^map:(%d+)$")) or nil
end

local function PlaceText(place)
	for _, g in ipairs(GENERIC_PLACES) do
		if g.key == place then return g.text end
	end
	local id = MapOf(place)
	if id then return Places().name[id] or ("Map " .. id) end
	return "Unknown Place"
end

local function WhoList(place)
	local p = Places()
	local key = tostring(place)
	local list = p.who[key]
	if list then return list end
	list = {}
	local id = MapOf(place)
	-- a boss fight can only be in a raid or a dungeon (or out in the world: its world bosses)
	if id or place == "anyraid" or place == "anydungeon" or place == "world" then
		list[#list + 1] = { key = "anyboss", text = "Any Boss" }
	end
	local bosses = id and p.bosses[id]
	if bosses then
		for i = 1, #bosses, 2 do
			list[#list + 1] = { key = "enc:" .. bosses[i], text = bosses[i + 1] .. " (boss)" }
		end
	end
	list[#list + 1] = { key = "anyone", text = "Anyone" }
	list[#list + 1] = { key = "name", text = "A Target You Name..." }
	p.who[key] = list
	return list
end

local function WhoText(rule)
	local who = rule.who
	if who == "name" then
		if type(rule.name) == "string" and rule.name ~= "" then return rule.name end
		return "A Target You Name..."
	end
	if who == "anyboss" then return "Any Boss" end
	if who == "anyone" then return "Anyone" end
	local enc = type(who) == "string" and tonumber(who:match("^enc:(%d+)$"))
	if enc then
		local name = Places().bossName[enc]
		if name then return name .. " (boss)" end
		return "Boss " .. enc
	end
	return "Anyone"
end

-- ---------------------------------------------------------------------------
-- Where you are and what you are fighting (rules), and whether you are in a
-- fight. On WoW: Forever the game hides some answers ("secret" values): a hidden
-- answer is never compared, not even to nil; it counts as "not known".
-- ---------------------------------------------------------------------------
local zone = { kind = "world", map = nil }
local encounter = { id = nil, name = nil }
local targetName              -- your target's name, where the game shows it (rules that name a target)
local inCombat = InCombatLockdown() and true or false
local overrides, spare = {}, {}   -- [part] = true / false while a rule turns it on / off
local nameRules = false       -- a rule names a target: its name is read on target changes

local function ReadZone()
	local _, instanceType, _, _, _, _, _, mapID = GetInstanceInfo()
	if secret(instanceType) or secret(mapID) then return end
	local kind = "world"
	if instanceType == "raid" then kind = "raid"
	elseif instanceType == "party" or instanceType == "scenario" then kind = "dungeon"
	elseif instanceType == "pvp" then kind = "bg"
	elseif instanceType == "arena" then kind = "arena" end
	zone.kind = kind
	zone.map = nil
	if kind ~= "world" then zone.map = tonumber(mapID) end
end

local function HasNameRules()
	for _, rule in ipairs(SV().rules) do
		if rule.who == "name" then return true end
	end
	return false
end

-- your target's name, only while a rule names one (and only where the game shows it)
local function ReadTargetName()
	targetName = nil
	if not HasNameRules() then return end
	if FOREVER and C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
		local ok, hidden = pcall(C_Secrets.ShouldUnitIdentityBeSecret, "target")
		if not ok or secret(hidden) or hidden then return end
	end
	local ex = UnitExists("target")
	if secret(ex) or not ex then return end
	local name = UnitName("target")
	if secret(name) or type(name) ~= "string" then return end   -- in an instance on WoW: Forever the game hides it
	targetName = strlower(name)
end

local function PlaceMatches(place)
	if place == "world" then return zone.kind == "world" end
	if place == "anyraid" then return zone.kind == "raid" end
	if place == "anydungeon" then return zone.kind == "dungeon" end
	if place == "bg" then return zone.kind == "bg" end
	if place == "arena" then return zone.kind == "arena" end
	local id = MapOf(place)
	return id ~= nil and id == zone.map
end

local function WhoMatches(rule)
	local who = rule.who
	if who == "anyone" then return true end
	if who == "anyboss" then return encounter.id ~= nil end
	if who == "name" then
		local want = type(rule.name) == "string" and strlower(strtrim(rule.name)) or ""
		if want == "" then return false end
		-- the fight's own name counts too: the game names a boss fight at the pull, also where it hides names
		if encounter.name and strlower(encounter.name) == want then return true end
		return targetName ~= nil and targetName == want
	end
	local enc = type(who) == "string" and tonumber(who:match("^enc:(%d+)$"))
	if not (enc and encounter.id) then return false end
	if enc == encounter.id then return true end
	local alias = Places().alias   -- the same boss on another difficulty
	return (alias[encounter.id] or encounter.id) == (alias[enc] or enc)
end

-- What the rules say right now. True when that changed.
local function EvaluateRules()
	wipe(spare)
	local names = false
	for _, rule in ipairs(SV().rules) do
		if rule.who == "name" then names = true end
		local p = PART[rule.part]
		if p and PlaceMatches(rule.place) and WhoMatches(rule) then spare[p[1]] = p[2] end
	end
	nameRules = names
	local changed = false
	for k, v in pairs(spare) do
		if overrides[k] ~= v then changed = true end
	end
	for k, v in pairs(overrides) do
		if spare[k] ~= v then changed = true end
	end
	if changed then overrides, spare = spare, overrides end
	return changed
end

-- ---------------------------------------------------------------------------
-- What the player has
-- ---------------------------------------------------------------------------
local knownCache, usableCache, wasKnown = {}, {}, {}
local function Usable(key)
	local c = usableCache[key]
	if c ~= nil then return c end
	c = false
	for _, id in ipairs(SPELL[key].ids) do
		local has
		if SPCompat and SPCompat.SpellExists then has = SPCompat.SpellExists(id) else has = GetSpellInfo(id) ~= nil end
		if has then c = true break end
	end
	usableCache[key] = c
	return c
end

local function Known(key)
	-- This module drops its events while disabled; the shared spell cache still
	-- advances when a spell is learned or unlearned while its settings are open.
	if knownCache.generation ~= SPCompat.SpellDataGeneration then
		wipe(knownCache)
		knownCache.generation = SPCompat.SpellDataGeneration
	end
	local c = knownCache[key]
	if c ~= nil then return c end
	c = false
	for _, id in ipairs(SPELL[key].ids) do
		if SPCompat.KnowsSpellID(id) then c = true break end
	end
	knownCache[key] = c
	return c
end

-- ---------------------------------------------------------------------------
-- Which parts are on right now
-- ---------------------------------------------------------------------------
local built = false      -- the frames exist (made once the module is first turned on)
local demo = {}          -- debuffs / purge: Unlock UI is showing its stand-ins on that spot
-- Every Nameplate, the nameplate spots and Hide WoW's Own Icons, in one table (not many locals:
-- the main chunk is near Lua's 200-local limit). want / warnWant / lay: worked out once per change.
-- entryOf: [plate] = its Every Nameplate entry; hooked: [WoW's aura frame] = our hook is on it;
-- hidden: [WoW's icon] = hidden by this module, one by one; servedBy: [plate] = the container that
-- redraws WoW's row of your debuffs on it (WoW: Forever); faded: [WoW's row] = faded by this module;
-- gScale / gStride: WoW's nameplate aura scale and row length, as last read off a plate; waiting: units
-- waiting for a free entry (or for the end of a fight); skipped: friendly plates on screen (looked at
-- again at a pull); soon / tried: units placed again on the next frame (once).
local OnPlate = { want = {}, warnWant = {}, lay = {}, entryOf = {}, waiting = {}, skipped = {}, soon = {}, tried = {}, scratch = {},
	hooked = setmetatable({}, { __mode = "k" }), hidden = setmetatable({}, { __mode = "k" }), servedBy = {}, faded = {},
	gwork = {}, gScale = 1, gStride = 8 }
-- Next Shock (D49), in one table too: its frames, the records of your Flame Shock on your targets, the
-- one-shot timer for its last seconds, and its functions (further down, once the frames and the engine
-- are known). recs: [target GUID] = { start, duration }; cur: your current target's; learned: [spell ID]
-- = Flame Shock's duration as read off the aura; last: your last Flame Shock cast. BASE: Flame Shock's
-- duration in each client's own spell data (SpellMisc DurationIndex 29 -> SpellDuration 12000 ms, every
-- rank and every Flame Shock aura ID, on WoW: Forever 1.60.1 and TBC Anniversary 2.5.6: read 2026-10-04).
local NS = { recs = {}, learned = {}, last = { id = nil, t = 0 }, BASE = 12, plain = { border = "thin", size = 36 },
	lk = { border = "thin" }, EARTH = "Interface\\Icons\\Spell_Nature_EarthShock" }

local function ModuleOn()
	return built and SV().enabled == true and not SP:IsOff()
end

local function ZoneOK(key) return Get(key, "w_" .. zone.kind) and true or false end

-- Flame Shock, Frost Shock, Stormstrike or Purge: on in this place (a rule wins over the spell's own setting)
local function PartOn(key)
	local o = overrides[key]
	if o ~= nil then return o end
	return Get(key, "shown") and ZoneOK(key)
end
-- a spell's Missing Warning and its Every Nameplate: the spell's own switch, only while the spell
-- itself is on here (Hide This Spell hides them too); a "Missing Warnings" / "Every Nameplate" rule
-- turns every spell's on or off
local function MissingOn(key)
	if key == "purge" or not (PartOn(key) and Known(key)) then return false end
	local o = overrides.missing
	if o == nil then o = Get(key, "missing") end
	return o == true
end
local function PlatesOn(key)
	if not (PartOn(key) and Known(key)) then return false end
	local o = overrides.plates
	if o == nil then o = Get(key, "everyPlate") end
	return o == true
end
local function ModeOK(key)
	local m = Get(key, "show")
	if m == "combat" then return inCombat end
	if m == "nocombat" then return not inCombat end
	return true
end
-- has a spot in the row (its Missing Warning shows in that spot too)
local function DebuffInPlay(key)
	return Known(key) and PartOn(key) and true or false
end
local function CellWanted(key)
	return DebuffInPlay(key) and ModeOK(key)
end
local function PurgeWanted()
	return Known("purge") and PartOn("purge") and ModeOK("purge")
end
-- anything on your target in this place (in a fight or out of it), or a rule here that can turn
-- one on at a pull: the target gate is needed (it cannot be set up in a fight)
local TARGET_PARTS = { fs = true, frs = true, ss = true, purge = true, missing = true }
local function TargetNeeded()
	for _, key in ipairs(DEBUFFS) do
		if DebuffInPlay(key) then return true end
	end
	if Known("purge") and PartOn("purge") then return true end
	for _, rule in ipairs(SV().rules) do
		local p = PART[rule.part]
		if p and p[2] and TARGET_PARTS[p[1]] and PlaceMatches(rule.place) then return true end
	end
	return false
end

-- what each spell does on the enemy nameplates right now, worked out once per change (never per
-- plate): lay = on every enemy plate here (a spot in the plate's row), want = it shows right now
-- (its When), warnWant = its Missing Warning shows right now. True when any spell is on the plates.
function OnPlate.Compute()
	local any = false
	for _, s in ipairs(SPELLS) do
		local key = s.key
		local lay = PlatesOn(key)
		OnPlate.lay[key] = lay
		OnPlate.want[key] = lay and ModeOK(key) or false
		OnPlate.warnWant[key] = MissingOn(key) and ModeOK(key) or false
		if lay then any = true end
	end
	OnPlate.anyLay = any
	return any
end

-- ---------------------------------------------------------------------------
-- Settings changes reach the settings rows (TT_Watch), once, on the next frame
-- ---------------------------------------------------------------------------
local watchers, watchQueued = {}, false
local function RunWatchers()
	watchQueued = false
	for i = 1, #watchers do
		local ok, err = pcall(watchers[i])
		if not ok then geterrorhandler()(err) end
	end
end
local function Watch()
	if #watchers > 0 and not watchQueued then
		watchQueued = true
		C_Timer.After(0, RunWatchers)
	end
end
local Changed, Update, Apply   -- (further down, once the frames are known)

-- ---------------------------------------------------------------------------
-- The art. One of your debuffs as the game's aura button draws it: the icon in a
-- 1 px black edge, the time-left sweep, the time left and (Stormstrike) its
-- charges. The same parts go on the game's own aura buttons (WoW: Forever), on
-- the icons filled in here (Anniversary) and on the stand-ins (Unlock UI, the
-- settings preview). Each part a setting can turn off sits on a frame of its own
-- (its carrier), so a look changes on the parts already there: nothing is made again.
-- ---------------------------------------------------------------------------
local function NoMouse(f)
	if f.SetMouseClickEnabled then pcall(f.SetMouseClickEnabled, f, false) end
	if f.SetMouseMotionEnabled then pcall(f.SetMouseMotionEnabled, f, false) end
end

local function TimeSize(size) return max(9, floor(size * 0.42 + 0.5)) end
local function CountSize(size) return max(8, floor(size * 0.34 + 0.5)) end
local function WordSize(size) return max(10, floor(size * 0.22 + 0.5)) end

local function Outline(fs)
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(1, -1)
end

local function Carrier(host, level)
	local f = CreateFrame("Frame", nil, host)
	f:SetAllPoints(host)
	if level then f:SetFrameLevel(level) end
	return f
end

-- The vertical sweeps, as on the cooldown bar. Grays Out grows a gray copy over the icon;
-- Fills Back In grows a colored copy over gray. Sweep Direction chooses the starting edge.
-- Both are one vertical bar the game moves itself (StatusBar:SetTimerDuration, or the
-- game's aura button on WoW: Forever), always by the time gone. Nothing here runs per frame.
local VERTICAL = { greys = true, fills = true }
local ICON_TRIM = 0.08 / 0.84   -- the icon's crop (SetTexCoord 0.08 .. 0.92), as a share of what shows
local function SweepBarShown(p)
	local look = p.look
	return look ~= nil and VERTICAL[look.sweep] and not p.vfail and not p.missing and (p.engine or p.vrun) and true or false
end
local function SweepBarArt(p, look)
	if not p.vbar then return end
	local inner = max(1, (look.size or 36) - 2)
	local m = ICON_TRIM * inner
	p.vbar:ClearAllPoints()
	p.vbar:SetPoint("TOPLEFT", p.vclip, "TOPLEFT", -m, m)
	p.vbar:SetPoint("BOTTOMRIGHT", p.vclip, "BOTTOMRIGHT", m, -m)
	p.vbg:ClearAllPoints()
	p.vbg:SetAllPoints(p.vbar)
	-- The bar always fills from the bottom: a bar filled from its top edge stretches the icon's
	-- copy in the game instead of cropping it (a squashed icon over a hard edge). So the way it
	-- runs comes from the timer: From The Top counts the time left (the bar shrinks down to the
	-- bottom), From The Bottom the time gone (it grows up). Grays Out from the top: the color
	-- copy fills, over a gray one; Fills Back In from the top: the gray copy fills. From the
	-- bottom it is the other way round.
	-- the picture its copies show: the icon's own, or (Flame Shock with Next Shock on) the shock it shows
	local art = NS.Art(p.key)
	if p.vart ~= art then
		p.vart = art
		p.vbg:SetTexture(art)
		p.vbar:SetStatusBarTexture(art)
	end
	local fills = look.sweep == "fills"
	local direction = look.sweepDirection
	if direction == nil then direction = fills and "bottom" or "top" end
	local top = direction == "top"
	local colored = (fills and not top) or (top and not fills)
	p.vbar:SetReverseFill(false)
	if p.vbar.SetStatusBarDesaturated then p.vbar:SetStatusBarDesaturated(not colored) end
	if colored then p.vbar:SetStatusBarColor(1, 1, 1, 1) else p.vbar:SetStatusBarColor(0.5, 0.5, 0.5, 1) end
	local tex = p.vbar:GetStatusBarTexture()
	if tex then
		tex:SetDesaturated(not colored)
		if colored then tex:SetVertexColor(1, 1, 1) else tex:SetVertexColor(0.5, 0.5, 0.5) end
	end
	p.vbg:SetShown(colored)
	-- the timer's way changed: hand the bar over again (the game's aura button), or start ours again
	if p.vtop ~= top then
		p.vtop = top
		local Dir = Enum and Enum.StatusBarTimerDirection
		local way = Dir and (top and Dir.RemainingTime or Dir.ElapsedTime)
		if p.engine and p.button then
			if not (way and p.button.SetDurationBar and pcall(p.button.SetDurationBar, p.button, p.vbar, { direction = way })) then
				p.vfail = true
			end
		elseif p.vrun and p.vdur and way then
			local Interp = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
			pcall(p.vbar.SetTimerDuration, p.vbar, p.vdur, Interp, way)
		end
	end
end
local function SweepBarRefresh(p)
	if p.vclip then p.vclip:SetShown(SweepBarShown(p)) end
end

-- ---------------------------------------------------------------------------
-- Icon Edge (each spell's Look) and Look When Missing (each debuff's Look), drawn with
-- the parts already made, plus a few made the first time a look needs them. On WoW:
-- Forever a debuff that is on covers its Missing warning (the warning sits under the
-- game's button), so a warning never reaches further out than that spell's own edge
-- does: a solid edge 1 px (Thin Black, Spell Color) or 3 px (Thick Black), None and
-- Dotted nothing. The same rule on both clients, so both look the same.
-- ---------------------------------------------------------------------------
local LK = {
	REACH = { thin = 1, spell = 1, thick = 3, none = 0, dotted = 0 },
	ELEMENT = { fs = "fire", frs = "water", ss = "air" },
}
function LK.SpellColor(key)
	if key == "purge" then return MAGIC[1], MAGIC[2], MAGIC[3] end
	local el = LK.ELEMENT[key]
	if el and SP.BrandElementRGB then
		local r, g, b = SP:BrandElementRGB(el)
		if r then return r, g, b end
	end
	return 1, 1, 1
end
-- a dotted line round the host: dashes d long, gaps about gap, t thick, o px outside
-- (made the first time, then moved and reused)
function LK.Dots(p, size, t, d, gap, o, r, g, b, layer)
	local host = p.host
	p.dots = p.dots or {}
	local len = size + 2 * o
	local n = max(2, floor((len + gap) / (d + gap) + 0.5))
	local step = (len - d) / (n - 1)
	local used = 0
	local function dot(x, y, w, h)
		used = used + 1
		local tx = p.dots[used]
		if not tx then
			tx = host:CreateTexture(nil, layer, nil, 1)
			p.dots[used] = tx
		end
		tx:SetDrawLayer(layer, 1)
		tx:ClearAllPoints()
		tx:SetPoint("TOPLEFT", host, "TOPLEFT", x, -y)
		tx:SetSize(w, h)
		tx:SetColorTexture(r, g, b, 1)
		tx:Show()
	end
	for i = 0, n - 1 do
		local q = -o + i * step
		dot(q, -o, d, t)
		dot(q, size + o - t, d, t)
		if i > 0 and i < n - 1 then
			dot(-o, q, t, d)
			dot(size + o - t, q, t, d)
		end
	end
	for i = used + 1, #p.dots do p.dots[i]:Hide() end
end
function LK.HideDots(p)
	if p.dots then for i = 1, #p.dots do p.dots[i]:Hide() end end
end
-- the solid edge, o px outside the host (behind the icon: it shows round it)
function LK.Solid(p, o, r, g, b)
	p.edge:ClearAllPoints()
	p.edge:SetPoint("TOPLEFT", p.host, "TOPLEFT", -o, o)
	p.edge:SetPoint("BOTTOMRIGHT", p.host, "BOTTOMRIGHT", o, -o)
	p.edge:SetColorTexture(r, g, b, 1)
	p.edge:Show()
end
-- the icon on the host, inset px in from its rim
function LK.IconAt(p, inset)
	p.icon:ClearAllPoints()
	p.icon:SetPoint("TOPLEFT", p.host, "TOPLEFT", inset, -inset)
	p.icon:SetPoint("BOTTOMRIGHT", p.host, "BOTTOMRIGHT", -inset, inset)
end
function LK.ExtrasOff(p)
	if p.mglow then p.mglow:Hide() end
	if p.wash then p.wash:Hide() end
	if p.slash then p.slash:Hide() end
	if p.pulse then p.pulse:Stop() end
	p.edge:SetAlpha(1)
	LK.HideDots(p)
end
-- an icon that is on: its spell's Icon Edge (Purge's icon itself is left as it is)
function LK.Edge(p, key, look, purge)
	local style = look.border or "thin"
	local size = look.size or 36
	LK.ExtrasOff(p)
	if not purge then
		LK.IconAt(p, 0)
		p.icon:SetDesaturated(false)
		p.icon:SetVertexColor(1, 1, 1)
		p.icon:SetAlpha(1)
	end
	if style == "none" then
		p.edge:Hide()
	elseif style == "thick" then
		LK.Solid(p, 3, 0, 0, 0)
	elseif style == "spell" then
		local r, g, b = LK.SpellColor(key)
		LK.Solid(p, 1, r, g, b)
	elseif style == "dotted" then
		p.edge:Hide()
		LK.Dots(p, size, 1, size >= 30 and 3 or 2, 2, 1, 0, 0, 0, "BACKGROUND")
	else
		LK.Solid(p, 1, 0, 0, 0)   -- Thin Black (as before)
	end
end
-- a debuff's Missing warning: its Look When Missing, reaching no further out than its edge
function LK.Missing(p, key, look)
	local style = look.missLook or "edge"
	local size = look.size or 36
	local reach = LK.REACH[look.border or "thin"] or 1
	local o = min(1, reach)
	LK.ExtrasOff(p)
	p.edge:Hide()
	LK.IconAt(p, 0)
	p.icon:SetDesaturated(true)
	p.icon:SetVertexColor(0.55, 0.55, 0.55)
	p.icon:SetAlpha(0.85)
	if style == "edge" or style == "pulse" then
		-- a red ring 2 px wide: as before, one px outside the icon and one over its rim
		LK.Solid(p, o, RED[1], RED[2], RED[3])
		LK.IconAt(p, 2 - o)
		if style == "pulse" then
			if not p.pulse then
				p.pulse = p.edge:CreateAnimationGroup()
				p.pulse:SetLooping("BOUNCE")
				local a = p.pulse:CreateAnimation("Alpha")
				a:SetFromAlpha(1)
				a:SetToAlpha(0.3)
				a:SetDuration(0.8)
			end
			p.pulse:Play()
		end
	elseif style == "dotted" then
		LK.Dots(p, size, 2, size >= 30 and 4 or 3, 3, o, RED[1], RED[2], RED[3], "OVERLAY")
	elseif style == "faded" then
		p.icon:SetVertexColor(0.6, 0.6, 0.6)
		p.icon:SetAlpha(0.45)
	elseif style == "glow" then
		if not p.mglow then
			p.mglow = p.host:CreateTexture(nil, "ARTWORK", nil, 3)
			p.mglow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
			p.mglow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
			p.mglow:SetBlendMode("ADD")
		end
		p.mglow:SetAllPoints(p.host)
		p.mglow:SetVertexColor(RED[1], RED[2], RED[3])
		p.mglow:SetAlpha(0.9)
		p.mglow:Show()
	elseif style == "tint" then
		p.icon:SetAlpha(1)
		if not p.wash then p.wash = p.host:CreateTexture(nil, "ARTWORK", nil, 2) end
		p.wash:SetAllPoints(p.icon)
		p.wash:SetColorTexture(RED[1], RED[2], RED[3], 0.55)
		p.wash:Show()
		if reach >= 1 then LK.Solid(p, 1, 0, 0, 0) end
	elseif style == "slash" then
		if reach >= 1 then LK.Solid(p, 1, 0, 0, 0) end
		if not p.slash and p.host.CreateLine then p.slash = p.host:CreateLine(nil, "OVERLAY", nil, 2) end
		if p.slash then
			p.slash:SetColorTexture(RED[1], RED[2], RED[3], 1)
			p.slash:SetThickness(size >= 30 and 3 or 2)
			p.slash:SetStartPoint("TOPRIGHT", p.host, -2, -2)
			p.slash:SetEndPoint("BOTTOMLEFT", p.host, 2, 2)
			p.slash:Show()
		end
	elseif style == "outline" then
		p.icon:SetAlpha(0)
		LK.Dots(p, size, 2, size >= 30 and 4 or 3, 3, 0, RED[1], RED[2], RED[3], "OVERLAY")
	end
end

-- the look on parts already made: fonts for the size, which parts show
local function StyleDebuff(p, look)
	if p.size ~= look.size then
		SP:SetSPFont(p.time, "timers", TimeSize(look.size), "OUTLINE")
		SP:SetSPFont(p.count, "alerts", CountSize(look.size), "OUTLINE")
		p.size = look.size
	end
	SweepBarArt(p, look)
	-- a vertical sweep this icon can't draw (no bar the game moves on this client): the clock instead
	local sweep = look.sweep
	if VERTICAL[sweep] and p.vfail then sweep = "radial" end
	if p.ownNumbers then
		-- the Cooldown's own numbers show the time left here (a client without a duration binding):
		-- the Cooldown carries both, so Sweep and Time Left switch its own sweep and numbers
		p.sweep:SetShown(true)
		if p.cd.SetDrawSwipe then p.cd:SetDrawSwipe(sweep == "radial") end
		p.cd:SetHideCountdownNumbers(not look.timeLeft)
	else
		p.sweep:SetShown(sweep ~= "none")
		if p.cd.SetDrawSwipe then p.cd:SetDrawSwipe(sweep == "radial") end
	end
	p.look = look
	if p.missing then LK.Missing(p, p.key, look) else LK.Edge(p, p.key, look) end
	SweepBarRefresh(p)
	p.text:SetShown(look.timeLeft and true or false)
	p.charges:SetShown(look.charges and true or false)
	p.look = look
end

-- host: the frame the parts go on (sized by its anchors); returns the parts
local function DebuffParts(host, key, look)
	local p = { host = host, key = key }
	p.edge = host:CreateTexture(nil, "BACKGROUND")
	p.edge:SetPoint("TOPLEFT", host, "TOPLEFT", -1, 1)
	p.edge:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 1, -1)
	p.edge:SetColorTexture(0, 0, 0, 1)
	p.icon = host:CreateTexture(nil, "ARTWORK")
	p.icon:SetPoint("TOPLEFT", p.edge, "TOPLEFT", 1, -1)
	p.icon:SetPoint("BOTTOMRIGHT", p.edge, "BOTTOMRIGHT", -1, 1)
	p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	p.icon:SetTexture(SPELL[key].icon)
	p.sweep = Carrier(host)
	p.cd = CreateFrame("Cooldown", nil, p.sweep, "CooldownFrameTemplate")
	p.cd:SetAllPoints(host)
	p.cd:SetReverse(true)   -- the dark part grows as the time runs out, as on WoW's target frame
	if p.cd.SetDrawEdge then p.cd:SetDrawEdge(false) end
	if p.cd.SetDrawBling then p.cd:SetDrawBling(false) end
	p.cd:SetHideCountdownNumbers(true)
	p.cd.noCooldownCount = true   -- (OmniCC and the like: the time left is drawn here)
	-- the vertical sweeps' bar (Grays Out / Fills Back In): clipped to the icon, a copy of the icon
	-- cropped as the icon is (the bar stands past the clip by the crop), over a gray copy for Fills Back In
	p.vclip = CreateFrame("Frame", nil, p.sweep)
	p.vclip:SetAllPoints(p.icon)
	p.vclip:SetClipsChildren(true)
	p.vclip:SetFrameLevel(p.cd:GetFrameLevel())
	p.vbg = p.vclip:CreateTexture(nil, "BACKGROUND")
	p.vbg:SetTexture(SPELL[key].icon)
	p.vbg:SetDesaturated(true)
	p.vbg:SetVertexColor(0.5, 0.5, 0.5)
	p.vbar = CreateFrame("StatusBar", nil, p.vclip)
	p.vbar:SetOrientation("VERTICAL")
	-- the texture cropped to the fill, never stretched (the game's enum: Anniversary takes only that, not the string)
	local fillStyle = Enum and Enum.StatusBarFillStyle and Enum.StatusBarFillStyle.Standard
	if p.vbar.SetFillStyle then p.vbar:SetFillStyle(fillStyle or "STANDARD") end
	p.vbar:SetMinMaxValues(0, 1)
	p.vbar:SetValue(0)
	p.vbar:SetStatusBarTexture(SPELL[key].icon)
	p.vclip:Hide()
	local over = p.cd:GetFrameLevel() + 2
	p.text = Carrier(host, over)
	p.time = p.text:CreateFontString(nil, "OVERLAY")
	p.time:SetFontObject(GameFontHighlight)   -- a font at once: the game's button writes into it before ours is set
	p.time:SetPoint("CENTER", host, "CENTER", 0, 0)
	p.time:SetTextColor(1, 1, 1)
	Outline(p.time)
	p.charges = Carrier(host, over)
	p.count = p.charges:CreateFontString(nil, "OVERLAY")
	p.count:SetFontObject(GameFontHighlight)
	p.count:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -1, 2)
	p.count:SetTextColor(1, 1, 1)
	Outline(p.count)
	StyleDebuff(p, look)
	return p
end

-- the Missing look: the spell gray, in its Look When Missing (Red Edge to start: a red
-- edge 2 px wide, so the real Flame Shock drawn on top covers it all), and back
local function MissingLook(p, on)
	p.missing = on and true or nil
	if on then
		LK.Missing(p, p.key, p.look or {})
		p.cd:Clear()
		p.time:SetText("")
		p.count:SetText("")
		if p.vclip then p.vclip:Hide() end
	else
		LK.Edge(p, p.key, p.look or {})
	end
	SweepBarRefresh(p)
	if p.nsF then NS.Shown(p) end   -- (Next Shock's face never on a Missing Warning)
end

local function StylePurge(p, look)
	if p.size ~= look.size then
		local pad = floor(look.size * 0.2 + 0.5)
		p.glow:ClearAllPoints()
		p.glow:SetPoint("TOPLEFT", p.host, "TOPLEFT", -pad, pad)
		p.glow:SetPoint("BOTTOMRIGHT", p.host, "BOTTOMRIGHT", pad, -pad)
		SP:SetSPFont(p.word, "alerts", WordSize(look.size), "OUTLINE")
		local bs = max(12, floor(look.size * 0.42 + 0.5))
		p.badge:SetSize(bs, bs)
		p.size = look.size
	end
	p.glow:SetShown(look.glow and true or false)
	if look.glow then
		if not p.glowAnim:IsPlaying() then p.glowAnim:Play() end
	else
		p.glowAnim:Stop()
	end
	p.word:SetShown(look.word and true or false)
	-- off: still there (the game's button wants a picture to paint), never seen
	p.badge:SetAlpha(look.picture and 1 or 0)
	p.look = look
	LK.Edge(p, "purge", look, true)
end

-- Purge: the big icon, WoW's spell-alert glow behind it in gold (breathing: an
-- animation the game plays), PURGE under it on screen, and the buff's picture
-- beside it (the picture, never its name: in a fight on WoW: Forever the game
-- hides the name). blend: "BLEND" for a boss's copy, so two never add up.
local function PurgeParts(host, look, blend)
	local p = { host = host }
	p.glow = host:CreateTexture(nil, "BACKGROUND", nil, -1)
	p.glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
	p.glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
	if SP.ShapeGlow then SP:ShapeGlow(p.glow, "alert") end   -- (General > Themes: Glow Shape)
	p.glow:SetBlendMode(blend or "ADD")
	p.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
	p.glow:SetAlpha(0.6)
	p.glowAnim = p.glow:CreateAnimationGroup()
	p.glowAnim:SetLooping("BOUNCE")
	local a = p.glowAnim:CreateAnimation("Alpha")
	a:SetFromAlpha(blend and 0.25 or 0.35)
	a:SetToAlpha(blend and 0.6 or 0.9)
	a:SetDuration(0.5)
	p.edge = host:CreateTexture(nil, "BACKGROUND")
	p.edge:SetPoint("TOPLEFT", host, "TOPLEFT", -1, 1)
	p.edge:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 1, -1)
	p.edge:SetColorTexture(0, 0, 0, 1)
	p.icon = host:CreateTexture(nil, "ARTWORK")
	p.icon:SetAllPoints(host)
	p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	p.icon:SetTexture(SPELL.purge.icon)
	p.over = Carrier(host, host:GetFrameLevel() + 3)
	p.word = p.over:CreateFontString(nil, "OVERLAY")
	p.word:SetFontObject(GameFontHighlight)   -- before its SetText below ("Font not set" otherwise)
	p.word:SetPoint("TOP", host, "BOTTOM", 0, -4)
	p.word:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	Outline(p.word)
	p.word:SetText("PURGE")
	-- the buff's picture, in its own 1 px black edge, beside the icon
	p.badge = CreateFrame("Frame", nil, p.over)
	p.badge:SetPoint("BOTTOMLEFT", host, "BOTTOMRIGHT", 6, 0)
	local bedge = p.badge:CreateTexture(nil, "BACKGROUND")
	bedge:SetPoint("TOPLEFT", p.badge, "TOPLEFT", -1, 1)
	bedge:SetPoint("BOTTOMRIGHT", p.badge, "BOTTOMRIGHT", 1, -1)
	bedge:SetColorTexture(0, 0, 0, 1)
	p.pic = p.badge:CreateTexture(nil, "ARTWORK")
	p.pic:SetAllPoints(p.badge)
	p.pic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	StylePurge(p, look)
	return p
end

-- ---------------------------------------------------------------------------
-- The time left on an icon of our own, drawn by the game: a duration text
-- binding updates the number itself (no Lua each frame); a client without one
-- gets the Cooldown's own numbers (WoW's "Show Numbers for Cooldowns").
-- ---------------------------------------------------------------------------
local timeFormatter, countFormatter   -- nil: not made yet; false: this client cannot
local function TimeFormatter()
	if timeFormatter ~= nil then return timeFormatter or nil end
	timeFormatter = false
	local S = C_StringUtil
	if not (S and S.CreateNumericRuleFormatter) then return nil end
	local ok, f = pcall(S.CreateNumericRuleFormatter)
	if not (ok and f and f.AddBreakpoint) then return nil end
	local up = Enum and Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Up or 1
	-- whole seconds (rounded up, as WoW counts down); from a minute on, minutes
	local okS = pcall(f.AddBreakpoint, f, { threshold = 0, step = 1, rounding = up, format = "%d" })
	pcall(f.AddBreakpoint, f, { threshold = 60, format = "%dm", components = { { div = 60, step = 1, rounding = up } } })
	if okS then timeFormatter = f end
	return timeFormatter or nil
end
-- Stormstrike's charges: every count shows, 1 too (by default the game hides a stack of 1)
local function CountFormatter()
	if countFormatter ~= nil then return countFormatter or nil end
	countFormatter = false
	local S = C_StringUtil
	if not (S and S.CreateNumericRuleFormatter) then return nil end
	local ok, f = pcall(S.CreateNumericRuleFormatter)
	if ok and f and f.AddBreakpoint and pcall(f.AddBreakpoint, f, { threshold = 1, format = "%d" }) then countFormatter = f end
	return countFormatter or nil
end

-- the vertical sweep's bar on an icon drawn here: the game moves it by the time gone, from a
-- duration of the icon's own (made once); a client without it shows the clock instead
local function SweepBarStart(p, start, duration)
	if not p.vbar or p.engine then return end
	if p.vdur == nil then
		local D = C_DurationUtil
		local ok, d = false, nil
		if D and D.CreateDuration then ok, d = pcall(D.CreateDuration) end
		p.vdur = (ok and d) or false
	end
	local Dir = Enum and Enum.StatusBarTimerDirection
	local Interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
	local ok = p.vdur and Dir and pcall(p.vdur.SetTimeFromStart, p.vdur, start, duration)
		and pcall(p.vbar.SetTimerDuration, p.vbar, p.vdur, Interp, p.vtop and Dir.RemainingTime or Dir.ElapsedTime)
	if not ok then
		if not p.vfail then
			p.vfail = true
			if p.look then StyleDebuff(p, p.look) end
		end
		return
	end
	p.vrun = true
	SweepBarRefresh(p)
end
local function SweepBarStop(p)
	if p.vrun then
		p.vrun = nil
		SweepBarRefresh(p)
	end
end

local function StopTime(p)
	if p.binding then pcall(p.binding.SetEnabled, p.binding, false) end
	p.cd:Clear()
	p.time:SetText("")
	SweepBarStop(p)
end

local function ShowTime(p, start, duration)
	if not (duration and duration > 0) then
		StopTime(p)
		return
	end
	if p.binding == nil then
		p.binding = false
		local D = C_DurationUtil
		if D and D.CreateDurationTextBinding and D.CreateDuration then
			local ok, b = pcall(D.CreateDurationTextBinding)
			local okD, d = pcall(D.CreateDuration)
			if ok and b and okD and d and pcall(b.SetFontString, b, p.time) then
				local f = TimeFormatter()
				if f then pcall(b.SetFormatter, b, f) end
				if b.SetExpiredText then pcall(b.SetExpiredText, b, "") end
				p.binding, p.duration = b, d
			end
		end
	end
	p.cd:SetCooldown(start, duration)
	SweepBarStart(p, start, duration)
	if p.binding then
		pcall(p.duration.SetTimeFromStart, p.duration, start, duration)
		pcall(p.binding.SetDuration, p.binding, p.duration)
		pcall(p.binding.SetEnabled, p.binding, true)
	elseif not p.ownNumbers then
		-- no binding on this client: the Cooldown's own numbers stand in (Time Left and Sweep then
		-- switch them on the Cooldown itself)
		p.ownNumbers = true
		StyleDebuff(p, p.look)
	end
end

-- ---------------------------------------------------------------------------
-- The frames. H.debuffs and H.purge are the two spots (Unlock UI's boxes); a
-- cell per debuff sits in H.debuffs; H.bossSpot is where a boss's Purge shows
-- (Purge's spot, or its screen spot while your target has no nameplate to sit on).
-- ---------------------------------------------------------------------------
local H = {}            -- debuffs, purge, bossSpot, plates (every nameplate's parent)
local cells = {}        -- [debuff key] = { frame, slot (has a spot in the row), p (an icon of ours), g (its spot under the gate) }
local K = {
	TARGET = "[@target,harm,nodead] show; hide",   -- the one gate: an attackable target that is alive
	PLATE_SCALE = 0.7, PURGE_PLATE_SCALE = 0.6,     -- on a nameplate: smaller
	FRAME_X = 8, FRAME_Y = -12,                     -- under the target frame: from its bottom left corner
	-- where the spots start: right of the middle, clear of the other modules' starting spots (Next Shock's
	-- right of Purge's, clear of its buff picture)
	SPOT = { debuffs = { anchor = "CENTER", x = 200, y = -60 }, purge = { anchor = "CENTER", x = 200, y = 40 },
		ns = { anchor = "CENTER", x = 330, y = 40 } },
	POOL = 40,                                      -- nameplate entries made ahead, so a fight never has to make one
	-- no Missing Warning on these kinds of enemy (WoW's creature types): a critter, a totem, a pet, a gas cloud
	NOWARN = { [8] = true, [11] = true, [12] = true, [13] = true },
	-- nameplate addons that hide WoW's own nameplate (theirs sits on the same plate)
	PLATE_ADDONS = { "Plater", "Kui_Nameplates", "TidyPlates_ThreatPlates", "TidyPlates", "NeatPlates" },
	-- WoW's own nameplate row of your debuffs (Blizzard_NamePlates): icons 25 high times the plate's aura
	-- scale (WoW's aura scale option times its nameplate size's: size = Small .. Huge), side by side with no
	-- gap, no numbers on one that lasts longer than a minute. Hide WoW's Own Icons has the game redraw it
	-- with this aura filter, without Target Tracker's spells, at most 10 (one batch of the game's frames,
	-- made ahead: never more made in a fight)
	GAME = { item = 25, max = 10, long = 60, filter = "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY",
		size = { 0.75, 1, 1.25, 1.4, 1.6 } },
	BIT = { fs = 1, frs = 2, ss = 4 },   -- each debuff's bit in the mask of the spells shown on a plate
	-- WoW's own nameplate options that change that row: whether it shows (its Personal Debuffs for enemy
	-- NPCs, Debuffs for enemy players), all of your debuffs or only the ones marked for nameplates, its size
	GAME_CVARS = { nameplateEnemyNpcAuraDisplay = true, nameplateEnemyPlayerAuraDisplay = true,
		nameplateShowAllPersonalAuras = true, nameplateAuraScale = true, nameplateSize = true },
}
local blockH = 0        -- the debuffs' block height, as last laid out (Purge goes under it below the target frame)
local pending = {}      -- build / look / driver: wanted while a fight was on, done when it ends
local placed = { debuffs = true, purge = true, ns = true }   -- false: on a nameplate that is not there right now

local function EnsureHolders()
	if H.debuffs then return end
	local function spot(name, label, size)
		local f = CreateFrame("Frame", name, UIParent)
		f:SetSize(size, size)
		f:SetMovable(true)
		f:SetClampedToScreen(true)
		f:EnableMouse(false)
		f:Hide()
		f.spMoverLabel = label   -- Unlock UI's box
		return f
	end
	H.debuffs = spot("ShamanPowerTargetTrackerDebuffs", "Target Tracker", 36)
	H.purge = spot("ShamanPowerTargetTrackerPurge", "Target Tracker: Purge", 64)
	H.ns = spot("ShamanPowerTargetTrackerNextShock", "Target Tracker: Next Shock", 64)   -- Next Shock's spot
	-- shown while Purge is on (here and now): what it shows sits in it (Anniversary's icon)
	H.purgeCell = CreateFrame("Frame", nil, H.purge)
	H.purgeCell:SetAllPoints(H.purge)
	H.purgeCell:Hide()
	H.bossSpot = CreateFrame("Frame", nil, UIParent)
	H.bossSpot:SetSize(64, 64)
	H.bossSpot:SetPoint("CENTER")
	H.plates = CreateFrame("Frame", nil, UIParent)   -- every nameplate's row (Every Nameplate) hangs off this one
	H.plates:SetSize(1, 1)
	H.plates:SetPoint("CENTER")
	H.plates:Hide()
end

-- off screen, where a spot waits while the nameplate it sits on is not there (the
-- game's buttons hang off it by their anchors: they go with it, nothing is touched)
local function Park(f)
	f:SetClampedToScreen(false)
	f:ClearAllPoints()
	f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -400, -400)
end

local function TargetPlate()
	local N = C_NamePlate
	if not (N and N.GetNamePlateForUnit) then return nil end
	local ok, plate = pcall(N.GetNamePlateForUnit, "target")
	if not ok or secret(plate) or plate == nil then return nil end
	return plate
end

local function PlateOf(unit)
	local N = C_NamePlate
	if not (N and N.GetNamePlateForUnit) or secret(unit) or type(unit) ~= "string" then return nil end
	local ok, plate = pcall(N.GetNamePlateForUnit, unit)
	if not ok or secret(plate) or plate == nil then return nil end
	return plate
end

-- the debuffs in a row or a column inside `holder`; frameOf(key) gives each spell's
-- frame; keys: the spells with a spot, in order. Returns the block's size.
local function LayoutRow(holder, keys, frameOf, scale)
	local sv = SV()
	local column = sv.arrange == "column"
	local gap = sv.spacing or 6
	local total, thick = 0, 0
	for i, key in ipairs(keys) do
		local s = Get(key, "size") * (scale or 1)
		total = total + s
		if i > 1 then total = total + gap end
		if s > thick then thick = s end
	end
	local at = 0
	for _, key in ipairs(keys) do
		local f, s = frameOf(key), Get(key, "size") * (scale or 1)
		f:SetSize(s, s)
		f:ClearAllPoints()
		if column then
			f:SetPoint("TOP", holder, "TOP", 0, -at)
		else
			f:SetPoint("LEFT", holder, "LEFT", at, 0)
		end
		at = at + s + gap
	end
	if column then return max(thick, 1), max(total, 1) end
	return max(total, 1), max(thick, 1)
end

local inPlay = {}   -- (scratch) the debuffs with a spot, in order
local function CellFrame(key) return cells[key].frame end

local function LayoutDebuffs()
	wipe(inPlay)
	for _, key in ipairs(DEBUFFS) do
		if cells[key] and DebuffInPlay(key) then inPlay[#inPlay + 1] = key end
	end
	for key, c in pairs(cells) do
		c.slot = false
		for _, k in ipairs(inPlay) do
			if k == key then c.slot = true end
		end
	end
	local w, h = LayoutRow(H.debuffs, inPlay, CellFrame)
	if demo.debuffs then return end   -- (Unlock UI's stand-ins size the spot meanwhile)
	H.debuffs:SetSize(w, h)
	blockH = (#inPlay > 0) and h or 0
end

-- ---------------------------------------------------------------------------
-- Where things sit on an enemy's nameplate (your target's, and every enemy's with
-- Every Nameplate). Both game versions build their nameplates the same way (read
-- from each client's own Blizzard_NamePlates code): a unit frame with the health
-- bar (HealthBarsContainer), the cast bar under it, the name above it, the raid
-- mark left of it and, on WoW: Forever, the level badge right of it (on
-- Anniversary that badge never shows). The plate frame itself reaches far above
-- the name: never its top.
-- ---------------------------------------------------------------------------
-- what WoW shows right of the health bar, so a row or Purge goes right of it, never over it: WoW's
-- loss-of-control icon (an enemy player: a stun, fear or sheep on them) or its crowd-control icons (an
-- NPC) when WoW shows that spot, else WoW: Forever's level badge, else the bar. Anchored to it, so it
-- follows as WoW's row grows (on Anniversary the badge sits left of the bar, Plunderstorm only).
function OnPlate.RightOf(uf, bar)
	local af = uf.AurasFrame
	local lc = af and af.LossOfControlFrame
	if lc and lc:IsShown() then return lc end
	local cc = af and af.CrowdControlListFrame
	if cc and cc:IsShown() then return cc end
	local lv = uf.PlayerLevelDiffFrame
	if FOREVER and lv and lv:IsShown() then return lv end
	return bar
end

-- what WoW shows left of the health bar: the raid mark, the elite or rare mark left of it and, when WoW
-- shows that spot, the enemy's buffs left of those (WoW lines them up in that order on both game versions)
function OnPlate.LeftOf(uf, bar)
	local af = uf.AurasFrame
	local bl = af and af.BuffListFrame
	if bl and bl:IsShown() then return bl end
	return uf.ClassificationFrame or uf.RaidTargetFrame or bar
end

-- a row: just above the name, below the cast bar, left of WoW's marks and buff icons or right of
-- WoW's icons there and the level badge, nudged by the page's Up / Down and Left / Right. False while
-- the plate has no parts yet (WoW gives them right after: it is placed again on the next frame).
-- redraw: the game redraws WoW's row of your debuffs for this row (Hide WoW's Own Icons, WoW: Forever).
function OnPlate.Debuffs(d, plate, sv, redraw)
	local uf = plate.UnitFrame
	local bar = uf and uf.HealthBarsContainer
	local spot, x, y = sv.plateSpot, sv.plateX or 0, sv.plateY or 0
	if OnPlate.addonPlates then
		-- another addon draws the nameplates (WoW's own is hidden): around the plate's middle
		if spot == "below" then return pcall(d.SetPoint, d, "TOP", plate, "CENTER", x, -16 + y) end
		if spot == "left" then return pcall(d.SetPoint, d, "RIGHT", plate, "CENTER", -66 + x, y) end
		if spot == "right" then return pcall(d.SetPoint, d, "LEFT", plate, "CENTER", 66 + x, y) end
		return pcall(d.SetPoint, d, "BOTTOM", plate, "CENTER", x, 16 + y)
	end
	if not bar then return false end
	-- below the cast bar: never over the cast you want to interrupt
	if spot == "below" then return pcall(d.SetPoint, d, "TOP", uf.CastBarsContainer or bar, "BOTTOM", x, -2 + y) end
	if spot == "left" then return pcall(d.SetPoint, d, "RIGHT", OnPlate.LeftOf(uf, bar), "LEFT", -4 + x, y) end
	if spot == "right" then return pcall(d.SetPoint, d, "LEFT", OnPlate.RightOf(uf, bar), "RIGHT", 6 + x, y) end
	-- above the name, where WoW's row of your debuffs sits: on top of WoW's row while it shows icons of
	-- yours (WoW's own icons left on; or hidden one by one while others of yours still show there: lined
	-- up with it, from the bar's left edge, never over it), else at the name. Where the game redraws
	-- WoW's row (WoW: Forever), this row stays at the name and the redraw goes on top of it.
	local af = uf.AurasFrame
	local dl = af and af.DebuffListFrame
	d.spAbove = false
	if dl and dl:IsShown() and (not sv.hideGame or (not redraw and OnPlate.AnyShown(dl:GetChildren()))) then
		d.spAbove = true
		return pcall(d.SetPoint, d, "BOTTOMLEFT", dl, "TOPLEFT", x, 2 + y)
	end
	local name = uf.name
	return pcall(d.SetPoint, d, "BOTTOM", (name and name:IsShown()) and name or bar, "TOP", x, 3 + y)
end

-- Purge on a nameplate: right of its health bar and of WoW's icons and level badge there, or right of
-- your debuffs' row when that row sits there too (never on top of either)
function OnPlate.Purge(p, plate, row)
	if row then return pcall(p.SetPoint, p, "LEFT", row, "RIGHT", 6, 0) end
	if OnPlate.addonPlates then return pcall(p.SetPoint, p, "LEFT", plate, "CENTER", 66, 0) end
	local uf = plate.UnitFrame
	local bar = uf and uf.HealthBarsContainer
	if not bar then return false end
	return pcall(p.SetPoint, p, "LEFT", OnPlate.RightOf(uf, bar), "RIGHT", 6, 0)
end

-- Next Shock on a nameplate: left of its health bar and of WoW's marks and buff icons there (Purge sits on
-- the right), or left of your debuffs' row when that row sits there too (never on top of either)
function OnPlate.NextShock(f, plate, row)
	if row then return pcall(f.SetPoint, f, "RIGHT", row, "LEFT", -6, 0) end
	if OnPlate.addonPlates then return pcall(f.SetPoint, f, "RIGHT", plate, "CENTER", -66, 0) end
	local uf = plate.UnitFrame
	local bar = uf and uf.HealthBarsContainer
	if not bar then return false end
	return pcall(f.SetPoint, f, "RIGHT", OnPlate.LeftOf(uf, bar), "LEFT", -6, 0)
end

-- under WoW's target frame. Anniversary: under the target's cast bar, which WoW itself moves down
-- under the target's rows of buffs and debuffs (so they never cover each other, and nothing polls).
-- WoW: Forever draws that part of its target frame with the game's own protected aura display, which
-- no addon may hang anything off: a fixed spot under the frame.
function OnPlate.UnderTargetFrame(f)
	local cast = not FOREVER and _G.TargetFrameSpellBar
	if cast then
		f:SetPoint("TOPLEFT", cast, "BOTTOMLEFT", K.FRAME_X - 43, -10)
	else
		f:SetPoint("TOPLEFT", TargetFrame, "BOTTOMLEFT", K.FRAME_X, K.FRAME_Y)
	end
end

-- a Missing Warning only on an enemy the game says you can attack (an answer it hides: no warning),
-- and never on an enemy's totem, pet or guardian, a critter or a gas cloud, or a minor enemy (WoW's own
-- "minus" mobs, which its nameplates draw small): noise in a pack. (In dungeons and raids on WoW: Forever
-- the game hides the kind of creature; whether you can attack it, a minion and a minor enemy it never hides.)
function OnPlate.WarnOK(unit)
	local can = UnitCanAttack("player", unit)
	if secret(can) or not can then return false end
	local m = UnitIsMinion and UnitIsMinion(unit)
	if not secret(m) and m then return false end
	local cl = UnitClassification and UnitClassification(unit)
	if not secret(cl) and cl == "minus" then return false end
	local _, id = UnitCreatureType(unit)
	if not secret(id) and id ~= nil and K.NOWARN[id] then return false end
	return true
end

local function PlaceDebuffs()
	local d, sv = H.debuffs, SV()
	d:ClearAllPoints()
	d.spPlate = nil
	if sv.showOn == "plate" and not demo.debuffs then
		d:SetScale(K.PLATE_SCALE)
		d:SetClampedToScreen(false)
		local plate = TargetPlate()
		if plate and OnPlate.Debuffs(d, plate, sv, OnPlate.tgtRedraw) then
			placed.debuffs, d.spPlate = true, plate
		else
			placed.debuffs = false
			Park(d)
			if plate then OnPlate.Wait("target") end   -- (the plate is there, its parts come right after)
		end
		return
	end
	placed.debuffs = true
	d:SetScale(1)
	d:SetClampedToScreen(true)
	if sv.showOn == "frame" and TargetFrame and not demo.debuffs then
		OnPlate.UnderTargetFrame(d)
		return
	end
	if not SP:ApplyPositionRecord(d, sv.debuffsPos or K.SPOT.debuffs) then
		d:SetPoint("CENTER", UIParent, "CENTER", 200, -60)
	end
end

-- Purge's spot; while it should sit on your target's nameplate and there is none,
-- your target's Purge waits off screen and a boss's shows on Purge's screen spot
local function PlacePurge()
	local p, b, sv = H.purge, H.bossSpot, SV()
	local size = Get("purge", "size")
	p:SetSize(size, size)
	b:SetSize(size, size)
	p:ClearAllPoints()
	p.spPlate = nil
	local where = Get("purge", "showOn")
	if where == "plate" and not demo.purge then
		p:SetScale(K.PURGE_PLATE_SCALE)
		p:SetClampedToScreen(false)
		local plate = TargetPlate()
		b:ClearAllPoints()
		-- your debuffs on the same side of the same plate: Purge goes right of them
		local row = nil
		if sv.showOn == "plate" and sv.plateSpot == "right" and placed.debuffs and plate and H.debuffs.spPlate == plate then row = H.debuffs end
		if plate and OnPlate.Purge(p, plate, row) then
			placed.purge, p.spPlate = true, plate
			b:SetScale(K.PURGE_PLATE_SCALE)
			b:SetAllPoints(p)
		else
			placed.purge = false
			Park(p)
			b:SetScale(1)
			if not SP:ApplyPositionRecord(b, sv.purgePos or K.SPOT.purge) then b:SetPoint("CENTER", UIParent, "CENTER", 200, 40) end
			if plate then OnPlate.Wait("target") end
		end
		return
	end
	placed.purge = true
	p:SetScale(1)
	p:SetClampedToScreen(true)
	b:SetScale(1)
	b:ClearAllPoints()
	b:SetAllPoints(p)
	if where == "frame" and TargetFrame and not demo.purge then
		-- under your debuffs when they are under the target frame too
		if sv.showOn == "frame" and blockH > 0 and not demo.debuffs then
			p:SetPoint("TOPLEFT", H.debuffs, "BOTTOMLEFT", 0, -10)
		else
			OnPlate.UnderTargetFrame(p)
		end
		return
	end
	if not SP:ApplyPositionRecord(p, sv.purgePos or K.SPOT.purge) then
		p:SetPoint("CENTER", UIParent, "CENTER", 200, 40)
	end
end

local function DebuffLook(key, size)
	return { size = size or Get(key, "size"), timeLeft = Get(key, "timeLeft") and true or false,
		sweep = Get(key, "sweep"), sweepDirection = Get(key, "sweepDirection"),
		charges = key == "ss" and Get(key, "charges") and true or false,
		missLook = Get(key, "missLook"), border = Get(key, "border") }
end

-- word: PURGE under the icon (on the screen spot only; never on a nameplate)
local function PurgeLook(size, onPlate)
	return { size = size or Get("purge", "size"), glow = Get("purge", "glow") and true or false,
		picture = Get("purge", "buffPicture") and true or false,
		word = not onPlate and Get("purge", "showOn") == "screen", border = Get("purge", "border") }
end

-- what Purge lights for: a Magic buff, the long ones left out when asked (the game's own filter)
local function PurgeCandidate()
	local c = { includeDispelTypes = { Magic = true } }
	if Get("purge", "skipLong") then c.maxDuration = Get("purge", "longerThan") * 60 end
	return c
end

-- ---------------------------------------------------------------------------
-- WoW: Forever: the game draws. E.tc is the ONE container on your target, with a
-- slot each for Flame Shock, Frost Shock, Stormstrike (yours: HARMFUL|PLAYER and
-- the spell's IDs) and Purge (a Magic buff, the long ones left out when asked);
-- each slot's button hangs on its spot by its anchors. Under each debuff's slot
-- sits its Missing Warning: the real debuff, drawn on top by the game whenever it
-- is on your target, covers it (nothing is read). E.gate is the ONE state driver
-- (on both game versions): the game shows it, and everything in it, only while
-- you have an attackable, living target. A part is turned on or off by its slot
-- (the game's own call, made for us by the game: SetAuraSlotEnabled), in a fight
-- too. The bosses' containers (Purge only) show between the pull and the end of
-- the fight.
-- ---------------------------------------------------------------------------
local E = { parts = {}, slotOn = {}, slotOk = {}, miss = {}, boss = {}, log = {}, plateAll = {}, enabled = nil, driver = false }
local engine = nil      -- true: the game's containers draw; false: the icons are filled in here

local function Log(fmt, ...)
	E.log[#E.log + 1] = fmt:format(...)
	if #E.log > 30 then table.remove(E.log, 1) end
end

local function EngineAvailable()
	if engine ~= nil then return engine end
	engine = false
	if not FOREVER or not (C_AddOns and C_AddOns.LoadAddOn) then return false end
	pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
	if ok and c and type(c.AddAuraSlot) == "function" and type(c.SetUnit) == "function" then
		engine = true
		E.spare = c   -- (the one this probe made: the target's container is this one)
	end
	if c and c.Hide then c:Hide() end
	return engine
end

local function NewContainer(parent)
	local c = E.spare
	if c then
		E.spare = nil
		c:SetParent(parent)
	else
		local ok
		ok, c = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
		if not (ok and c and type(c.AddAuraSlot) == "function") then
			Log("no container (%s)", tostring(c))
			return nil
		end
	end
	c:ClearAllPoints()
	c:SetSize(1, 1)
	c:SetPoint("CENTER", parent, "CENTER")
	-- WoW's Edit Mode fills aura displays with made-up auras while it is open: never these
	if c.SetEditModePreviewEnabled then pcall(c.SetEditModePreviewEnabled, c, false) end
	c:Show()
	return c
end

-- one slot: the button the game makes for it gets the parts (init); false when refused
local function AddSlot(c, slot, filter, candidate, init, quiet)
	local ok, err = pcall(c.AddAuraSlot, c, slot, filter, { candidateFilters = candidate, initializeFrame = init })
	if not ok and not quiet then Log("%s: slot refused (%s)", slot, tostring(err)) end
	return ok, err
end

-- the debuff slot's button: our parts, the game's icon, sweep, time left and charges
local function DebuffInit(key, box, partsOut, look)
	return function(button)
		button:ClearAllPoints()
		button:SetAllPoints(box)
		NoMouse(button)
		local p = DebuffParts(button, key, look or DebuffLook(key))
		pcall(button.SetIcon, button, p.icon)
		if not pcall(button.SetDurationCooldown, button, p.cd) then p.sweep:Hide() end
		-- the vertical sweeps' bar: the game moves it (Grays Out / Fills Back In); StyleDebuff hands it
		-- over, with the timer's way for this look (SweepBarArt)
		p.engine, p.button, p.vtop = true, button, nil
		if not button.SetDurationBar then p.vfail = true end
		StyleDebuff(p, p.look)
		pcall(button.SetDurationText, button, p.time, { textFormatter = TimeFormatter() })
		pcall(button.SetApplicationCount, button, p.count, { formatter = CountFormatter() })
		partsOut[key] = p
	end
end

local function PurgeInit(box, partsOut, slot, blend, look)
	return function(button)
		button:ClearAllPoints()
		button:SetAllPoints(box)
		NoMouse(button)
		local p = PurgeParts(button, look or PurgeLook(), blend)
		pcall(button.SetIcon, button, p.pic)   -- the game paints the buff's picture
		partsOut[slot] = p
	end
end

-- the one gate (both game versions): shown by the game only while you have an attackable, living
-- target; what shows on your target hangs under it, so a dead or friendly target hides it all
-- without any code of ours running
function E.Gate()
	if E.gate then return E.gate end
	local g = CreateFrame("Frame", nil, UIParent)
	g:SetSize(1, 1)
	g:SetPoint("CENTER")
	g:Hide()
	E.gate = g
	return g
end

-- the one container on your target, under the gate, each debuff's Missing Warning under its slot
-- (out of combat, once)
local function BuildTarget()
	if E.tc ~= nil then return end
	E.tc = false
	local g = E.Gate()
	E.missLayer = CreateFrame("Frame", nil, g)
	E.missLayer:SetFrameLevel(g:GetFrameLevel() + 1)
	E.missLayer:SetAllPoints(H.debuffs)
	for _, key in ipairs(DEBUFFS) do
		local mh = CreateFrame("Frame", nil, E.missLayer)
		mh:SetAllPoints(cells[key].frame)
		mh:Hide()
		local p = DebuffParts(mh, key, DebuffLook(key))
		p.host = mh
		MissingLook(p, true)
		E.miss[key] = p
	end
	local c = NewContainer(g)
	if not c then return end
	c:SetFrameLevel(g:GetFrameLevel() + 5)   -- (above the Missing Warnings: the real debuff covers its warning)
	local ok = true
	for _, key in ipairs(DEBUFFS) do
		E.slotOk[key] = AddSlot(c, key, "HARMFUL|PLAYER", { includeSpellIDs = AURA_IDS[key] }, DebuffInit(key, cells[key].frame, E.parts))
		ok = E.slotOk[key] and ok
		E.slotOn[key] = true
	end
	E.slotOk.purge = AddSlot(c, "purge", "HELPFUL", PurgeCandidate(), PurgeInit(H.purge, E.parts, "purge"))
	ok = E.slotOk.purge and ok
	E.slotOn.purge = true
	-- a container that could not be bound to your target never shows a Missing Warning
	E.bound = pcall(c.SetUnit, c, "target")
	pcall(c.SetEnabled, c, true)
	E.enabled = true
	Log("target: %s", ok and "built" or "built, a slot refused")
	E.tc = c
end

-- a boss fight here can light Purge (Watch Bosses on, and Purge on in this kind of place, or a rule
-- here that turns it on): only then are the bosses' containers made
function E.BossesPossible()
	if not (Get("purge", "watchBosses") and Usable("purge")) then return false end
	if Get("purge", "shown") and ZoneOK("purge") then return true end
	for _, rule in ipairs(SV().rules) do
		if rule.part == "purge:on" and PlaceMatches(rule.place) then return true end
	end
	return false
end

-- the bosses' containers (Purge only; a boss's glow blends, so with the boss as your
-- target too it never doubles up). Out of combat, once, when Watch Bosses can light here.
local function BuildBosses()
	if E.bossLayer then return end
	E.bossLayer = CreateFrame("Frame", nil, UIParent)
	E.bossLayer:SetSize(1, 1)
	E.bossLayer:SetPoint("CENTER")
	E.bossLayer:Hide()
	for i = 1, 5 do
		local c = NewContainer(E.bossLayer)
		if c then
			local parts = {}
			if AddSlot(c, "purge", "HELPFUL", PurgeCandidate(), PurgeInit(H.bossSpot, parts, "purge", "BLEND")) then
				pcall(c.SetUnit, c, "boss" .. i)
				pcall(c.SetEnabled, c, false)
				c:Hide()   -- shown (and listening) while boss<i> is there in a boss fight
				E.boss[i] = { c = c, p = parts, on = false }
			end
		end
	end
	Log("bosses: %d built", #E.boss)
end

-- a part on or off: the game's own call (made for us by the game, in a fight too)
local function SlotEnable(key, on)
	if not E.tc or E.slotOn[key] == on then return end
	E.slotOn[key] = on
	local ok, err = pcall(E.tc.SetAuraSlotEnabled, E.tc, key, on)
	if not ok and not E.slotErr then
		E.slotErr = true
		Log("%s: SetAuraSlotEnabled refused (%s)", key, tostring(err))
	end
end

-- the one state driver: registered only while the module is on and something needs your target
local afterFight = CreateFrame("Frame")
local function SyncDriver()
	if not E.gate then return end
	local want = ModuleOn() and TargetNeeded()
	if want == E.driver then return end
	if InCombatLockdown() then
		pending.driver = true
		afterFight:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	pending.driver = nil
	if want then
		RegisterStateDriver(E.gate, "visibility", K.TARGET)
	else
		UnregisterStateDriver(E.gate, "visibility")
		E.gate:Hide()
	end
	E.driver = want
end

-- Purge's slot filter (Skip Long Buffs, Longer Than): changed on the slots there, after the last change.
-- In a fight too (the game's own call, made for us by the game); one it refuses there: again when it ends.
local filterGen = 0
local function ApplyFilters()
	pending.filters = nil
	local cand = PurgeCandidate()
	local refused = false
	local function set(c)
		local ok = pcall(c.SetAuraSlotCandidateFilters, c, "purge", cand)
		if not ok then
			refused = true
			if not E.filterErr then
				E.filterErr = true
				Log("purge: SetAuraSlotCandidateFilters refused")
			end
		end
	end
	if E.tc then set(E.tc) end
	for _, b in pairs(E.boss) do set(b.c) end
	for _, e in ipairs(E.plateAll) do
		if e.c and e.slotOk.purge then set(e.c) end
	end
	if refused and InCombatLockdown() then
		pending.filters = true
		afterFight:RegisterEvent("PLAYER_REGEN_ENABLED")
	end
end
local function QueueFilters()
	filterGen = filterGen + 1
	local gen = filterGen
	C_Timer.After(0.3, function()
		if gen == filterGen then ApplyFilters() end   -- 0.3 s after the LAST change (a slider drag: once)
	end)
end


-- ---------------------------------------------------------------------------
-- Anniversary: your target's auras (and a plate's, a boss's), kept from UNIT_AURA's
-- own list of what changed. A full read only on a new target or when the game asks.
-- ---------------------------------------------------------------------------
local function NewTracker(unit)
	local t = { unit = unit, mine = {}, magic = {}, magicN = 0 }
	for _, key in ipairs(DEBUFFS) do t.mine[key] = {} end   -- reused: { id, start, duration, count }
	return t
end
local tgt = NewTracker("target")
local bossT = {}
for i = 1, 5 do bossT[i] = NewTracker("boss" .. i) end

local purgeMax   -- seconds: a buff that lasts longer is left out (Skip Long Buffs), nil = none
local function ReadPurgeLimit()
	local was = purgeMax
	if Get("purge", "skipLong") then purgeMax = Get("purge", "longerThan") * 60 else purgeMax = nil end
	return was ~= purgeMax
end

-- the game hides auras right now (a fight on WoW: Forever): nothing here can be read
local function AurasHidden()
	if not FOREVER then return false end
	local S = C_Secrets
	if S and S.ShouldAurasBeSecret then
		local ok, v = pcall(S.ShouldAurasBeSecret)
		return not ok or secret(v) or v == true
	end
	return InCombatLockdown()
end

local function Store(rec, a)
	local d, e, id = a.duration, a.expirationTime, a.auraInstanceID
	if secret(d) or secret(e) or secret(id) then rec.id = nil return end
	rec.id = id
	rec.duration = d or 0
	rec.start = (e or 0) - (d or 0)
	local sid = a.spellId   -- (Next Shock learns Flame Shock's duration per spell ID from it)
	if secret(sid) then sid = nil end
	rec.spell = sid
	local n = a.applications
	if secret(n) or type(n) ~= "number" then n = 0 end
	rec.count = n
end

-- one of YOUR debuffs (cast by you, not by another player: isFromPlayerOrPlayerPet means any player)
local function Mine(a)
	local id, src = a.spellId, a.sourceUnit
	if secret(id) or secret(src) or src ~= "player" then return nil end
	return AURA_KEY[id]
end

local function Purgeable(a)
	local dt, help = a.dispelName, a.isHelpful
	if secret(dt) or secret(help) or dt ~= "Magic" or help == false then return false end
	if purgeMax then
		local d = a.duration
		if secret(d) or type(d) ~= "number" or d <= 0 or d > purgeMax then return false end
	end
	return true
end

local function MineKeyOf(t, iid)
	for _, key in ipairs(DEBUFFS) do
		if t.mine[key].id == iid then return key end
	end
	return nil
end

-- a full read; true when the game let it read (auras not hidden, the unit there)
local function TrackFull(t, mine, magic)
	local A = C_UnitAuras
	-- (nothing can be read now: what was known stays, rather than an empty record)
	if not (A and A.GetAuraDataByIndex) or AurasHidden() then return false end
	for _, key in ipairs(DEBUFFS) do t.mine[key].id = nil end
	wipe(t.magic)
	t.magicN = 0
	local ex = UnitExists(t.unit)
	if secret(ex) or not ex then return false end
	if mine then
		for i = 1, 40 do
			local a = A.GetAuraDataByIndex(t.unit, i, "HARMFUL|PLAYER")
			if not a then break end
			local key = Mine(a)
			if key then Store(t.mine[key], a) end
		end
	end
	if magic then
		for i = 1, 40 do
			local a = A.GetAuraDataByIndex(t.unit, i, "HELPFUL")
			if not a then break end
			local iid = a.auraInstanceID
			if not secret(iid) and Purgeable(a) then
				t.magic[iid] = a.icon or true
				t.magicN = t.magicN + 1
			end
		end
	end
	return true
end

-- true when something on the display may have changed
local function TrackUpdate(t, info, mine, magic)
	if AurasHidden() then return false end
	-- a payload with hidden fields (WoW: Forever in combat): read everything again, as the core does
	if secret(info) or not info or not SPCompat.AuraInfoReadable(info) or info.isFullUpdate then
		TrackFull(t, mine, magic)
		return true
	end
	local dirty = false
	local added = info.addedAuras
	if added then
		for i = 1, #added do
			local a = added[i]
			local key = mine and Mine(a)
			if key then
				Store(t.mine[key], a)
				dirty = true
			elseif magic then
				local iid = a.auraInstanceID
				if not secret(iid) and Purgeable(a) then
					if not t.magic[iid] then t.magicN = t.magicN + 1 end
					t.magic[iid] = a.icon or true
					dirty = true
				end
			end
		end
	end
	local updated = info.updatedAuraInstanceIDs
	if updated then
		for i = 1, #updated do
			local iid = updated[i]
			if not secret(iid) then
				local key = MineKeyOf(t, iid)
				if key then
					local a = C_UnitAuras.GetAuraDataByAuraInstanceID(t.unit, iid)
					if a then Store(t.mine[key], a) else t.mine[key].id = nil end
					dirty = true
				elseif t.magic[iid] then
					local a = C_UnitAuras.GetAuraDataByAuraInstanceID(t.unit, iid)
					if a and Purgeable(a) then
						t.magic[iid] = a.icon or true
					else
						t.magic[iid] = nil
						t.magicN = t.magicN - 1
					end
					dirty = true
				end
			end
		end
	end
	local removed = info.removedAuraInstanceIDs
	if removed then
		for i = 1, #removed do
			local iid = removed[i]
			if not secret(iid) then
				local key = MineKeyOf(t, iid)
				if key then
					t.mine[key].id = nil
					dirty = true
				end
				if t.magic[iid] then
					t.magic[iid] = nil
					t.magicN = t.magicN - 1
					dirty = true
				end
			end
		end
	end
	return dirty
end

local function HideRec(p)
	if p.nsF then NS.Track(p, nil) end
	if p.host:IsShown() then p.host:Hide() end
	if p.shownId ~= nil then
		p.shownId = nil
		StopTime(p)   -- (the time-left binding stops with it)
	end
end

-- one icon of ours shows a tracked debuff
local function ShowRec(p, rec)
	if p.missing then
		MissingLook(p, false)
		p.shownId = nil
	end
	if p.shownId ~= rec.id or p.shownStart ~= rec.start or p.shownDur ~= rec.duration then
		p.shownId, p.shownStart, p.shownDur = rec.id, rec.start, rec.duration
		ShowTime(p, rec.start, rec.duration)
	end
	if p.look.charges and rec.count and rec.count > 0 then p.count:SetText(rec.count) else p.count:SetText("") end
	if p.nsF then NS.Track(p, rec.start, rec.duration) end   -- (Next Shock: this enemy's own Flame Shock)
	if not p.host:IsShown() then p.host:Show() end
end

local function TargetAttackable()
	local ex = UnitExists("target")
	if secret(ex) or not ex then return false end
	local can, dead = UnitCanAttack("player", "target"), UnitIsDead("target")
	if secret(can) or secret(dead) then return true end
	return can and not dead or false
end

-- the icons filled in here (no game container: Anniversary), from what the trackers know. Never a
-- false Missing Warning: only from auras the game let us read, on an enemy it says you can attack
local function RefreshIcons()
	if not built or engine then return end
	local attack = TargetAttackable()
	local readable = not AurasHidden()   -- (always on Anniversary; WoW: Forever without its containers: not in a fight)
	-- the debuff icons hang under the gate, which the game itself hides while your target is dead: with its
	-- state driver on they only need "you can attack it", so a target brought back to life (no aura change)
	-- shows them at once. Purge (not under the gate) keeps the full test.
	local cellAttack = attack
	if not attack and E.driver then
		local ex = UnitExists("target")
		if not secret(ex) and ex then
			local can = UnitCanAttack("player", "target")
			cellAttack = secret(can) or can == true
		end
	end
	for _, key in ipairs(DEBUFFS) do
		local c = cells[key]
		if c and c.p then
			local rec = tgt.mine[key]
			if rec.id and cellAttack and readable then
				ShowRec(c.p, rec)
			elseif cellAttack and readable and tgt.warn and MissingOn(key) and ModeOK(key) then
				-- yours is not on your target: the Missing look in its spot (it follows the spell's When)
				if not c.p.missing then
					HideRec(c.p)
					MissingLook(c.p, true)
				end
				if not c.p.host:IsShown() then c.p.host:Show() end
			else
				HideRec(c.p)
			end
		end
	end
	local pp = E.purgeIcon
	if pp then
		local pic, spot
		if tgt.magicN > 0 and attack and readable and placed.purge then pic, spot = select(2, next(tgt.magic)), H.purge end
		if not pic and readable and Get("purge", "watchBosses") and encounter.id ~= nil then
			for i = 1, 5 do
				local b = bossT[i]
				if b.magicN > 0 then
					pic = select(2, next(b.magic))
					if placed.purge then spot = H.purge else spot = H.bossSpot end
					break
				end
			end
		end
		if pic and not PurgeWanted() then pic = nil end
		if pic then
			if pic ~= true then pp.pic:SetTexture(pic) end
			if pp.at ~= spot then
				-- in Purge's spot, or (a boss's, while your target has no nameplate for it) on its screen spot
				if spot == H.purge then pp.host:SetParent(H.purgeCell) else pp.host:SetParent(H.bossSpot) end
				pp.host:ClearAllPoints()
				pp.host:SetAllPoints(spot)
				pp.at = spot
			end
			pp.host:Show()
		else
			pp.host:Hide()
		end
	end
end

-- ---------------------------------------------------------------------------
-- Every Nameplate: on every enemy nameplate a small row like your target's (the
-- spells with Every Nameplate on, each at its own size, at the page's Nameplate
-- Spot, Up / Down, Left / Right, Arrange As and Spacing): your debuff with its time
-- where it is on, its Missing Warning where it is not (when that spell's Missing
-- Warning is on), and Purge right of the bar while that enemy has a Magic buff you
-- can remove. One entry per plate, taken from a pool as plates appear and given
-- back as they go. WoW: Forever: ONE container per entry, made ahead out of combat
-- (a slot each for the three debuffs and Purge, each Missing Warning under its
-- slot: the game draws, nothing is read; a hidden container does nothing).
-- Anniversary: icons filled in from that plate's own UNIT_AURA, made as needed.
-- ---------------------------------------------------------------------------
local plateUsed, platePool = {}, {}   -- [unit] = entry; entries free to use

-- Purge's look on a nameplate (no PURGE word; WoW: Forever's button sits in the row's container,
-- so it is sized for that container's scale)
function OnPlate.PurgeLook()
	local size = Get("purge", "size")
	if engine then size = size * K.PURGE_PLATE_SCALE / K.PLATE_SCALE end
	return PurgeLook(size, true)
end

function OnPlate.NewEntry()
	local e = { cells = {}, parts = {}, miss = {}, slotOn = {}, slotOk = {}, keyOn = {}, keys = {} }
	e.cellOf = function(key) return e.cells[key] end   -- (the row's frame for a spell, for LayoutRow: made once)
	e.row = CreateFrame("Frame", nil, H.plates)
	e.row:SetScale(K.PLATE_SCALE)
	e.row:SetSize(1, 1)
	e.row:Hide()
	e.purgeBox = CreateFrame("Frame", nil, H.plates)
	e.purgeBox:SetScale(K.PURGE_PLATE_SCALE)
	e.purgeBox:SetSize(64, 64)
	e.purgeBox:Hide()
	local lv = e.row:GetFrameLevel()
	for _, key in ipairs(DEBUFFS) do
		if Usable(key) then
			local cell = CreateFrame("Frame", nil, e.row)
			cell:SetSize(36, 36)
			e.cells[key] = cell
		end
	end
	if engine then
		for key, cell in pairs(e.cells) do
			-- its Missing Warning, under the slot's button: the real debuff covers it
			local mh = CreateFrame("Frame", nil, e.row)
			mh:SetFrameLevel(lv + 1)
			mh:SetAllPoints(cell)
			mh:Hide()
			local p = DebuffParts(mh, key, DebuffLook(key))
			p.host = mh
			MissingLook(p, true)
			e.miss[key] = p
		end
		local c = NewContainer(e.row)   -- (in the row: the plate's scale applies to its buttons too)
		if not c then return nil end
		c:SetFrameLevel(lv + 5)
		for key, cell in pairs(e.cells) do
			e.slotOk[key] = AddSlot(c, key, "HARMFUL|PLAYER", { includeSpellIDs = AURA_IDS[key] }, DebuffInit(key, cell, e.parts))
			e.slotOn[key] = e.slotOk[key]
		end
		if Usable("purge") then
			e.slotOk.purge = AddSlot(c, "purge", "HELPFUL", PurgeCandidate(), PurgeInit(e.purgeBox, e.parts, "purge", nil, OnPlate.PurgeLook()))
			e.slotOn.purge = e.slotOk.purge
		end
		-- (WoW's row of your debuffs on its plate, redrawn: Hide WoW's Own Icons, once the groups are made)
		if OnPlate.groupsBuilt then OnPlate.AddGroup(e, c, K.PLATE_SCALE) end
		pcall(c.SetUnit, c, "none")
		pcall(c.SetEnabled, c, true)
		e.c = c
		if NS.built then NS.PlateBuild(e) end   -- (Next Shock on this nameplate's Flame Shock icon)
	else
		for key, cell in pairs(e.cells) do
			local host = Carrier(cell)
			host:Hide()
			local p = DebuffParts(host, key, DebuffLook(key))
			p.host = host
			if key == "fs" then NS.Attach(p) end
			e.parts[key] = p
		end
		if Usable("purge") then
			local host = CreateFrame("Frame", nil, e.purgeBox)
			host:SetAllPoints(e.purgeBox)
			host:Hide()
			e.parts.purge = PurgeParts(host, OnPlate.PurgeLook())
			e.slotOk.purge = true
		end
		e.t = NewTracker("none")
		e.watch = CreateFrame("Frame")
		e.watch.entry = e
		e.watch:SetScript("OnEvent", OnPlate.OnAura)
	end
	E.plateAll[#E.plateAll + 1] = e
	return e
end

-- WoW: Forever: the entries made ahead, out of combat (a fight never has to make one)
function OnPlate.FillPool()
	if not engine or InCombatLockdown() then return end
	for _ = #E.plateAll + 1, K.POOL do
		local e = OnPlate.NewEntry()
		if not e then break end
		platePool[#platePool + 1] = e
	end
end

-- an entry's row: its spells (the ones on every plate here), each at its own size, in a row or a
-- column with the page's spacing, at the page's Nameplate Spot; Purge right of the bar (or of the
-- row when the row sits right of the bar). False while the plate has no parts yet.
function OnPlate.Layout(e)
	local keys = e.keys
	wipe(keys)
	for _, key in ipairs(DEBUFFS) do
		if e.cells[key] and OnPlate.lay[key] then keys[#keys + 1] = key end
	end
	local w, h = LayoutRow(e.row, keys, e.cellOf)
	e.row:SetSize(w, h)
	local size = Get("purge", "size")
	e.purgeBox:SetSize(size, size)
	local plate = e.plate
	if not plate then return true end
	local sv = SV()
	e.row:ClearAllPoints()
	e.purgeBox:ClearAllPoints()
	local ok = OnPlate.Debuffs(e.row, plate, sv, e.grp)
	local row = nil
	if sv.plateSpot == "right" and #keys > 0 then row = e.row end
	OnPlate.Purge(e.purgeBox, plate, row)
	return ok and true or false
end

-- what an entry shows now: each spell's slot (WoW: Forever) or icon (Anniversary), the Missing
-- Warnings and Purge. Your target's plate steps aside where your debuffs, or your target's Purge,
-- already sit on it: never twice. A slot is switched only when that changes (each switch has the
-- game read that enemy's auras again).
function OnPlate.Sync(e)
	local plate = e.plate
	if not plate then return end
	local sv = SV()
	local onTarget = plate == H.debuffs.spPlate and sv.showOn == "plate" and placed.debuffs
	local purgeOnTarget = plate == H.purge.spPlate and placed.purge and Get("purge", "showOn") == "plate"
	local want, warn = OnPlate.want, OnPlate.warnWant
	local any = false
	for key, cell in pairs(e.cells) do
		local on = want[key] and not onTarget and (e.c == nil or e.slotOk[key]) or false
		e.keyOn[key] = on
		if on then any = true end
		if e.c then
			if e.slotOk[key] and e.slotOn[key] ~= on then
				e.slotOn[key] = on
				pcall(e.c.SetAuraSlotEnabled, e.c, key, on)
			end
			-- never a false Missing Warning: only on a container bound to this enemy, one you can attack
			e.miss[key].host:SetShown(on and e.bound and e.warn and warn[key] or false)
		else
			cell:SetShown(on)
		end
	end
	local pon = want.purge and not purgeOnTarget and e.slotOk.purge or false
	e.purgeOn = pon
	if e.c and e.slotOk.purge and e.slotOn.purge ~= pon then
		e.slotOn.purge = pon
		pcall(e.c.SetAuraSlotEnabled, e.c, "purge", pon)
	end
	e.purgeBox:SetShown(pon)
	e.row:SetShown(any or pon)   -- (WoW: Forever: the container is in the row; it works only while shown)
	if e.nc then NS.PlateSync(e) end
	if not e.c then OnPlate.Fill(e) end
end

-- what an entry's icons show (Anniversary): your debuff with its time, its Missing Warning where it
-- is not on (never a false one: only from a read of this enemy's auras made since it got this entry,
-- on an enemy you can attack), Purge while it has a Magic buff you can remove
function OnPlate.Fill(e)
	if e.c then return end
	local readable = e.fresh and not AurasHidden()
	local warn = OnPlate.warnWant
	for key, p in pairs(e.parts) do
		if key ~= "purge" then
			local rec = e.t.mine[key]
			if not e.keyOn[key] then
				HideRec(p)
			elseif rec.id and readable then
				ShowRec(p, rec)
			elseif readable and e.warn and warn[key] then
				if not p.missing then
					HideRec(p)
					MissingLook(p, true)
				end
				if not p.host:IsShown() then p.host:Show() end
			else
				HideRec(p)
			end
		end
	end
	local pp = e.parts.purge
	if pp then
		local pic = nil
		if e.purgeOn and readable and e.t.magicN > 0 then pic = select(2, next(e.t.magic)) end
		if pic and pic ~= true then pp.pic:SetTexture(pic) end
		pp.host:SetShown(pic ~= nil)
	end
end

-- a plate's auras changed (Anniversary): its row and Purge follow (from the event's own list)
function OnPlate.OnAura(self, _, unit, info)
	local e = self.entry
	if secret(unit) or not (e and e.unit == unit) then return end
	if TrackUpdate(e.t, info, true, OnPlate.want.purge) then OnPlate.Fill(e) end
end

-- an enemy's plate gets an entry
function OnPlate.Attach(unit)
	if not H.plates or secret(unit) or type(unit) ~= "string" then return end
	OnPlate.waiting[unit] = nil
	OnPlate.skipped[unit] = nil
	if plateUsed[unit] then return end
	local plate = PlateOf(unit)
	if not plate then return end
	local can = UnitCanAttack("player", unit)
	if not secret(can) and not can then
		-- a friendly plate (an answer the game hides: icons, never a warning): looked at again at the next
		-- pull, or when the game says it turned hostile
		OnPlate.skipped[unit] = true
		return
	end
	local uf = plate.UnitFrame
	if not (uf and uf.HealthBarsContainer) and not OnPlate.addonPlates then
		OnPlate.Wait(unit)   -- (WoW gives the plate its parts right after: again on the next frame)
		return
	end
	local e = table.remove(platePool)
	if not e and not engine then e = OnPlate.NewEntry() end
	if not e then
		-- all in use (WoW: Forever makes its containers out of combat only): the next one that frees up
		OnPlate.waiting[unit] = true
		return
	end
	e.unit, e.plate = unit, plate
	e.warn = OnPlate.WarnOK(unit)
	OnPlate.Layout(e)
	if e.c then
		-- bound to this enemy, or nothing at all on its plate (a warning there could be false)
		local ok = pcall(e.c.SetUnit, e.c, unit)
		if ok and e.c.GetUnit then
			local okU, u = pcall(e.c.GetUnit, e.c)
			ok = okU and not secret(u) and u == unit
		end
		if not ok then
			if not E.bindErr then
				E.bindErr = true
				Log("plate: the game refused a nameplate (%s); it gets its row when the fight ends", unit)
			end
			e.unit, e.plate = nil, nil
			e.row:ClearAllPoints()
			e.purgeBox:ClearAllPoints()
			platePool[#platePool + 1] = e
			OnPlate.waiting[unit] = true
			afterFight:RegisterEvent("PLAYER_REGEN_ENABLED")
			return
		end
		pcall(e.c.UpdateAllAuras, e.c)
		if e.nc then
			pcall(e.nc.SetUnit, e.nc, unit)
			pcall(e.nc.UpdateAllAuras, e.nc)
		end
		if e.lc then
			pcall(e.lc.SetUnit, e.lc, unit)
			pcall(e.lc.UpdateAllAuras, e.lc)
		end
	else
		e.t.unit = unit
		e.watch:RegisterUnitEvent("UNIT_AURA", unit)
		e.fresh = TrackFull(e.t, true, OnPlate.want.purge)
	end
	e.bound = true
	plateUsed[unit] = e
	OnPlate.entryOf[plate] = e
	OnPlate.Sync(e)
	if e.c and e.parts.fs and NS.built then NS.Refresh() end   -- (Next Shock: this enemy's own Flame Shock)
	if OnPlate.hiding then OnPlate.RefreshGame(plate) end
end

-- a plate went: its entry goes back (all: everything is let go, nothing is attached in its place)
function OnPlate.Detach(unit, all)
	if secret(unit) or unit == nil then return end
	OnPlate.waiting[unit] = nil
	OnPlate.skipped[unit] = nil
	local e = plateUsed[unit]
	if not e then return end
	plateUsed[unit] = nil
	local plate = e.plate
	if plate and OnPlate.entryOf[plate] == e then OnPlate.entryOf[plate] = nil end
	e.row:Hide()
	e.row:ClearAllPoints()
	e.purgeBox:Hide()
	e.purgeBox:ClearAllPoints()
	e.unit, e.plate, e.bound, e.fresh, e.purgeOn = nil, nil, false, false, false
	if e.parts.fs then NS.Track(e.parts.fs, nil) end
	for key in pairs(e.keyOn) do e.keyOn[key] = false end
	for _, m in pairs(e.miss) do m.host:Hide() end
	if e.c then
		pcall(e.c.SetUnit, e.c, "none")
		if e.lc then pcall(e.lc.SetUnit, e.lc, "none") end
		if e.nc then
			pcall(e.nc.SetUnit, e.nc, "none")
			NS.PlateSync(e)
		end
	else
		e.watch:UnregisterEvent("UNIT_AURA")
		for key, p in pairs(e.parts) do
			if key == "purge" then p.host:Hide() else HideRec(p) end
		end
	end
	platePool[#platePool + 1] = e
	-- WoW's own icons come back on that plate (unless your target's row still sits on it)
	if plate then OnPlate.RefreshGame(plate) end
	-- a plate that waited for a free entry gets this one
	if not all and ModuleOn() and OnPlate.anyLay then
		local waiter = next(OnPlate.waiting)
		if waiter then OnPlate.Attach(waiter) end
	end
end

function OnPlate.DetachAll()
	wipe(OnPlate.waiting)
	wipe(OnPlate.skipped)
	local list = OnPlate.scratch
	wipe(list)
	for unit in pairs(plateUsed) do list[#list + 1] = unit end
	for i = 1, #list do OnPlate.Detach(list[i], true) end
	wipe(list)
end

-- every enemy plate on screen gets an entry (Every Nameplate just turned on, a new zone)
function OnPlate.AttachAll()
	local N = C_NamePlate
	if not N then return end
	if N.GetNamePlates then
		local ok, list = pcall(N.GetNamePlates)
		if ok and type(list) == "table" then
			for i = 1, #list do
				local plate = list[i]
				local unit = plate and plate.namePlateUnitToken
				if not secret(unit) and unit == nil and plate then unit = plate.unitToken end
				if not secret(unit) and type(unit) == "string" then OnPlate.Attach(unit) end
			end
			return
		end
	end
	for i = 1, 40 do OnPlate.Attach("nameplate" .. i) end
end

-- Every Nameplate on or off right now: the plates follow (the plates on screen once, as it turns on;
-- later ones as they come), and each entry shows what is wanted
function OnPlate.SyncAll()
	if ModuleOn() and OnPlate.anyLay then
		if not OnPlate.live then
			OnPlate.live = true
			OnPlate.AttachAll()
		end
	elseif OnPlate.live or next(plateUsed) ~= nil or next(OnPlate.waiting) ~= nil then
		OnPlate.live = false
		OnPlate.DetachAll()
	end
	for _, e in pairs(plateUsed) do OnPlate.Sync(e) end
end

-- a plate whose parts were not there yet (WoW gives them right after): placed again on the next frame,
-- once (a one-shot timer, never a loop)
function OnPlate.Wait(unit)
	if OnPlate.tried[unit] then return end
	OnPlate.soon[unit] = true
	if not OnPlate.queued then
		OnPlate.queued = true
		C_Timer.After(0, OnPlate.Retry)
	end
end
function OnPlate.Retry()
	OnPlate.queued = false
	for unit in pairs(OnPlate.soon) do
		OnPlate.soon[unit] = nil
		OnPlate.tried[unit] = true
		if ModuleOn() then
			if unit == "target" then
				PlaceDebuffs()
				PlacePurge()
				NS.Place()
				Apply()
			elseif OnPlate.anyLay then
				OnPlate.Attach(unit)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Hide WoW's Own Icons (the page's switch): on a nameplate where Target Tracker shows
-- your Flame Shock, Frost Shock or Stormstrike (your target's, when your debuffs sit
-- on its nameplate; every plate with that spell's Every Nameplate), you see each spell
-- once and your other debuffs stay. The moment Target Tracker shows nothing there,
-- WoW's own icons are back.
-- WoW: Forever. In a fight the game hides which spell each of WoW's icons is, so none
-- of WoW's icons is read. On that plate WoW's own row of your debuffs is faded (its
-- alpha only: no field of WoW's frames is written and none of WoW's code is run from
-- here; nothing in WoW's nameplate code sets that alpha back) and the game draws your
-- other debuffs in an aura group on the container that already draws that plate's
-- spells (it shares that container's unit events and aura cache; its own aura filter
-- costs one more read of the auras each time the game reads them all again), told by
-- spell ID what to leave out, a filter the game applies to your debuffs on an enemy in
-- a fight too. With Above the name the redraw sits on top of Target Tracker's own row
-- there (which stays at the name: never a jump, never a gap), else where WoW's row
-- was. Never on a plate whose container isn't bound to it, where WoW doesn't show that
-- row (its Personal Debuffs option), or when the game refused the group: there WoW's
-- row is left alone. The groups are made only once this switch, the module and WoW's
-- Personal Debuffs are all on (once, out of combat; turned off after that, not unmade).
-- Anniversary (and WoW: Forever without the groups): spell IDs can be read, so WoW's
-- icon for each of those spells is hidden (the game's own Hide and Show only) and
-- shown again once Target Tracker doesn't show it; Above the name then sits on top of
-- WoW's row while it still shows icons of yours, at the name once it shows none. A
-- hook goes only on the plates Target Tracker uses, and only while hiding; it
-- re-decides after WoW refreshes that plate's icons, and your target, a fight starting
-- or ending, a setting, WoW's options or on / off re-decide at once.
-- ---------------------------------------------------------------------------
-- Target Tracker shows this spell on this plate right now
function OnPlate.Covers(plate, key)
	if not OnPlate.hiding or plate == nil then return false end
	if plate == H.debuffs.spPlate and placed.debuffs and SV().showOn == "plate" then
		local c = cells[key]
		if c and c.slot and CellWanted(key) and (not engine or (E.bound and E.slotOk[key])) then return true end
	end
	local e = OnPlate.entryOf[plate]
	return e ~= nil and e.bound == true and e.keyOn[key] == true
end

-- WoW's icon in its crowd-control row, which shows anyone's: one of YOUR debuffs (the game's answer;
-- one it won't give counts as not yours, so WoW's icon stays)
function OnPlate.Yours(item)
	local U = C_UnitAuras
	if not (U and U.IsAuraFilteredOutByInstanceID) then return false end
	local ok, out = pcall(U.IsAuraFilteredOutByInstanceID, item.unitToken, item.auraInstanceID, "HARMFUL|PLAYER")
	return ok and not secret(out) and out == false
end

-- WoW's icons (the children of one of its lists on a plate; cc: its crowd-control row): each hidden while
-- Target Tracker shows its spell there (in the crowd-control row only your own), shown again once it
-- doesn't. Never one by one in a row the game redraws (WoW: Forever): that row is faded whole. (WoW's own
-- layout code is never called from here: while one is hidden, an icon after it in WoW's row keeps its
-- place, so a gap shows there.)
function OnPlate.GameIcons(plate, cc, ...)
	local hidden = OnPlate.hidden
	local redrawn = not cc and OnPlate.servedBy[plate] ~= nil
	for i = 1, select("#", ...) do
		local item = select(i, ...)
		local hide = false
		if not redrawn then
			local id = item.spellID
			if not secret(id) and id ~= nil then
				local key = AURA_KEY[id]
				if key then hide = OnPlate.Covers(plate, key) and (not cc or OnPlate.Yours(item)) end
			end
		end
		if hide then
			if item:IsShown() then item:Hide() end
			hidden[item] = true
		elseif hidden[item] then
			hidden[item] = nil
			if not item:IsShown() then item:Show() end
		end
	end
end

-- any of WoW's icons shown (the children of one of its lists)
function OnPlate.AnyShown(...)
	for i = 1, select("#", ...) do
		if select(i, ...):IsShown() then return true end
	end
	return false
end

-- Above the name while WoW's icons are hidden one by one (Anniversary, WoW: Forever without the groups):
-- the rows on this plate sit on top of WoW's row while it still shows icons of yours (they would cover
-- them), at the name once it shows none. After WoW refreshes the plate's icons, and on a target or plate
-- change (never polled); a row is moved only when that changes.
function OnPlate.Restack(plate)
	local sv = SV()
	if plate == nil or not sv.hideGame or sv.plateSpot ~= "above" or OnPlate.addonPlates then return end
	local dl = OnPlate.GameRow(plate)
	local want = dl ~= nil and dl:IsShown() and OnPlate.AnyShown(dl:GetChildren()) or false
	local d = H.debuffs
	if plate == d.spPlate and placed.debuffs and sv.showOn == "plate" and not OnPlate.tgtRedraw and want ~= (d.spAbove == true) then
		d:ClearAllPoints()
		OnPlate.Debuffs(d, plate, sv, nil)
	end
	local e = OnPlate.entryOf[plate]
	if e and not e.grp and want ~= (e.row.spAbove == true) then
		e.row:ClearAllPoints()
		OnPlate.Debuffs(e.row, plate, sv, nil)
	end
end

-- after WoW refreshes one of a plate's aura lists (the hook, on the plates Target Tracker uses)
function OnPlate.AfterList(af, listFrame)
	if not OnPlate.hiding then return end
	if OnPlate.faded[listFrame] then
		if not listFrame:IsVisible() then
			-- WoW no longer shows this row (its Personal Debuffs option): nothing redrawn there either
			local uf = af:GetParent()
			OnPlate.Replace(uf and uf:GetParent())
			return
		end
		-- WoW's row on a plate the game redraws: it stays faded (nothing of WoW's sets it back; kept so anyway)
		local a = listFrame:GetAlpha()
		if secret(a) or a ~= 0 then listFrame:SetAlpha(0) end
		return
	end
	if listFrame ~= af.DebuffListFrame and listFrame ~= af.CrowdControlListFrame then return end
	local uf = af:GetParent()
	local plate = uf and uf:GetParent()
	if plate == nil or (plate ~= H.debuffs.spPlate and OnPlate.entryOf[plate] == nil) then return end
	OnPlate.GameIcons(plate, listFrame == af.CrowdControlListFrame, listFrame:GetChildren())
	if listFrame == af.DebuffListFrame then OnPlate.Restack(plate) end
end

-- WoW: Forever. The spells Target Tracker shows on a plate right now, as a mask (K.BIT), and the container
-- that draws them there: your target's (your debuffs on its nameplate, an enemy you can attack) or the
-- plate's Every Nameplate entry. 0 while hiding is off, or while nothing of Target Tracker's is there.
function OnPlate.Shown(plate)
	if not OnPlate.hiding or plate == nil then return 0, nil end
	if plate == H.debuffs.spPlate and placed.debuffs and E.bound and SV().showOn == "plate" and TargetAttackable() then
		local m = 0
		for _, key in ipairs(DEBUFFS) do
			if E.slotOk[key] and E.slotOn[key] then m = m + K.BIT[key] end
		end
		if m > 0 then return m, E end
	end
	local e = OnPlate.entryOf[plate]
	if e and e.bound and e.c then
		local m = 0
		for _, key in ipairs(DEBUFFS) do
			if e.keyOn[key] then m = m + K.BIT[key] end
		end
		if m > 0 then return m, e end
	end
	return 0, nil
end

-- WoW's own row of your debuffs on a plate, and its aura frame: nil on a plate the game keeps from addons,
-- or one without its parts (WoW lends a plate its parts while it is up)
function OnPlate.GameRow(plate)
	local uf = plate and plate.UnitFrame
	local af = uf and uf.AurasFrame
	if not af or af:IsForbidden() then return nil end
	return af.DebuffListFrame, af
end

-- WoW's row faded (its alpha only) or back
function OnPlate.Fade(dl, on)
	if on then
		OnPlate.faded[dl] = true
		local a = dl:GetAlpha()
		if secret(a) or a ~= 0 then dl:SetAlpha(0) end
	elseif OnPlate.faded[dl] then
		OnPlate.faded[dl] = nil
		dl:SetAlpha(1)
	end
end

-- WoW's own option that shows all of your debuffs on nameplates (else only the ones the game marks for them);
-- kept in OnPlate.showAll, read again when that option changes or the redraw starts listening
function OnPlate.ShowAll()
	local C = C_CVar
	local get = C and C.GetCVarBool or GetCVarBool
	if type(get) ~= "function" then return false end
	local ok, v = pcall(get, "nameplateShowAllPersonalAuras")
	return ok and not secret(v) and v == true or false
end

-- WoW shows its row of your debuffs on enemy nameplates: its Personal Debuffs for enemy NPCs, or Debuffs
-- for enemy players (WoW's own options: read, never written). A client that can't say counts as yes (each
-- plate's row still decides for itself).
function OnPlate.WoWShowsDebuffs()
	local C = C_CVar
	local get = C and C.GetCVarBitfield
	if type(get) ~= "function" then return true end
	local en = Enum and Enum.NamePlateEnemyNpcAuraDisplay
	local ep = Enum and Enum.NamePlateEnemyPlayerAuraDisplay
	local okN, npc = pcall(get, "nameplateEnemyNpcAuraDisplay", en and en.Debuffs or 2)
	local okP, pvp = pcall(get, "nameplateEnemyPlayerAuraDisplay", ep and ep.Debuffs or 2)
	if not (okN or okP) then return true end
	return (okN and not secret(npc) and npc == true) or (okP and not secret(pvp) and pvp == true) or false
end

-- the groups are wanted: Hide WoW's Own Icons on and WoW showing that row (the module on: asked only then)
function OnPlate.GroupsWanted()
	return engine and SV().hideGame == true and OnPlate.WoWShowsDebuffs() and true or false
end

-- what the group leaves out: the spells Target Tracker shows there (one table per mask, made once); like
-- WoW's row, the debuffs the game doesn't mark for nameplates (unless WoW shows all of yours) and the crowd
-- control WoW puts in its crowd-control row instead
function OnPlate.Filters(mask, all)
	local t = OnPlate.cf
	if not t then
		t = {}
		for m = 0, 7 do
			local ex = {}
			for _, key in ipairs(DEBUFFS) do
				local b = K.BIT[key]
				if m % (b * 2) >= b then
					for id in pairs(AURA_IDS[key]) do ex[id] = true end
				end
			end
			t[m] = { excludeSpellIDs = ex, nameplateShowAll = false }
		end
		OnPlate.cf = t
	end
	local cf = t[mask]
	if all then cf.nameplateShowPersonal = nil else cf.nameplateShowPersonal = true end
	return cf
end

-- the redrawn row's icon size in its container's units: WoW's (25 times the plate's aura scale), as big
-- on screen as WoW's own on that plate (gRatio: how big the plate is drawn, against the screen's units;
-- gRel: the container's scale)
function OnPlate.GameSize(who) return K.GAME.item * OnPlate.gScale * (who.gRatio or 1) / who.gRel end
-- laid out like WoW's row: side by side with no gap, a line as long as WoW's, then the next one above
function OnPlate.GameLayout(who)
	local l = OnPlate.glay
	if not l then
		l = { elementSpacing = 0, lineSpacing = 0 }
		OnPlate.glay = l
	end
	l.elementWidth, l.elementHeight = who.gs, who.gs
	return l
end
function OnPlate.LineSize(who) return OnPlate.gStride * who.gs + who.gs / 2 end

-- the time left on a redrawn icon, like WoW's: whole seconds, and no numbers at all on a debuff that lasts
-- longer than a minute (the game colors the text by the debuff's whole duration: see-through above 60 s)
function OnPlate.TimeOpts()
	local o = OnPlate.timeOpts
	if o then return o end
	o = { textFormatter = TimeFormatter() }
	local CU, P = C_CurveUtil, Enum and Enum.DurationTextBindingProperty
	if CU and CU.CreateColorCurve and P and P.TotalDuration and CreateColor then
		local ok, curve = pcall(CU.CreateColorCurve)
		local step = Enum.LuaCurveType and Enum.LuaCurveType.Step or 1
		if ok and curve and pcall(curve.SetType, curve, step) and pcall(curve.AddPoint, curve, 0, CreateColor(1, 1, 1, 1))
			and pcall(curve.AddPoint, curve, K.GAME.long + 0.001, CreateColor(1, 1, 1, 0)) then
			o.textColor = { curve = curve, property = P.TotalDuration }
		end
	end
	OnPlate.timeOpts = o
	OnPlate.timePlain = { textFormatter = o.textFormatter }
	return o
end

-- a redrawn icon (each frame the group makes, made with the group: out of combat), WoW's look: the icon
-- in WoW's rounded mask and border, its sweep, the time left (60 s or less) and the stack count. Its text
-- and border sit in a frame scaled to WoW's icon (25 across), so they are as big as on WoW's own. Hovering
-- one shows that debuff's tooltip (the game's own aura button does); a click goes where it would without it.
function OnPlate.GameInit(who)
	return function(b)
		local s = who.gs
		b:SetSize(s, s)
		pcall(b.SetMouseMotionEnabled, b, true)
		pcall(b.SetMouseClickEnabled, b, false)
		local icon = b:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints(b)
		if b.CreateMaskTexture then
			local mask = b:CreateMaskTexture()
			mask:SetAllPoints(b)
			if mask:SetAtlas("UI-HUD-CoolDownManager-Mask") then icon:AddMaskTexture(mask) end   -- (no mask without its art)
		end
		local cd = CreateFrame("Cooldown", nil, b)
		cd:SetAllPoints(b)
		cd:SetReverse(true)   -- (the dark part grows as the time runs out, as on WoW's icon)
		cd:SetSwipeTexture("Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe")
		cd:SetSwipeColor(0, 0, 0, 0.5)
		cd:SetEdgeTexture("Interface\\Cooldown\\UI-HUD-ActionBar-SecondaryCooldown")
		cd:SetDrawEdge(true)
		if cd.SetDrawBling then cd:SetDrawBling(false) end
		cd:SetHideCountdownNumbers(true)
		cd.noCooldownCount = true   -- (OmniCC and the like: the time left is drawn here)
		local t = CreateFrame("Frame", nil, b)
		t:SetScale(s / K.GAME.item)
		t:SetAllPoints(b)
		t:SetFrameLevel(cd:GetFrameLevel() + 2)
		local over = t:CreateTexture(nil, "OVERLAY")
		over:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
		over:SetPoint("TOPLEFT", t, "TOPLEFT", -6, 5)
		over:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 6, -5)
		local time = t:CreateFontString(nil, "OVERLAY")
		time:SetFontObject(_G.NumberFontNormal or GameFontHighlight)   -- (a font at once: the game writes into it)
		time:SetPoint("CENTER", t, "CENTER", 0, 0)
		local count = t:CreateFontString(nil, "OVERLAY")
		count:SetFontObject(_G.NumberFontNormalSmall or GameFontHighlightSmall)
		count:SetJustifyH("RIGHT")
		count:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 3, -2)
		pcall(b.SetIcon, b, icon)
		pcall(b.SetDurationCooldown, b, cd)
		if not pcall(b.SetDurationText, b, time, OnPlate.TimeOpts()) then pcall(b.SetDurationText, b, time, OnPlate.timePlain) end
		pcall(b.SetApplicationCount, b, count)   -- (like WoW's: a stack of 2 or more)
		who.gb[#who.gb + 1] = b
		who.gt[#who.gt + 1] = t
	end
end

-- WoW's icon size and row length from WoW's own options (its nameplate aura scale times its nameplate
-- size's, the row length as WoW works it out), or exactly, off a plate on screen out of combat: set
-- before the first fight, so a first redraw in one is already WoW's size
function OnPlate.GameSeed()
	OnPlate.seeded = true
	local C = C_CVar
	local get = C and C.GetCVar or GetCVar
	local as, sz
	if type(get) == "function" then
		local ok1, v1 = pcall(get, "nameplateAuraScale")
		local ok2, v2 = pcall(get, "nameplateSize")
		if ok1 and not secret(v1) then as = tonumber(v1) end
		if ok2 and not secret(v2) then sz = tonumber(v2) end
	end
	as, sz = as or 1, sz or 2
	local NC = NamePlateConstants
	local row = NC and type(NC.NAME_PLATE_SCALES) == "table" and NC.NAME_PLATE_SCALES[sz]
	local fromSize = type(row) == "table" and type(row.aura) == "number" and row.aura or K.GAME.size[sz] or 1
	OnPlate.gScale = as * fromSize
	OnPlate.gStride = (as <= 0.71 and 12) or (as <= 0.81 and 10) or (as <= 0.91 and 9) or (as <= 1.01 and 8) or (as <= 1.21 and 7) or 6
	if InCombatLockdown() then return end
	local N = C_NamePlate
	if not (N and N.GetNamePlates) then return end
	local ok, list = pcall(N.GetNamePlates)
	if not ok or type(list) ~= "table" then return end
	for i = 1, #list do
		local dl, af = OnPlate.GameRow(list[i])
		if dl and af then
			local sc, st = af.auraItemScale, dl.stride
			if not secret(sc) and type(sc) == "number" and sc > 0 then OnPlate.gScale = sc end
			if not secret(st) and type(st) == "number" and st >= 1 then OnPlate.gStride = st end
			return
		end
	end
end

-- your target's flags changed while its container redraws WoW's row on its plate (it may have stopped being
-- one you can attack without changing sides): that plate decided again
function OnPlate.TargetFlags(_, _, unit)
	if secret(unit) or unit ~= "target" then return end
	OnPlate.Replace(H.debuffs.spPlate)
end

-- the group on a container (out of combat): off until it redraws a plate's row. The container hangs on a
-- spot of its own from then on (where it hung before, until that spot is moved; nothing is anchored to the
-- container itself: the game's groups resize it), laid out like WoW's row; its slots stay where they hang.
-- True when the game took it. One it half took is turned off: never drawn anywhere.
function OnPlate.AddGroup(who, c, rel)
	if not OnPlate.seeded then OnPlate.GameSeed() end
	who.gc, who.gRel, who.gRatio, who.gb, who.gt = c, rel, 1, {}, {}
	who.gs = OnPlate.GameSize(who)
	local spot = CreateFrame("Frame", nil, c:GetParent())
	spot:SetSize(1, 1)
	spot:SetPoint("CENTER")
	who.gameSpot = spot
	c:ClearAllPoints()
	c:SetPoint("BOTTOMLEFT", spot, "BOTTOMLEFT", 0, 0)
	-- from the bottom left, to the right, then a line up, as WoW's row grows
	local fd = AnchorUtil and AnchorUtil.FlowDirection
	pcall(c.SetFlowLayoutAnchorPoint, c, "BOTTOMLEFT")
	pcall(c.SetFlowLayoutGrowthDirection, c, fd and fd.Right or 1, fd and fd.Up or 1)
	pcall(c.SetFlowLayoutMaximumLineSize, c, OnPlate.LineSize(who))
	if OnPlate.showAll == nil then OnPlate.showAll = OnPlate.ShowAll() end
	local all = OnPlate.showAll
	local ok, err = pcall(c.AddAuraGroup, c, "others", K.GAME.filter, { maxFrameCount = K.GAME.max,
		candidateFilters = OnPlate.Filters(0, all), layout = OnPlate.GameLayout(who), initializeFrame = OnPlate.GameInit(who) })
	local off = ok and pcall(c.SetAuraGroupEnabled, c, "others", false)
	if not off then
		local okH, has = pcall(c.HasAuraGroup, c, "others")
		if okH and not secret(has) and has == true then pcall(c.SetAuraGroupEnabled, c, "others", false) end
		Log("WoW's row: the game refused the group (%s)", ok and "it would not turn off" or tostring(err))
		return
	end
	if who == E then
		E.flagWatch = CreateFrame("Frame")
		E.flagWatch:SetScript("OnEvent", OnPlate.TargetFlags)
	end
	who.grp, who.grpOn, who.grpMask, who.grpAll, who.gLine = true, false, 0, all, OnPlate.gStride
	return true
end

-- the groups made (out of combat, once Hide WoW's Own Icons, the module and WoW's Personal Debuffs are on;
-- after that they are turned off, never unmade): on your target's container and on every nameplate entry's
-- (an entry made later gets its own as it is made)
function OnPlate.BuildGroups()
	if OnPlate.groupsBuilt or InCombatLockdown() then return end
	OnPlate.groupsBuilt = true
	if E.tc and not E.gc then OnPlate.tgtRedraw = OnPlate.AddGroup(E, E.tc, 1) end
	for _, e in ipairs(E.plateAll) do
		if e.c and not e.gc then OnPlate.AddGroup(e, e.c, K.PLATE_SCALE) end
	end
end

-- the redrawn rows at WoW's size again (out of combat, while the game shows auras: its frames can be
-- touched only then)
function OnPlate.GameResizeOne(who)
	if not who.grp then return end
	local s = OnPlate.GameSize(who)
	if who.gs == s and who.gLine == OnPlate.gStride then return end
	who.gs, who.gLine = s, OnPlate.gStride
	local k = s / K.GAME.item
	for i = 1, #who.gb do
		pcall(who.gb[i].SetSize, who.gb[i], s, s)
		pcall(who.gt[i].SetScale, who.gt[i], k)
	end
	pcall(who.gc.SetAuraGroupLayout, who.gc, "others", OnPlate.GameLayout(who))
	pcall(who.gc.SetFlowLayoutMaximumLineSize, who.gc, OnPlate.LineSize(who))
end
function OnPlate.GameResize()
	OnPlate.GameResizeOne(E)
	for _, e in ipairs(E.plateAll) do OnPlate.GameResizeOne(e) end
end

-- WoW's icon size (the plate's aura scale), its row length and how big the plate is drawn, read off the
-- plate a container starts redrawing, out of combat (a plate drawn a little nearer or further away keeps
-- the size it has); a change resizes the redrawn rows (or once the game shows auras again)
function OnPlate.GameMetrics(who, af, dl)
	local sc, st = af.auraItemScale, dl.stride
	if secret(sc) or type(sc) ~= "number" or sc <= 0 then sc = OnPlate.gScale end
	if secret(st) or type(st) ~= "number" or st < 1 then st = OnPlate.gStride end
	local ratio = who.gRatio or 1
	local es, us = dl:GetEffectiveScale(), UIParent:GetEffectiveScale()
	if not secret(es) and not secret(us) and type(es) == "number" and type(us) == "number" and es > 0 and us > 0 then
		local r = es / us
		if math.abs(r - ratio) > ratio * 0.02 then ratio = r end
	end
	local all = sc ~= OnPlate.gScale or st ~= OnPlate.gStride
	if not all and ratio == who.gRatio then return end
	OnPlate.gScale, OnPlate.gStride, who.gRatio = sc, st, ratio
	if AurasHidden() then
		pending.look = true
		afterFight:RegisterEvent("PLAYER_REGEN_ENABLED")
	elseif all then
		OnPlate.GameResize()
	else
		OnPlate.GameResizeOne(who)
	end
end

-- a container stops redrawing WoW's row: its group off, the row it faded back (that row, not the plate's:
-- WoW may have lent the plate other parts since)
function OnPlate.Release(who)
	local plate = who.gamePlate
	if plate and OnPlate.servedBy[plate] == who then OnPlate.servedBy[plate] = nil end
	who.gamePlate = nil
	if who.gameDL then
		OnPlate.Fade(who.gameDL, false)
		who.gameDL = nil
	end
	if who.gameAt then
		who.gameAt = nil
		who.gameSpot:ClearAllPoints()
		who.gameSpot:SetPoint("CENTER")
	end
	if who.grpOn then
		who.grpOn = false
		pcall(who.gc.SetAuraGroupEnabled, who.gc, "others", false)
	end
	if who == E and E.flagsOn then
		E.flagsOn = false
		E.flagWatch:UnregisterEvent("UNIT_FLAGS")
	end
end

-- a container redraws WoW's row on a plate: its group on, leaving out the spells it shows there (mask),
-- on top of Target Tracker's own row there with Above the name (that row stays at the name: the redraw
-- follows it), else where WoW's row is; WoW's row faded. The game's own calls, in a fight too. While your
-- target's container does it, your target's flags are listened to.
function OnPlate.Serve(who, plate, dl, af, mask)
	local old = who.gamePlate
	if old ~= plate then
		if old and OnPlate.servedBy[old] == who then OnPlate.servedBy[old] = nil end
		who.gamePlate = plate
		OnPlate.servedBy[plate] = who
	end
	if who.gameDL ~= dl then
		if who.gameDL then OnPlate.Fade(who.gameDL, false) end
		who.gameDL = dl
	end
	local over = SV().plateSpot == "above" and (who == E and H.debuffs or who.row) or nil
	local at = over or dl
	if who.gameAt ~= at then
		who.gameAt = at
		who.gameSpot:ClearAllPoints()
		if over then
			who.gameSpot:SetPoint("BOTTOMLEFT", over, "TOPLEFT", 0, 2 / who.gRel)
		else
			who.gameSpot:SetPoint("BOTTOMLEFT", dl, "BOTTOMLEFT", 0, 0)
		end
	end
	if not InCombatLockdown() then OnPlate.GameMetrics(who, af, dl) end
	local all = OnPlate.showAll or false
	if who.grpMask ~= mask or who.grpAll ~= all then
		who.grpMask, who.grpAll = mask, all
		local ok, err = pcall(who.gc.SetAuraGroupCandidateFilters, who.gc, "others", OnPlate.Filters(mask, all))
		if not ok and not E.groupErr then
			E.groupErr = true
			Log("WoW's row: SetAuraGroupCandidateFilters refused (%s)", tostring(err))
		end
	end
	if not who.grpOn then
		local ok, err = pcall(who.gc.SetAuraGroupEnabled, who.gc, "others", true)
		if not ok then
			-- refused: no faded row without the game's own drawn in its place (and never a group half on)
			if not E.groupErr then
				E.groupErr = true
				Log("WoW's row: SetAuraGroupEnabled refused (%s)", tostring(err))
			end
			pcall(who.gc.SetAuraGroupEnabled, who.gc, "others", false)
			OnPlate.Release(who)
			return
		end
		who.grpOn = true
	end
	if who == E and E.flagWatch and not E.flagsOn then
		E.flagsOn = true
		E.flagWatch:RegisterUnitEvent("UNIT_FLAGS", "target")
	end
	OnPlate.Fade(dl, true)
end

-- one plate decided again (WoW: Forever): WoW's row there faded and redrawn by the container that draws
-- Target Tracker's spells on it, or given back. Only where WoW shows that row (its Personal Debuffs option,
-- WoW's own nameplate: not another addon's), by a container bound to that enemy whose group the game
-- took; anything less and WoW's row is left alone.
function OnPlate.Replace(plate)
	if not engine or plate == nil then return end
	local mask, who = OnPlate.Shown(plate)
	local dl, af = OnPlate.GameRow(plate)
	local on = mask > 0 and who.grp and not OnPlate.addonPlates and dl ~= nil and dl:IsVisible() or false
	local was = OnPlate.servedBy[plate]
	if was and was.gamePlate ~= plate then
		OnPlate.servedBy[plate], was = nil, nil   -- (it has moved on to another plate)
	end
	if was and (was ~= who or not on) then OnPlate.Release(was) end
	if on then OnPlate.Serve(who, plate, dl, af, mask) end
end

-- WoW's own icons on one plate, decided again: its row redrawn or given back (WoW: Forever), its icons
-- hidden or shown one by one and the rows above the name restacked (the hook goes on that plate's aura
-- frame the first time, only while hiding; never on a plate the game keeps from addons)
function OnPlate.RefreshGame(plate)
	OnPlate.Replace(plate)
	local uf = plate and plate.UnitFrame
	local af = uf and uf.AurasFrame
	if not af or af:IsForbidden() then return end
	if OnPlate.hiding and not OnPlate.hooked[af] and type(af.RefreshList) == "function" then
		OnPlate.hooked[af] = true
		hooksecurefunc(af, "RefreshList", OnPlate.AfterList)
	end
	if not (OnPlate.hiding or next(OnPlate.hidden)) then return end
	local dl, cl = af.DebuffListFrame, af.CrowdControlListFrame
	if dl then OnPlate.GameIcons(plate, false, dl:GetChildren()) end
	if cl then OnPlate.GameIcons(plate, true, cl:GetChildren()) end
	OnPlate.Restack(plate)
end

-- every icon this module hid is decided again (shown where Target Tracker no longer shows that spell),
-- the plates it shows on are gone over, then every row it had the game redraw is given back where
-- Target Tracker shows nothing now (all of them while hiding is off; after the others, so a container
-- moving on to another plate never turns its group off and on): a fight starting or ending, a setting,
-- on / off, WoW's own nameplate options
function OnPlate.SyncGame()
	local hidden = OnPlate.hidden
	for item in pairs(hidden) do
		local list = item:GetParent()
		local af = list and list:GetParent()
		local cc = af ~= nil and list == af.CrowdControlListFrame
		local active = af ~= nil and (list == af.DebuffListFrame or cc)
		local keep = false
		if active and OnPlate.hiding then
			local uf = af:GetParent()
			local plate = uf and uf:GetParent()
			local id = item.spellID
			local key = nil
			if not secret(id) and id ~= nil then key = AURA_KEY[id] end
			keep = key ~= nil and (cc or OnPlate.servedBy[plate] == nil) and OnPlate.Covers(plate, key)
				and (not cc or OnPlate.Yours(item))
		end
		if not keep then
			hidden[item] = nil
			if active and not item:IsShown() then item:Show() end
		end
	end
	if OnPlate.hiding then
		if placed.debuffs and SV().showOn == "plate" then OnPlate.RefreshGame(H.debuffs.spPlate) end
		for plate in pairs(OnPlate.entryOf) do OnPlate.RefreshGame(plate) end
	end
	if not engine then return end
	local list = OnPlate.gwork
	wipe(list)
	for plate in pairs(OnPlate.servedBy) do list[#list + 1] = plate end
	for i = 1, #list do OnPlate.Replace(list[i]) end
	wipe(list)
	-- (no row redrawn anywhere: none faded either)
	if next(OnPlate.servedBy) == nil then
		for dl in pairs(OnPlate.faded) do OnPlate.Fade(dl, false) end
	end
end

-- WoW's own nameplate options changed (its Personal Debuffs and the like decide whether WoW shows its row
-- of your debuffs on a plate, and how big): WoW's icon size read again, everything placed and decided again
-- on the next frame, once WoW has applied it (a one-shot deferral; the event is listened to only while
-- WoW: Forever can redraw that row): the groups made if WoW now shows that row, out of combat
function OnPlate.CVar(name)
	if secret(name) or not K.GAME_CVARS[name] or OnPlate.cvarQueued then return end
	OnPlate.cvarQueued = true
	C_Timer.After(0, OnPlate.CVarNow)
end
function OnPlate.CVarNow()
	OnPlate.cvarQueued = false
	OnPlate.showAll = OnPlate.ShowAll()
	if not ModuleOn() then return end
	local sc, st = OnPlate.gScale, OnPlate.gStride
	OnPlate.GameSeed()
	if OnPlate.groupsBuilt and (sc ~= OnPlate.gScale or st ~= OnPlate.gStride) then
		if InCombatLockdown() or AurasHidden() then
			pending.look = true
			afterFight:RegisterEvent("PLAYER_REGEN_ENABLED")
		else
			OnPlate.GameResize()
		end
	end
	Update()
end

-- one plate after your target moved to or from it: its entry steps aside or back in, WoW's own icons
-- hide or come back, at once
function OnPlate.Touch(plate)
	if plate == nil then return end
	local e = OnPlate.entryOf[plate]
	if e then OnPlate.Sync(e) end
	OnPlate.RefreshGame(plate)
end

-- another addon draws the nameplates (WoW's own plate is hidden): rows go around the plate's middle
function OnPlate.FindAddons()
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	if not loaded then return end
	for _, name in ipairs(K.PLATE_ADDONS) do
		if loaded(name) then OnPlate.addonPlates = true end
	end
	-- ElvUI only while its own nameplates are on
	if loaded("ElvUI") then
		local ok, on = pcall(function() return unpack(_G.ElvUI).private.nameplates.enable end)
		if ok and on then OnPlate.addonPlates = true end
	end
end

-- ---------------------------------------------------------------------------
-- Next Shock (D49, reworked 2026-10-04: part of Flame Shock's own icon, set in Flame Shock's right-click
-- menu): which shock to press, on EACH enemy's own Flame Shock icon (your target's, and every enemy's
-- nameplate with Show On Every Enemy's Nameplate), from THAT enemy's own Flame Shock:
--   * your Flame Shock is on it: Earth Shock (or Frost Shock) over the Flame Shock icon, with Flame
--     Shock's sweep and time left (the icon only shows while yours is on that enemy: the game's own button
--     on WoW: Forever, which it shows only then, so this holds in a fight too; an icon of ours elsewhere)
--   * its last N seconds: Flame Shock again over the sweep, in its "cast it" look (N = 0: never)
--   * not on it: Flame Shock's own Missing Warning, when that is on
-- The last N seconds come from one one-shot timer per enemy, from that enemy's own Flame Shock: the aura
-- wherever the game shows it, else (a fight on WoW: Forever) your own cast on it (by its GUID, where the
-- game names it; else your target only). Nothing polls. On WoW: Forever nothing on the game's buttons
-- changes in a fight: the last seconds are a SECOND container of Next Shock's own (Flame Shock in the
-- cast-it look on the game's button), switched on and off by the timer, so the game still decides whether
-- your Flame Shock is really there (a resist, an immunity or a dispel shows nothing). Icons of ours
-- (Anniversary) switch an overlay of ours by alpha.
-- ---------------------------------------------------------------------------
function NS.On() return Get("ns", "on") == true and Known("fs") end

function NS.ShockIcon() return Get("ns", "whenOn") == "frost" and SPELL.frs.icon or NS.EARTH end
-- the picture a debuff icon's vertical sweep copies: its own, or with Next Shock on, Flame Shock's shows the shock to press
function NS.Art(key)
	if key == "fs" and NS.On() then return NS.ShockIcon() end
	return SPELL[key].icon
end
function NS.CornerSize(size) return max(8, floor(size * 0.22 + 0.5)) end
function NS.BigSize(size) return max(10, floor(size * 0.25 + 0.5)) end
NS.parts = {}   -- every Flame Shock icon with Next Shock's parts on it

-- an icon in Target Tracker's art (in a 1 px black edge) on `host`, with an opaque back: nothing under it
-- ever shows through, whatever its look
function NS.Parts(host, icon)
	local p = { host = host, key = "fs" }
	p.back = host:CreateTexture(nil, "BACKGROUND", nil, -8)
	p.back:SetAllPoints(host)
	p.back:SetColorTexture(0, 0, 0, 1)
	p.edge = host:CreateTexture(nil, "BACKGROUND")
	p.edge:SetPoint("TOPLEFT", host, "TOPLEFT", -1, 1)
	p.edge:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 1, -1)
	p.edge:SetColorTexture(0, 0, 0, 1)
	p.icon = host:CreateTexture(nil, "ARTWORK")
	p.icon:SetAllPoints(host)
	p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	p.icon:SetTexture(icon)
	return p
end

-- the cast-it look on Flame Shock: Gold Dotted Edge (WoW's gold) or one of the Missing Warnings' looks,
-- drawn as they are; gray: grayed out as a Missing Warning is, else in full color. Like a Missing Warning
-- it reaches no further out than 1 px, the edge of the icon that covers it (state 3)
function NS.Look(p, style, gray, size)
	if style == "gold" then
		LK.ExtrasOff(p)
		LK.Solid(p, 1, 0, 0, 0)
		LK.IconAt(p, 0)
		LK.Dots(p, size, 2, size >= 30 and 4 or 3, 3, 1, GOLD[1], GOLD[2], GOLD[3], "OVERLAY")
		p.icon:SetDesaturated(gray and true or false)
		if gray then
			p.icon:SetVertexColor(0.55, 0.55, 0.55)
			p.icon:SetAlpha(0.85)
		else
			p.icon:SetVertexColor(1, 1, 1)
			p.icon:SetAlpha(1)
		end
		return
	end
	local lk = NS.lk
	lk.missLook, lk.size = style, size
	LK.Missing(p, "fs", lk)
	if not gray then
		p.icon:SetDesaturated(false)
		p.icon:SetVertexColor(1, 1, 1)
		p.icon:SetAlpha((style == "faded" and 0.45) or (style == "outline" and 0) or 1)
	end
end


-- Next Shock's parts on one Flame Shock icon `p` (made with it). nsF: the shock to press over the icon,
-- on a frame of its own just above the icon (under the sweep and the time left). On WoW: Forever the icon
-- is the game's own button, which no addon may touch in a fight: the face is set out of combat and then
-- simply stays (that button only shows while your Flame Shock is on that enemy). Its last seconds are an
-- overlay of ours, never on the game's button (NS.NewOver), switched in a fight too.
function NS.Attach(p)
	if p.nsF then return end
	local host = p.host
	local fc = Carrier(host, host:GetFrameLevel() + 1)
	p.nsF = fc:CreateTexture(nil, "ARTWORK")
	p.nsF:SetAllPoints(p.icon)
	p.nsF:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	p.nsFC = fc
	if not p.engine then
		-- an icon of ours: its overlay can be its own child, over the icon's own time left (its opaque back
		-- covers that number; its own big one is drawn above it): one countdown only
		p.nsL = NS.NewOver(host, host, p.text:GetFrameLevel() + 1)
	end
	p.nsFire = function() NS.Eval(p) end
	NS.parts[#NS.parts + 1] = p
	NS.Face(p)
end

-- the last seconds' overlay: Flame Shock in the cast-it look with its time left big, on a frame of ours
-- over `anchor` (made out of combat; only its alpha changes after)
NS.overs = {}
function NS.NewOver(parent, anchor, level, gate)
	local f = CreateFrame("Frame", nil, parent)
	f:SetAllPoints(anchor)
	f:SetFrameLevel(level)
	f:SetAlpha(0)
	local L = NS.Parts(f, SPELL.fs.icon)
	L.text = Carrier(f, f:GetFrameLevel() + 2)
	L.big = L.text:CreateFontString(nil, "OVERLAY")
	L.big:SetFontObject(GameFontHighlight)
	L.big:SetPoint("CENTER", f, "CENTER", 0, 0)
	L.big:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	Outline(L.big)
	NS.Time(L, L.big, nil, nil, NS.DecFormatter(), 0.1)   -- (its binding made now, off until it shows)
	L.gate = gate
	NS.overs[#NS.overs + 1] = L
	NS.StyleOver(L)
	return L
end

function NS.StyleOver(L)
	local size = Get("fs", "size")   -- (in the icon row's scale: the target's overlay follows it, NS.Place)
	NS.Look(L, Get("ns", "castLook"), false, size)
	SP:SetSPFont(L.big, "timers", NS.BigSize(size), "OUTLINE")
end

-- the game's button may not be touched now (WoW: Forever, in a fight or while it hides auras)
function NS.Locked(p)
	return p.engine and (InCombatLockdown() or AurasHidden()) or false
end

-- the face: the shock while Next Shock is on (and the icon is not its Missing Warning); on the game's
-- button only out of combat (done after the fight otherwise)
function NS.Face(p)
	if NS.Locked(p) then
		NS.dirty = true
		return
	end
	local on = NS.On() and not p.missing
	if on then p.nsF:SetTexture(NS.ShockIcon()) end
	p.nsFC:SetShown(on)
	if not on and p.nsLate then NS.PartLate(p, false) end
end
NS.Shown = NS.Face

function NS.PartLate(p, on)
	if p.lc then
		-- WoW: Forever: the last seconds' container on or off (the game's own call, in a fight too); the game
		-- shows its button only while that enemy really has your Flame Shock, its time left the game's own
		on = on and NS.On() and true or false
		if p.nsLate == on then return end
		p.nsLate = on
		pcall(p.lc.SetEnabled, p.lc, on)
		if on then pcall(p.lc.UpdateAllAuras, p.lc) end
		return
	end
	on = on and NS.On() and not p.missing and p.nsL ~= nil or false
	if p.nsLate == on then return end
	p.nsLate = on
	local L = p.nsL
	if not L then return end
	if on then
		NS.Time(L, L.big, p.nsStart, p.nsDur, NS.DecFormatter(), 0.1)
		L.host:SetAlpha(1)
	else
		L.host:SetAlpha(0)
		NS.Time(L, L.big, nil)
	end
end

-- after a fight: what waited for the game's buttons
NS.flush = CreateFrame("Frame")
NS.flush:SetScript("OnEvent", function(self)
	if AurasHidden() then return end
	self:UnregisterAllEvents()
	if NS.dirty then NS.Restyle() end
end)

-- that enemy's Flame Shock (start, duration; nil: not on or not known): its timer set again only when that changes
function NS.Track(p, start, duration)
	if not p.nsF then return end
	local n = NS.On() and (Get("ns", "refresh") or 0) or 0
	if not (start and duration and duration > 0) or n <= 0 then
		if p.nsT then p.nsT:Cancel(); p.nsT = nil end
		p.nsStart = nil
		NS.PartLate(p, false)
		return
	end
	if p.nsStart and math.abs(p.nsStart - start) < 0.2 and math.abs(p.nsDur - duration) < 0.2 and p.nsN == n then return end
	if p.nsT then p.nsT:Cancel(); p.nsT = nil end
	p.nsStart, p.nsDur, p.nsN = start, duration, n
	NS.Eval(p)
end

-- the last N seconds on or off now, and ONE one-shot timer to the next change (never polled)
function NS.Eval(p)
	p.nsT = nil
	local s = p.nsStart
	if not s then NS.PartLate(p, false) return end
	local now, stop = GetTime(), s + p.nsDur
	if now >= stop then
		p.nsStart = nil
		NS.PartLate(p, false)
		return
	end
	local late = now >= stop - p.nsN
	NS.PartLate(p, late)
	p.nsT = C_Timer.NewTimer(max(0.01, (late and stop + 0.05 or stop - p.nsN) - now), p.nsFire)
end

-- a time left the game draws from numbers of ours: a duration text binding on `fs` (the game updates the
-- number, no Lua each frame), made once; no start: off. A client without one gets no number, never a
-- wrong one.
function NS.Time(p, fs, start, duration, formatter, interval)
	if p.bind == nil then
		p.bind = false
		local D = C_DurationUtil
		if D and D.CreateDurationTextBinding and D.CreateDuration then
			local ok, b = pcall(D.CreateDurationTextBinding)
			local okD, d = pcall(D.CreateDuration)
			if ok and b and okD and d and pcall(b.SetFontString, b, fs) then
				if formatter then pcall(b.SetFormatter, b, formatter) end
				if interval and b.SetUpdateInterval then pcall(b.SetUpdateInterval, b, interval) end
				if b.SetExpiredText then pcall(b.SetExpiredText, b, "") end
				p.bind, p.dur = b, d
			end
		end
	end
	if not start then
		if p.bind then pcall(p.bind.SetEnabled, p.bind, false) end
		fs:SetText("")
		return
	end
	if not p.bind then
		fs:SetText("")
		return
	end
	pcall(p.dur.SetTimeFromStart, p.dur, start, duration)
	pcall(p.bind.SetDuration, p.bind, p.dur)
	pcall(p.bind.SetEnabled, p.bind, true)
end

-- state 4's big time: tenths of a second (2.8), rounded up as WoW counts down (whole seconds from 10 on)
function NS.DecFormatter()
	if NS.dec ~= nil then return NS.dec or nil end
	NS.dec = false
	local S = C_StringUtil
	if not (S and S.CreateNumericRuleFormatter) then return nil end
	local ok, f = pcall(S.CreateNumericRuleFormatter)
	if not (ok and f and f.AddBreakpoint) then return nil end
	local up = Enum and Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Up or 1
	if pcall(f.AddBreakpoint, f, { threshold = 0, step = 0.1, rounding = up, format = "%.1f" }) then
		pcall(f.AddBreakpoint, f, { threshold = 10, step = 1, rounding = up, format = "%d" })
		NS.dec = f
	end
	return NS.dec or nil
end

-- ---------------------------------------------------------------------------
-- WoW: Forever (the game's containers): Next Shock's OWN Flame Shock slot (yours: HARMFUL|PLAYER and
-- Flame Shock's aura IDs) in a container of its own, its button sitting exactly on Target Tracker's
-- Flame Shock icon: over the icon, under its sweep and time left (the sweep runs over the shock, as on
-- Anniversary). The game shows that button only while YOUR Flame Shock is on your target, so nothing is
-- read: Earth Shock (or Frost Shock) on it, made once out of combat. Its last N seconds: a SECOND
-- container of its own (NS.lc; e.lc per nameplate), Flame Shock again over everything with the game's own
-- time big in tenths, switched on by ONE one-shot timer from the aura (out of a fight) or your own cast:
-- the game still shows it only while your Flame Shock is really there.
-- ---------------------------------------------------------------------------
function NS.GateSize()
	local scale = (H.debuffs and H.debuffs:GetScale()) or 1
	return Get("fs", "size") * scale
end

function NS.EFace(host)
	return NS.Parts(host, NS.ShockIcon())
end

function NS.EStyle(f, s)
	f.icon:SetTexture(NS.ShockIcon())
	NS.plain.size = s
	LK.Edge(f, "fs", NS.plain)
end

function NS.Init(button)
	button:ClearAllPoints()
	button:SetAllPoints(H.ns)
	NoMouse(button)
	local f = NS.EFace(button)
	NS.EStyle(f, NS.GateSize())
	NS.face = f
end

-- the last seconds on the game's own button (WoW: Forever): Flame Shock in the cast-it look, its time left
-- big in the middle (the game's own duration text, in tenths). Made once, out of combat, as the game makes
-- the button (AddSlot); out.late gets the parts. size: a function (the look follows the spot's scale).
function NS.LateInit(anchor, size, out)
	return function(button)
		button:ClearAllPoints()
		button:SetAllPoints(anchor)
		NoMouse(button)
		local L = NS.Parts(button, SPELL.fs.icon)
		L.text = Carrier(button, button:GetFrameLevel() + 2)
		L.big = L.text:CreateFontString(nil, "OVERLAY")
		L.big:SetFontObject(GameFontHighlight)   -- (a font at once: the game's button writes into it before ours is set)
		L.big:SetPoint("CENTER", button, "CENTER", 0, 0)
		Outline(L.big)
		local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
		cd:SetAllPoints(button)
		if cd.SetDrawSwipe then cd:SetDrawSwipe(false) end
		if cd.SetDrawEdge then cd:SetDrawEdge(false) end
		if cd.SetDrawBling then cd:SetDrawBling(false) end
		cd:SetHideCountdownNumbers(true)
		cd.noCooldownCount = true   -- (OmniCC and the like: the time left is drawn here)
		pcall(button.SetDurationCooldown, button, cd)
		local b = NS.LateBinding()
		if not (b and pcall(button.SetDurationText, button, L.big, { binding = b })) then
			pcall(button.SetDurationText, button, L.big, { textFormatter = NS.DecFormatter() })
		end
		NS.LStyle(L, size())
		out.late = L
	end
end

-- the last seconds' time left on the game's button ticks in tenths: a binding of ours, which the game copies
-- onto the button (its SetDurationText Assign()s options.binding), with the tenths formatter and a 0.1 s
-- update interval (the formatter alone keeps the binding's default interval). Made once; false where the
-- client has none (the formatter alone then).
function NS.LateBinding()
	if NS.lb ~= nil then return NS.lb or nil end
	NS.lb = false
	local D, f = C_DurationUtil, NS.DecFormatter()
	if not (D and D.CreateDurationTextBinding and f) then return nil end
	local ok, b = pcall(D.CreateDurationTextBinding)
	if not (ok and b and pcall(b.SetFormatter, b, f)) then return nil end
	if b.SetUpdateInterval then pcall(b.SetUpdateInterval, b, 0.1) end
	if b.SetExpiredText then pcall(b.SetExpiredText, b, "") end
	NS.lb = b
	return b
end

-- a refusal said once per kind (the plates' entries would fill the /sptt log otherwise)
NS.said = {}
function NS.Say(kind, fmt, ...)
	if NS.said[kind] then return end
	NS.said[kind] = true
	Log(fmt, ...)
end

-- the last seconds' look: the cast-it look at its size, its time left in WoW's gold (out of combat)
function NS.LStyle(L, s)
	NS.Look(L, Get("ns", "castLook"), false, s)
	SP:SetSPFont(L.big, "timers", NS.BigSize(s), "OUTLINE")
	L.big:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
end

-- state 4 on or off: the last seconds' own container (the game's own call, in a fight too). Nothing on the
-- game's buttons changes; the game shows that button only while your Flame Shock is really on your target.
function NS.Late(on)
	on = on and true or false
	if NS.lateOn == on then return end
	NS.lateOn = on
	local c = NS.lc
	if not c then return end
	pcall(c.SetEnabled, c, on)
	if on then pcall(c.UpdateAllAuras, c) end
end

function NS.Arm()
	local now, n = GetTime(), NS.sN
	local stop = NS.sStart + NS.sDur
	local at = stop + 0.1
	if n > 0 then
		if now < stop - n then
			at = stop - n
		elseif now < stop and not NS.lateOn then
			NS.Late(true)
		end
	end
	NS.timer = C_Timer.NewTimer(max(0.01, at - now), NS.Fire)
end

function NS.Fire()
	NS.timer = nil
	if not NS.sStart then return end
	if GetTime() < NS.sStart + NS.sDur then
		NS.Arm()
	else
		NS.Refresh()   -- (it ran out)
	end
end

function NS.Schedule(start, duration)
	local n = Get("ns", "refresh") or 0
	local s0 = NS.sStart
	if start and s0 and NS.sN == n and math.abs(s0 - start) < 0.2 and math.abs(s0 + NS.sDur - start - duration) < 0.2 then return end
	if not start and not s0 and not NS.timer and not NS.lateOn then return end
	if NS.timer then
		NS.timer:Cancel()
		NS.timer = nil
	end
	NS.Late(false)
	NS.sStart, NS.sDur, NS.sN = start, duration, n
	if start then NS.Arm() end
end

-- every icon's look. On WoW: Forever the game's buttons only out of combat and while the game shows auras
-- (its own guard: done when they show again otherwise)
function NS.Restyle()
	if engine and (InCombatLockdown() or AurasHidden()) then
		NS.dirty = true
		if InCombatLockdown() then NS.flush:RegisterEvent("PLAYER_REGEN_ENABLED") end
		return
	end
	NS.dirty = nil
	for _, L in ipairs(NS.overs) do NS.StyleOver(L) end
	for _, p in ipairs(NS.parts) do NS.Face(p) end
	local gs = NS.GateSize()
	if NS.face then NS.EStyle(NS.face, gs) end
	if NS.late then NS.LStyle(NS.late, gs) end
	local ps = Get("fs", "size")
	for _, e in ipairs(E.plateAll) do
		local q = e.nsP
		if q then
			NS.EStyle(q.face, ps)
			if q.late then NS.LStyle(q.late, ps) end
		end
	end
	NS.Refresh()
end

-- WoW: Forever, every nameplate: the same as your target's (its own container and Flame Shock slot on
-- that enemy, its button on that plate's Flame Shock icon), and its last seconds' container, made out of
-- combat once per nameplate entry. Out of combat is enough, in a Battleground or Arena too: the game runs a
-- button's setup (initializeFrame) before it locks the button while auras are hidden (Blizzard's
-- AuraContainerCustomFrameProvider CreateFrame). A refusal can be passing: each part is asked again on later
-- passes (NS.Apply), three times at most (nil: ask again; false: given up).
function NS.PlateBuild(e)
	if not (engine and e.c and e.cells.fs) or InCombatLockdown() then return end
	if e.nc == nil then
		local c = NewContainer(e.row)
		-- (the levels before the slots: the game's buttons, and what is made on them, take them then)
		-- (over the Flame Shock icon, under its sweep and time left: the sweep runs over the shock, as on Anniversary)
		if c then c:SetFrameLevel(e.c:GetFrameLevel() + 1) end
		local got
		local ok, err = false, nil
		if c then
			ok, err = AddSlot(c, "ns", "HARMFUL|PLAYER", { includeSpellIDs = AURA_IDS.fs }, function(button)
				button:ClearAllPoints()
				button:SetAllPoints(e.cells.fs)
				NoMouse(button)
				got = NS.EFace(button)
				NS.EStyle(got, Get("fs", "size"))
			end, true)
		end
		if not (ok and got) then
			if c then c:Hide() end
			e.nsTries = (e.nsTries or 0) + 1
			if e.nsTries >= 3 then e.nc = false end
			NS.Say("plateFace", "next shock: the game refused a nameplate's Flame Shock slot (%s)", tostring(err))
			return
		end
		pcall(c.SetEnabled, c, false)
		pcall(c.SetUnit, c, e.unit or "none")
		e.nc, e.nsOn = c, false
		local q = { nsF = true, face = got }
		q.nsFire = function() NS.Eval(q) end
		e.nsP = q
	end
	if e.nc and e.lc == nil then
		-- its last seconds: a second container of its own (the game's button in the cast-it look), over the
		-- icon's time left; off until that enemy's timer says so
		local out = {}
		local lc = NewContainer(e.row)
		if lc then lc:SetFrameLevel(e.c:GetFrameLevel() + 6) end
		local ok, err = false, nil
		if lc then
			ok, err = AddSlot(lc, "nsl", "HARMFUL|PLAYER", { includeSpellIDs = AURA_IDS.fs },
				NS.LateInit(e.cells.fs, function() return Get("fs", "size") end, out), true)
		end
		if ok and out.late then
			pcall(lc.SetEnabled, lc, false)
			pcall(lc.SetUnit, lc, e.unit or "none")
			local q = e.nsP
			e.lc, q.lc, q.late = lc, lc, out.late
			if q.nsStart then
				-- (asked again while that enemy's Flame Shock runs: its timer set again, on at once if it is late)
				if q.nsT then q.nsT:Cancel(); q.nsT = nil end
				q.nsLate = nil
				NS.Eval(q)
			end
		else
			if lc then lc:Hide() end
			e.lcTries = (e.lcTries or 0) + 1
			if e.lcTries >= 3 then e.lc = false end
			NS.Say("plateLate", "next shock: the game refused a nameplate's last seconds (%s); Earth Shock still shows there",
				tostring(err))
		end
	end
end

-- a nameplate's Next Shock on or off (the game's own call, in a fight too): only where its Flame Shock shows
function NS.PlateSync(e)
	if not e.nc then return end
	local on = NS.wanted and e.unit ~= nil and e.keyOn.fs and true or false
	if e.nsOn ~= on then
		e.nsOn = on
		pcall(e.nc.SetEnabled, e.nc, on)
		-- (the game's container never reads the enemy's auras again by itself: as on a new target)
		if on then pcall(e.nc.UpdateAllAuras, e.nc) end
	end
	if e.nsP then
		local st, du
		if on then st, du = NS.RecOf(e.unit) end
		NS.Track(e.nsP, st, du)
	end
end

-- WoW: Forever: Next Shock's containers on your target, made once out of combat, after Target Tracker's own
-- (icons of ours need nothing of their own). Out of combat is enough, in a Battleground or Arena too (see
-- NS.PlateBuild). A refusal can be passing: asked again on later passes, three times at most.
function NS.Build()
	if NS.built then return end
	if FOREVER and InCombatLockdown() then return end
	EnsureHolders()
	if engine then
		if not E.tc then return end   -- (Target Tracker's own container first)
		if not NS.c then
			NS.engine = false
			local c = NewContainer(E.Gate())
			-- (the levels before the slots: the game's buttons, and what is made on them, take them then)
			-- (over the Flame Shock icon, under its sweep and time left: the sweep runs over the shock, as on Anniversary)
			if c then c:SetFrameLevel(E.tc:GetFrameLevel() + 1) end
			local ok, err = false, nil
			if c then ok, err = AddSlot(c, "ns", "HARMFUL|PLAYER", { includeSpellIDs = AURA_IDS.fs }, NS.Init, true) end
			NS.bound = ok and pcall(c.SetUnit, c, "target") or false
			if NS.bound and NS.face then
				pcall(c.SetEnabled, c, false)   -- (on while Next Shock shows: NS.Apply)
				NS.enabled = false
				NS.c, NS.engine = c, true
			else
				if c then c:Hide() end
				NS.face = nil
				NS.tries = (NS.tries or 0) + 1
				NS.Say("face", "next shock: the game refused its container (%s)", tostring(err))
				if NS.tries < 3 then return end   -- (a refusal can be passing)
			end
		end
		NS.BuildLate()
		Log("next shock: %s", NS.engine and "built" or "not built")
	end
	NS.built = true
	for _, e in ipairs(E.plateAll) do NS.PlateBuild(e) end
end

-- your target's last seconds: a second container of Next Shock's own, over the icon's time left (off until the
-- timer). Out of combat; asked again on later passes (NS.Apply), three times at most (nil: ask again; false:
-- given up).
function NS.BuildLate()
	if not (NS.c and NS.lc == nil) or InCombatLockdown() then return end
	local out = {}
	local lc = NewContainer(E.Gate())
	if lc then lc:SetFrameLevel(E.tc:GetFrameLevel() + 6) end   -- (over the icon's time left)
	local ok, err = false, nil
	if lc then
		ok, err = AddSlot(lc, "nsl", "HARMFUL|PLAYER", { includeSpellIDs = AURA_IDS.fs }, NS.LateInit(H.ns, NS.GateSize, out), true)
	end
	if ok and out.late and pcall(lc.SetUnit, lc, "target") then
		pcall(lc.SetEnabled, lc, false)
		NS.lc, NS.late = lc, out.late
		-- (it starts off; already in its last seconds, as the timer said meanwhile: on at once)
		local late = NS.lateOn
		NS.lateOn = false
		if late then NS.Late(true) end
		return
	end
	if lc then lc:Hide() end
	NS.lcTries = (NS.lcTries or 0) + 1
	if NS.lcTries >= 3 then NS.lc = false end
	NS.Say("late", "next shock: the game refused its last seconds (%s); Earth Shock still shows", tostring(err))
end

-- Next Shock's spot: exactly Target Tracker's Flame Shock icon (anchored once: it moves with it)
function NS.Place()
	local f = H.ns
	if not f then return end
	local cell = cells.fs and cells.fs.frame
	if not (NS.engine and cell) then
		placed.ns = false
		f:Hide()
		return
	end
	if f.spOn ~= cell then
		f:ClearAllPoints()
		f:SetScale(1)
		f:SetClampedToScreen(false)
		f:SetAllPoints(cell)
		f.spOn = cell
	end
	-- the row's scale (bigger or smaller on a nameplate): the looks on the game's buttons are drawn again for
	-- it (out of combat and while the game shows auras; once it does otherwise)
	local k = H.debuffs:GetScale()
	if NS.scale ~= k then
		NS.scale = k
		NS.Restyle()   -- (its own guard: after the fight, or once auras show again)
	end
	placed.ns = placed.debuffs and cells.fs.slot and true or false
end

-- your target's Next Shock shows right now: Next Shock and Target Tracker on, its spot there, Flame Shock's
-- own rules say Flame Shock shows here and now (Show In / Out of Combat, Hide This Spell, a rule), and not
-- while Unlock UI shows its stand-ins. (Each nameplate follows its own row: OnPlate.want.)
function NS.TargetWant(on)
	return on and NS.On() and not demo.debuffs and placed.ns and CellWanted("fs") and true or false
end

-- what shows right now (cheap; in a fight too: frames of ours, and the containers' own on / off)
function NS.Apply(on)
	NS.wanted = on and NS.On() or false
	NS.tWant = NS.TargetWant(on)
	for _, p in ipairs(NS.parts) do NS.Face(p) end
	if NS.engine then
		local want = NS.tWant
		H.ns:SetShown(want)
		if NS.c and NS.enabled ~= want then
			NS.enabled = want
			pcall(NS.c.SetEnabled, NS.c, want)
		end
	end
	if NS.wanted and not InCombatLockdown() then
		NS.BuildLate()   -- (a refusal asked again)
		for _, e in ipairs(E.plateAll) do NS.PlateBuild(e) end   -- (turned on after the nameplates were made)
	end
	NS.Refresh()
end
-- Flame Shock's duration per spell ID, learned from the aura wherever the game shows it (until then each
-- client's own spell data, NS.BASE); the aura your last cast put on counts for that cast's ID too
function NS.Learn(r)
	local d = r.duration
	if not (d and d > 0) then return end
	if r.spell then NS.learned[r.spell] = d end
	local c = NS.last
	if c.id and math.abs(r.start - c.t) < 1 then NS.learned[c.id] = d end
end

-- your Flame Shock on your target: its start and duration (nil: not on, or not known). From the aura itself
-- wherever the game shows it; in a fight on WoW: Forever (where only the game's button knows whether it is
-- on) from your own cast
NS.GRACE = 1.5   -- seconds a cast's aura may take to land (the readable path waits that long for it)
function NS.Rec()
	local c = NS.cur
	if not AurasHidden() then
		local r = tgt.mine.fs
		if r.id then
			NS.Learn(r)
			NS.from = "the aura"
			return r.start, r.duration
		end
		-- no aura where the game shows auras: it is not there (a resist, an immunity, a dispel, it ran out),
		-- unless your cast just went out and its aura has not landed yet (an opener just before a pull). With
		-- icons of ours, the tracker alone decides.
		if engine and c and GetTime() - c.start < NS.GRACE then
			NS.from = "your cast"
			return c.start, c.duration
		end
		return nil
	end
	if c and GetTime() < c.start + c.duration then
		NS.from = "your cast"
		return c.start, c.duration
	end
	return nil
end

-- an enemy's record from your own casts, by its GUID (nil where the game hides who it is)
function NS.RecOf(unit)
	local g = UnitGUID(unit)
	if secret(g) or type(g) ~= "string" then return nil end
	local r = NS.recs[g]
	if r and GetTime() < r.start + r.duration then return r.start, r.duration end
	return nil
end

-- each enemy's Flame Shock icon follows its own Flame Shock: icons of ours (Anniversary) their own records
-- (ShowRec); on WoW: Forever your target's from its aura or your cast (state 4's timer)
function NS.Refresh()
	if not NS.built then return end
	for _, p in ipairs(NS.parts) do
		NS.Track(p, p.shownId and p.shownStart or nil, p.shownDur)
	end
	if NS.engine then
		local s, d
		if NS.tWant then s, d = NS.Rec() end   -- (Flame Shock's own rules hide it: no last seconds either)
		NS.Schedule(s, d)
	end
	for _, e in pairs(plateUsed) do
		if e.nc then NS.PlateSync(e) end
	end
	for _, e in ipairs(E.plateAll) do
		if e.nc and not e.unit then NS.PlateSync(e) end
	end
end
-- your target, when the game names it (its GUID; nil where it hides it)
function NS.Guid()
	local g = UnitGUID("target")
	if secret(g) or type(g) ~= "string" then return nil end
	return g
end

-- one of your Flame Shock casts landed: a record for your target (its own, by GUID, where the game names it)
function NS.Cast(id)
	local now = GetTime()
	NS.last.id, NS.last.t = id, now
	if not TargetAttackable() then return end   -- (it went to another unit: a mouseover or focus macro)
	local rec = { start = now, duration = NS.learned[id] or NS.BASE }
	local g = NS.Guid()
	if g then
		for k, r in pairs(NS.recs) do
			if r.start + r.duration < now then NS.recs[k] = nil end   -- (the ones that ran out)
		end
		NS.recs[g] = rec
	end
	NS.cur = rec
	NS.Refresh()
end

-- a new target: its own record where the game names it (its GUID). Where the game hides who it is, there is
-- none until your next Flame Shock on it: after you switch away and back, Next Shock shows Earth Shock (or
-- Frost Shock) while your Flame Shock is on it, without its last seconds, until that next cast (never a guess)
function NS.TargetChanged()
	NS.cur = nil
	if not NS.On() then return end
	local g = NS.Guid()
	local r = g and NS.recs[g]
	if r and GetTime() < r.start + r.duration then NS.cur = r end
	if not NS.built then return end
	-- (the game's containers start over on the new target: they never tell it themselves)
	if NS.c then pcall(NS.c.UpdateAllAuras, NS.c) end
	if NS.lc then pcall(NS.lc.UpdateAllAuras, NS.lc) end
	NS.Refresh()
end

-- your own casts (registered only while Next Shock is on): Flame Shock, any rank. UNIT_SPELLCAST_SENT names
-- the unit a cast goes to: one sent to another unit than your target (a mouseover or focus macro: another
-- name, where the game shows both) is not your target's
NS.castFrame = CreateFrame("Frame")
NS.castFrame:SetScript("OnEvent", function(_, event, unit, a2, a3, a4)
	if secret(unit) or unit ~= "player" then return end
	if event == "UNIT_SPELLCAST_SENT" then
		local name, guid, id = a2, a3, a4
		if secret(id) or not AURA_IDS.fs[id] then return end
		NS.sentOff, NS.sentGuid = false, nil
		if not secret(guid) then NS.sentGuid = guid end
		if secret(name) or type(name) ~= "string" or name == "" then return end
		local t = UnitName("target")
		if secret(t) or type(t) ~= "string" then return end
		if (name:match("^([^%-]+)") or name) ~= t then NS.sentOff = true end
		return
	end
	local guid, id = a2, a3   -- UNIT_SPELLCAST_SUCCEEDED
	if secret(id) or not AURA_IDS.fs[id] then return end
	local off = NS.sentOff and (NS.sentGuid == nil or secret(guid) or NS.sentGuid == guid)
	NS.sentOff = false
	if not off then NS.Cast(id) end
end)

-- ---------------------------------------------------------------------------
-- The look of every part, changed on the parts already there. The game's buttons
-- (WoW: Forever) are touched only out of combat and not while the game hides
-- auras (as all through a Battleground or Arena); icons of our own (Anniversary)
-- change at once, in a fight too.
-- ---------------------------------------------------------------------------
local standins = { debuffs = {}, purge = nil }
local function Restyle()
	if engine and (InCombatLockdown() or AurasHidden()) then
		pending.look = true
		afterFight:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	pending.look = nil
	-- your target's icons hang under the gate, not in the row: their text is sized for the row's scale
	local ps = SV().showOn == "plate" and K.PLATE_SCALE or 1
	for _, key in ipairs(DEBUFFS) do
		local look = DebuffLook(key)
		local scaled = DebuffLook(key, Get(key, "size") * ps)
		if E.parts[key] then StyleDebuff(E.parts[key], scaled) end
		if E.miss[key] then StyleDebuff(E.miss[key], scaled) end
		local c = cells[key]
		if c and c.p then StyleDebuff(c.p, scaled) end
		for _, e in ipairs(E.plateAll) do
			if e.parts[key] then StyleDebuff(e.parts[key], look) end
			if e.miss[key] then StyleDebuff(e.miss[key], look) end
		end
	end
	local pl = PurgeLook()
	local pps = Get("purge", "showOn") == "plate" and K.PURGE_PLATE_SCALE or 1
	if E.parts.purge then StylePurge(E.parts.purge, PurgeLook(Get("purge", "size") * pps)) end
	if E.purgeIcon then StylePurge(E.purgeIcon, pl) end
	for _, b in pairs(E.boss) do
		if b.p.purge then StylePurge(b.p.purge, pl) end
	end
	local plp = OnPlate.PurgeLook()
	for _, e in ipairs(E.plateAll) do
		if e.parts.purge then StylePurge(e.parts.purge, plp) end
	end
	OnPlate.GameResize()   -- (WoW's row redrawn: its icons at WoW's size)
	NS.Restyle()
end

-- ---------------------------------------------------------------------------
-- Build: the frames the module needs. Each is made once; looks change on the
-- parts already there. Anniversary's are plain frames, made in a fight too;
-- WoW: Forever makes the game's containers out of combat (turned on for the
-- first time in a fight, it says so once and starts when the fight ends).
-- ---------------------------------------------------------------------------
local function BuildCells()
	for _, key in ipairs(DEBUFFS) do
		if Usable(key) and not cells[key] then
			local c = { key = key, frame = CreateFrame("Frame", nil, H.debuffs) }
			c.frame:SetSize(36, 36)
			c.frame:Hide()
			cells[key] = c
		end
	end
end

local function Build()
	if InCombatLockdown() and FOREVER then
		pending.build = true
		afterFight:RegisterEvent("PLAYER_REGEN_ENABLED")
		if not built and not pending.told then
			pending.told = true
			SP:Print("Target Tracker starts when this fight ends.")
		end
		return false
	end
	pending.build = nil
	EnsureHolders()
	BuildCells()
	E.Gate()
	if EngineAvailable() then
		if cells.fs and cells.frs and cells.ss then BuildTarget() end
	end
	if not engine or not E.tc then
		engine = false   -- (no container: the icons are filled in here, out of combat on WoW: Forever)
		for key, c in pairs(cells) do
			if not c.p then
				-- under the gate (shown by the game only while you have an attackable, living target:
				-- a target that dies hides it with no code of ours running), on its spot in the row
				c.g = CreateFrame("Frame", nil, E.gate)
				c.g:SetAllPoints(c.frame)
				c.g:Hide()
				local host = Carrier(c.g)
				host:Hide()
				c.p = DebuffParts(host, key, DebuffLook(key))
				c.p.host = host
				if key == "fs" then NS.Attach(c.p) end   -- (Next Shock rides on it)
			end
		end
		if not E.purgeIcon and Usable("purge") then
			local host = CreateFrame("Frame", nil, H.purgeCell)
			host:SetAllPoints(H.purge)
			host:Hide()
			E.purgeIcon = PurgeParts(host, PurgeLook())
			E.purgeIcon.at = H.purge
		end
	end
	built = true
	-- sized for where the parts sit now (a saved "On your target's nameplate" at login: the target's text
	-- and Purge's picture for the plate's scale); it waits for the end of a fight by itself
	Restyle()
	return true
end

-- ---------------------------------------------------------------------------
-- Events. The module listens only while it is on, and only for what its parts
-- need right now: nameplates only while something uses them, UNIT_AURA for the
-- target only where its icons are filled in here (Anniversary).
-- ---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local auraFrame = CreateFrame("Frame")   -- UNIT_AURA for "target" (RegisterUnitEvent: the game filters)
local bossFrames = { CreateFrame("Frame"), CreateFrame("Frame"), CreateFrame("Frame") }   -- boss1-5, two a frame
local L = { core = false, plates = false, aura = false, boss = false, casts = false }   -- what is registered now (casts: Next Shock's)
-- WoW: Forever lets auras be read again a moment after a fight ends: your target's are read again then (Next
-- Shock's record of your Flame Shock; the icons of ours where the game's containers are not used)
if SPCompat and SPCompat.OnUnrestricted then
	SPCompat.OnUnrestricted(function()
		if not (FOREVER and L.aura) then return end
		TrackFull(tgt, true, not engine)
		RefreshIcons()
		if NS.On() and not NS.built then
			Update()   -- (Next Shock waited for the game to let it build)
		elseif NS.dirty then
			NS.Restyle()
		elseif NS.built then
			NS.Refresh()
		end
	end)
end
local BOSS_UNITS = { { "boss1", "boss2" }, { "boss3", "boss4" }, { "boss5" } }
local CORE_EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
	"PLAYER_TARGET_CHANGED", "ENCOUNTER_START", "ENCOUNTER_END", "SPELLS_CHANGED", "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
	"UNIT_FACTION" }

local function PlatePlacement()
	return SV().showOn == "plate" or Get("purge", "showOn") == "plate"
end

local function SetListening()
	local on = ModuleOn()
	if on ~= L.core then
		L.core = on
		for _, e in ipairs(CORE_EVENTS) do
			if on then pcall(ev.RegisterEvent, ev, e) else ev:UnregisterEvent(e) end
		end
	end
	-- nameplates: while your debuffs or Purge sit on your target's, or a spell is on every nameplate here
	local plates = on and (PlatePlacement() or OnPlate.anyLay) or false
	if plates ~= L.plates then
		L.plates = plates
		if plates then
			ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
			ev:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
		else
			ev:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
			ev:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
		end
	end
	-- WoW's own nameplate options (whether WoW shows its row of your debuffs, how big): only while WoW:
	-- Forever redraws that row on nameplates
	local cv = plates and engine and OnPlate.hiding and true or false
	if cv ~= L.cvar then
		L.cvar = cv
		if cv then
			OnPlate.showAll = OnPlate.ShowAll()   -- (WoW's option, as it is now)
			pcall(ev.RegisterEvent, ev, "CVAR_UPDATE")
		else
			ev:UnregisterEvent("CVAR_UPDATE")
		end
	end
	-- the target's auras: only where they are read here, and only while a part on the target is on
	local aura = false
	if on and built and not engine then
		for key in pairs(cells) do
			if CellWanted(key) then aura = true end
		end
		if E.purgeIcon and PurgeWanted() then aura = true end
	end
	-- Next Shock reads your Flame Shock on your target wherever the game shows it (both game versions:
	-- on WoW: Forever out of a fight), and follows your own Flame Shock casts
	local ns = on and built and NS.On() or false
	if ns then aura = true end
	if aura ~= L.aura then
		L.aura = aura
		if aura then
			auraFrame:RegisterUnitEvent("UNIT_AURA", "target")
			TrackFull(tgt, true, not engine)
		else
			auraFrame:UnregisterEvent("UNIT_AURA")
		end
	end
	if ns ~= L.casts then
		L.casts = ns
		if ns then
			NS.castFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
			NS.castFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		else
			NS.castFrame:UnregisterAllEvents()
		end
	end
	-- the bosses' buffs: only in a boss fight, and only where they are read here
	local boss = aura and not engine and encounter.id ~= nil and Get("purge", "watchBosses") and PurgeWanted() or false
	if boss ~= L.boss then
		L.boss = boss
		for i, f in ipairs(bossFrames) do
			if boss then f:RegisterUnitEvent("UNIT_AURA", BOSS_UNITS[i][1], BOSS_UNITS[i][2]) else f:UnregisterEvent("UNIT_AURA") end
		end
		for i = 1, 5 do TrackFull(bossT[i], false, boss) end
	end
end

-- the bosses' containers: shown between the pull and the end of the fight, each while its boss is there
local function SyncBosses()
	if not E.bossLayer then return end
	local want = ModuleOn() and not demo.purge and encounter.id ~= nil and Get("purge", "watchBosses") and PurgeWanted() or false
	E.bossLayer:SetShown(want)
	for i, b in pairs(E.boss) do
		local show = false
		if want then
			local ex = UnitExists("boss" .. i)
			show = secret(ex) or ex and true or false   -- (an answer the game hides counts as there)
		end
		if b.c:IsShown() ~= show then b.c:SetShown(show) end
		if b.on ~= show then   -- (out of a boss fight they do not even listen)
			b.on = show
			pcall(b.c.SetEnabled, b.c, show)
		end
	end
end

-- the Missing Warnings under your target's slots (WoW: Forever): each shown while its spell's slot is
-- on, its Missing Warning is wanted right now, the container is bound to your target and your target is
-- one the game says you can attack (the real debuff, drawn on top by the game, covers it while it is on)
function E.SyncMiss(on)
	for _, key in ipairs(DEBUFFS) do
		local m = E.miss[key]
		if m then
			m.host:SetShown(on and not demo.debuffs and placed.debuffs and E.bound and E.slotOk[key] and E.slotOn[key]
				and tgt.warn and MissingOn(key) and ModeOK(key) or false)
		end
	end
end

-- the game's state driver can't be set up in a fight (the module turned on in one): until the fight ends
-- the gate follows your target from here (shown for an attackable, living target; the gate is a plain frame)
function E.GateByHand(on)
	if E.gate and not E.driver and on and TargetNeeded() then E.gate:SetShown(TargetAttackable()) end
end

-- every frame shown or hidden for what is on right now (cheap; in a fight too)
Apply = function()
	if not built then return end
	local on = ModuleOn()
	if ReadPurgeLimit() then
		if L.aura then TrackFull(tgt, true, not engine) end
		OnPlate.stale = true   -- (Anniversary: every plate's Magic buffs are read again)
	end
	H.debuffs:SetShown(demo.debuffs or (on and placed.debuffs) or false)
	H.purge:SetShown(demo.purge or (on and placed.purge) or false)
	for key, c in pairs(cells) do
		local show = on and not demo.debuffs and c.slot and CellWanted(key) or false
		c.frame:SetShown(show)
		if c.g then c.g:SetShown(show and placed.debuffs) end   -- (Anniversary: the icon's spot under the gate)
	end
	if E.tc then
		if E.enabled ~= on then
			E.enabled = on
			pcall(E.tc.SetEnabled, E.tc, on)
		end
		for _, key in ipairs(DEBUFFS) do
			local c = cells[key]
			SlotEnable(key, on and not demo.debuffs and placed.debuffs and c ~= nil and c.slot and CellWanted(key) or false)
		end
		SlotEnable("purge", on and not demo.purge and placed.purge and PurgeWanted() or false)
		E.SyncMiss(on)
	end
	H.purgeCell:SetShown(on and not demo.purge and PurgeWanted() or false)
	SyncDriver()
	E.GateByHand(on)
	SyncBosses()
	OnPlate.Compute()
	H.plates:SetShown(on and OnPlate.anyLay or false)
	OnPlate.hiding = on and SV().hideGame == true or false
	if not engine then
		-- Anniversary: a plate's Magic buffs read again when Purge's Every Nameplate or its Long Buffs
		-- changed; a plate not read yet (auras hidden by the game) read once they show
		local magic = OnPlate.want.purge
		local again = OnPlate.stale or magic ~= OnPlate.readMagic
		OnPlate.stale, OnPlate.readMagic = nil, magic
		for _, e in pairs(plateUsed) do
			if again or not e.fresh then e.fresh = TrackFull(e.t, true, magic) end
		end
	end
	OnPlate.SyncAll()
	SetListening()
	RefreshIcons()
	NS.Apply(on)
	OnPlate.SyncGame()
end

local function Layout()
	if not built then return end
	OnPlate.Compute()
	LayoutDebuffs()
	PlaceDebuffs()
	PlacePurge()
	NS.Place()   -- (after the two: under the target frame it goes under them)
	for _, e in pairs(plateUsed) do OnPlate.Layout(e) end
end

-- any spell can be on every nameplate (its own setting, or a rule): the entries are made ahead
local function PlatesPossible()
	for _, s in ipairs(SPELLS) do
		if Get(s.key, "everyPlate") then return true end
	end
	for _, rule in ipairs(SV().rules) do
		if rule.part == "plates:on" then return true end
	end
	return false
end

-- everything again: frames made if needed, laid out, shown for what is on
Update = function()
	if SV().enabled and not SP:IsOff() and not built then Build() end
	if not built then
		SetListening()
		return
	end
	local on = ModuleOn()
	if on then tgt.warn = OnPlate.WarnOK("target") end
	if engine and on then
		-- the game's containers are made out of combat only: Watch Bosses' and Every Nameplate's,
		-- wanted in a fight, are made when it ends; so are the groups that redraw WoW's row of your
		-- debuffs (Hide WoW's Own Icons, while WoW shows that row: never made otherwise)
		local bosses = not E.bossLayer and E.BossesPossible()
		local plates = #E.plateAll < K.POOL and PlatesPossible()
		local groups = not OnPlate.groupsBuilt and OnPlate.GroupsWanted()
		if InCombatLockdown() then
			if bosses or plates or groups then
				pending.build = true
				afterFight:RegisterEvent("PLAYER_REGEN_ENABLED")
			end
		else
			pending.build = nil
			if bosses then BuildBosses() end
			if plates then OnPlate.FillPool() end
			if groups then OnPlate.BuildGroups() end
		end
	end
	-- Next Shock, the first time it is on (WoW: Forever makes its containers out of combat only: a fight waits)
	if on and NS.On() and not NS.built then
		if FOREVER and InCombatLockdown() then
			pending.build = true
			afterFight:RegisterEvent("PLAYER_REGEN_ENABLED")
		else
			NS.Build()
		end
	end
	EvaluateRules()
	Layout()
	Apply()
end

afterFight:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	if pending.look then Restyle() end
	if NS.dirty then NS.Restyle() end   -- (its own guard: waits again while the game hides auras)
	if pending.filters then ApplyFilters() end
	if pending.build or pending.driver then Update() end
	-- nameplates the game refused in the fight (or that found no free entry): now
	if next(OnPlate.waiting) and ModuleOn() and OnPlate.anyLay then
		local list = OnPlate.scratch
		wipe(list)
		for unit in pairs(OnPlate.waiting) do list[#list + 1] = unit end
		for i = 1, #list do OnPlate.Attach(list[i]) end
		wipe(list)
	end
end)

local LayoutStage   -- the settings preview (further down)
local stageOn = false
Changed = function(kind)
	if kind == "look" then
		if built then Restyle() end
		Update()
	elseif kind == "filters" then
		QueueFilters()
		Update()
	elseif kind == "rules" then
		ReadTargetName()   -- (a rule naming the enemy you have targeted applies at once)
		Update()
	else
		Update()
	end
	Watch()
	if stageOn and LayoutStage then LayoutStage() end
	-- Unlock UI is up (a size changed with the mouse wheel over Purge's box): its stand-ins follow
	if demo.debuffs and SP.TargetTrackerDebuffsDemo then SP:TargetTrackerDebuffsDemo(true) end
	if demo.purge and SP.TargetTrackerPurgeDemo then SP:TargetTrackerPurgeDemo(true) end
	if demo.ns and SP.TargetTrackerNextShockBoxDemo then SP:TargetTrackerNextShockBoxDemo(true) end
end

-- ---------------------------------------------------------------------------
-- Event handlers
-- ---------------------------------------------------------------------------
local function OnTargetChanged()
	if not ModuleOn() then return end
	OnPlate.tried.target = nil
	-- the game's container starts over on the new target (it never tells it itself)
	if E.tc then pcall(E.tc.UpdateAllAuras, E.tc) end
	-- no Missing Warning on an enemy's totem, pet or guardian, a critter, or one the game won't say you can attack
	local w = OnPlate.WarnOK("target")
	local apply = w ~= tgt.warn
	tgt.warn = w
	local oldD, oldP = H.debuffs.spPlate, H.purge.spPlate
	if PlatePlacement() then
		local d, p, n = placed.debuffs, placed.purge, placed.ns
		PlaceDebuffs()
		PlacePurge()
		NS.Place()
		if d ~= placed.debuffs or p ~= placed.purge or n ~= placed.ns then apply = true end
	end
	if apply then Apply() else E.GateByHand(true) end
	-- the plates your target left and came to: their entries step back in or aside, WoW's own icons come
	-- back or hide, at once
	-- (the plates it came to first: your target's container moves on to the new plate's row without turning off)
	OnPlate.Touch(H.debuffs.spPlate)
	OnPlate.Touch(H.purge.spPlate)
	OnPlate.Touch(oldD)
	OnPlate.Touch(oldP)
	if L.aura then
		TrackFull(tgt, true, not engine)
		RefreshIcons()
	end
	NS.TargetChanged()
	-- last: a rule that names a target (a name the game hides never stops the rest)
	if nameRules then
		ReadTargetName()
		if EvaluateRules() then
			Layout()
			Apply()
		end
	end
end

auraFrame:SetScript("OnEvent", function(_, _, unit, info)
	if secret(unit) or unit ~= "target" then return end
	-- (Magic buffs only where Purge is filled in here: the game's containers draw it on WoW: Forever)
	if TrackUpdate(tgt, info, true, not engine) then
		RefreshIcons()
		NS.Refresh()
	end
end)

for _, f in ipairs(bossFrames) do
	f:SetScript("OnEvent", function(_, _, unit, info)
		if secret(unit) or type(unit) ~= "string" then return end
		local i = tonumber(unit:match("^boss(%d)$"))
		if i and bossT[i] and TrackUpdate(bossT[i], info, false, true) then RefreshIcons() end
	end)
end

function OnPlate.Event(event, unit)
	if secret(unit) or type(unit) ~= "string" then return end
	local plate = PlateOf(unit)
	if event == "NAME_PLATE_UNIT_ADDED" then
		OnPlate.tried[unit] = nil
		if ModuleOn() and OnPlate.anyLay then OnPlate.Attach(unit) end
		-- your target's plate came: your debuffs, Purge and Next Shock go on it
		if PlatePlacement() and plate and plate == TargetPlate() then
			OnPlate.tried.target = nil
			PlaceDebuffs()
			PlacePurge()
			NS.Place()
			Apply()
		end
	else
		OnPlate.Detach(unit)
		-- the plate a spot hangs off is going (the game may still name it your target's)
		if plate and (plate == H.debuffs.spPlate or plate == H.purge.spPlate) then
			if plate == H.debuffs.spPlate then
				-- (Next Shock sits on your debuffs' Flame Shock: off with them; NS.Place puts it back with the plate)
				placed.debuffs, placed.ns, H.debuffs.spPlate = false, false, nil
				Park(H.debuffs)
			end
			if plate == H.purge.spPlate then
				H.purge.spPlate = nil
				Park(H.purge)
				placed.purge = false
				H.bossSpot:ClearAllPoints()
				H.bossSpot:SetScale(1)
				if not SP:ApplyPositionRecord(H.bossSpot, SV().purgePos or K.SPOT.purge) then
					H.bossSpot:SetPoint("CENTER", UIParent, "CENTER", 200, 40)
				end
			end
			Apply()
		end
	end
end

-- someone turned hostile or friendly where you can see them (a duel starting or ending, mind control, an
-- enemy that turns on you): your target's Missing Warnings and that enemy's nameplate row follow at once
-- (a rare event; nothing is made or read for it)
function OnPlate.Faction(unit)
	if secret(unit) or type(unit) ~= "string" then return end
	local w = OnPlate.WarnOK("target")
	if w ~= tgt.warn then
		tgt.warn = w
		Apply()
	end
	if not (OnPlate.live and unit:find("^nameplate%d")) then return end
	local e = plateUsed[unit]
	if not e then
		OnPlate.Attach(unit)   -- (only one you can attack gets a row)
		return
	end
	local can = UnitCanAttack("player", unit)
	if not secret(can) and not can then
		OnPlate.Detach(unit)   -- turned friendly: no row on it
	else
		local ew = OnPlate.WarnOK(unit)
		if ew ~= e.warn then
			e.warn = ew
			OnPlate.Sync(e)
		end
	end
end

ev:SetScript("OnEvent", function(_, event, a1, a2)
	if event == "PLAYER_TARGET_CHANGED" then
		OnTargetChanged()
	elseif event == "PLAYER_REGEN_DISABLED" then
		inCombat = true
		-- one that turned hostile while you had it targeted or in sight (a duel, an event enemy): its Missing
		-- Warnings and its nameplate row at the pull (only the plates that were friendly are looked at again)
		tgt.warn = OnPlate.WarnOK("target")
		if OnPlate.live and next(OnPlate.skipped) then
			local list = OnPlate.scratch
			wipe(list)
			for unit in pairs(OnPlate.skipped) do list[#list + 1] = unit end
			for i = 1, #list do OnPlate.Attach(list[i]) end
			wipe(list)
		end
		Apply()
	elseif event == "PLAYER_REGEN_ENABLED" then
		inCombat = false
		-- (WoW: Forever without its containers, or with Next Shock on: your target's auras, hidden in the
		-- fight, are read again)
		if FOREVER and L.aura then TrackFull(tgt, true, not engine) end
		if pending.build or pending.driver then Update() else Apply() end
	elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
		OnPlate.Event(event, a1)
	elseif event == "UNIT_FACTION" then
		OnPlate.Faction(a1)
	elseif event == "CVAR_UPDATE" then
		OnPlate.CVar(a1)
	elseif event == "ENCOUNTER_START" then
		local id, name = a1, a2
		if secret(id) then id = nil end
		if secret(name) then name = nil end
		encounter.id = tonumber(id) or -1   -- a fight the game will not name still counts as a boss fight
		encounter.name = type(name) == "string" and name or nil
		if EvaluateRules() then Layout() end
		Apply()
	elseif event == "ENCOUNTER_END" then
		encounter.id, encounter.name = nil, nil
		if EvaluateRules() then Layout() end
		Apply()
	elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
		-- the bosses changed: their containers (or reads) start over
		SyncBosses()
		for _, b in pairs(E.boss) do
			if b.c:IsShown() then pcall(b.c.UpdateAllAuras, b.c) end
		end
		if L.boss then
			for i = 1, 5 do TrackFull(bossT[i], false, true) end
			RefreshIcons()
		end
	elseif event == "SPELLS_CHANGED" then
		for _, s in ipairs(SPELLS) do wasKnown[s.key] = knownCache[s.key] end
		wipe(knownCache)
		local changed = false
		for _, s in ipairs(SPELLS) do
			if wasKnown[s.key] ~= nil and wasKnown[s.key] ~= Known(s.key) then changed = true end
		end
		if changed then
			Update()
			Watch()
		end
	elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
		if event == "PLAYER_ENTERING_WORLD" then
			encounter.id, encounter.name = nil, nil
			inCombat = InCombatLockdown() and true or false
		end
		ReadZone()
		if pending.look then Restyle() end   -- (a look changed while the game hid auras: now, if it shows them)
		if NS.dirty then NS.Restyle() end    -- (Next Shock's too: its own guard waits again if they still hide)
		Update()
		if nameRules then
			ReadTargetName()
			if EvaluateRules() then
				Layout()
				Apply()
			end
		end
	end
end)

-- ---------------------------------------------------------------------------
-- On / off
-- ---------------------------------------------------------------------------
local function HideAll()
	if H.debuffs then H.debuffs:Hide() end
	if H.purge then H.purge:Hide() end
	if H.ns then H.ns:Hide() end
	if H.plates then H.plates:Hide() end
	if E.bossLayer then E.bossLayer:Hide() end
	OnPlate.DetachAll()
end

local function SwitchedOnOff()
	if SV().enabled and not SP:IsOff() then
		inCombat = InCombatLockdown() and true or false   -- (turned on in a fight: Only In Combat shows at once)
		ReadZone()
		Update()
		-- last: a rule that names a target (a name the game hides never stops the rest)
		if HasNameRules() then
			pcall(ReadTargetName)
			if EvaluateRules() and built then
				Layout()
				Apply()
			end
		end
	else
		HideAll()
		-- (the containers off, the state driver let go, the events dropped, WoW's own icons back)
		if built then Apply() end
		SetListening()
	end
end


-- ---------------------------------------------------------------------------
-- The API (the settings window's Target Tracker page: ShamanPower_Config
-- TTIcons.lua and TTRules.lua, ShamanPowerOptions.lua, Window.lua)
-- ---------------------------------------------------------------------------
function SP:TT_Enabled() return SV().enabled == true end

function SP:TT_SetEnabled(on)
	on = on and true or false
	if SV().enabled == on then return end
	SV().enabled = on
	SwitchedOnOff()
	Watch()
	if stageOn and LayoutStage then LayoutStage() end
end

-- The two looks on General > Themes (Shapes & Textures): their choices, and a sample drawn
-- with the parts above, so a card shows exactly what the spell looks like
SP.TT_MISS_LOOKS = { { key = "edge", label = "Red Edge (default)" }, { key = "dotted", label = "Dotted Red Edge" },
	{ key = "faded", label = "Just Faded" }, { key = "glow", label = "Red Glow" }, { key = "tint", label = "Red Tint" },
	{ key = "slash", label = "Red Slash" }, { key = "outline", label = "Empty Outline" }, { key = "pulse", label = "Pulsing Edge" } }
SP.TT_ICON_EDGES = { { key = "thin", label = "Thin Black (default)" }, { key = "none", label = "None" },
	{ key = "thick", label = "Thick Black" }, { key = "dotted", label = "Dotted" }, { key = "spell", label = "Spell Color" } }
-- Next Shock's Look When It's Time to Cast: its choices (General > Themes cards; "cast" samples)
SP.TT_CAST_LOOKS = { { key = "gold", label = "Gold Dotted Edge (default)" }, { key = "edge", label = "Red Edge" },
	{ key = "dotted", label = "Dotted Red Edge" }, { key = "faded", label = "Just Faded" }, { key = "glow", label = "Red Glow" },
	{ key = "tint", label = "Red Tint" }, { key = "slash", label = "Red Slash" }, { key = "outline", label = "Empty Outline" },
	{ key = "pulse", label = "Pulsing Edge" } }
function SP:TT_LookSample(parent, kind, value)
	local host = CreateFrame("Frame", nil, parent)
	host:SetSize(30, 30)
	host:SetPoint("CENTER", parent, "CENTER", 0, 0)
	if kind == "cast" then
		-- Next Shock's Flame Shock when it's time to cast it again (state 4: in full color)
		NS.Look(NS.Parts(host, SPELL.fs.icon), value, false, 30)
		return host
	end
	local look = { size = 30, timeLeft = true, sweep = "none", charges = false, missLook = "edge", border = "thin" }
	if kind == "miss" then look.missLook = value else look.border = value end
	local p = DebuffParts(host, "fs", look)
	if kind == "miss" then MissingLook(p, true) else p.time:SetText("9") end
	return host
end

-- General > Themes > Reset Everything: every spell's visual choices back to their defaults
function SP:TT_ResetLooks()
	for _, s in ipairs(SPELLS) do
		if OPT[s.key].missLook ~= nil then SP:TT_Set(s.key, "missLook", nil) end
		if OPT[s.key].sweepDirection ~= nil then SP:TT_Set(s.key, "sweepDirection", nil) end
		SP:TT_Set(s.key, "border", nil)
	end
	SP:TT_Set("ns", "castLook", nil)   -- (Next Shock's Look When It's Time to Cast)
end

function SP:TT_Usable(key) return SPELL[key] ~= nil and Usable(key) end
function SP:TT_Known(key) return SPELL[key] ~= nil and Known(key) end

-- (key: a spell's, or "ns": Next Shock's settings, the Next Shock tab)
function SP:TT_Get(key, opt)
	if not (SPELL[key] or key == "ns") then return nil end
	return Get(key, opt)
end

function SP:TT_Set(key, opt, value)
	if not (SPELL[key] or key == "ns") then return end
	if opt == "shown" then
		local hidden = (value == false) or nil
		if SV().hidden[key] == hidden then return end
		SV().hidden[key] = hidden
		return Changed("layout")
	end
	if OPT[key][opt] == nil then return end
	local v
	if value ~= nil then
		v = Normalize(key, opt, value)
		if v == nil then return end
	end
	if SetOwn(key, opt, v) then
		if FILTER[opt] then Changed("filters")
		elseif LOOK[opt] then Changed("look")
		else Changed("layout") end
	end
end

function SP:TT_GetWhere(key, kind)
	if not SPELL[key] then return nil end
	return Get(key, "w_" .. tostring(kind))
end

function SP:TT_SetWhere(key, kind, on)
	self:TT_Set(key, "w_" .. tostring(kind), on and true or false)
end

function SP:TT_HasOwn(key)
	local own = SPELL[key] and Own(key)
	return own ~= nil and next(own) ~= nil
end

do   -- (in a block: this chunk's locals are counted)
	-- Copy and paste: every setting a spell has (not whether it is shown), as it is now
	local clipboard
	local function Snapshot(key)
		local t = { __from = key }   -- (the spell they came from: not a setting, never taken)
		for opt in pairs(OPT[key]) do t[opt] = Get(key, opt) end
		return t
	end
	-- the values on `key`, the ones it has; only: one group. A shock's size and Purge's are not
	-- alike (16-64 and 32-128): between the two, each keeps its own. Returns what kind of change
	-- it made ("filters" / "look" / "layout") or nil.
	local function Take(key, values, only)
		local kind
		local ownSize = (key == "purge") ~= (values.__from == "purge")
		for opt, v in pairs(values) do
			if (not only or only[opt]) and OPT[key][opt] ~= nil and not (ownSize and opt == "size") then
				local nv = Normalize(key, opt, v)
				if nv ~= nil and SetOwn(key, opt, nv) then
					if FILTER[opt] then kind = "filters"
					elseif LOOK[opt] and kind ~= "filters" then kind = "look"
					elseif not kind then kind = "layout" end
				end
			end
		end
		return kind
	end
	local RANK = { layout = 1, look = 2, filters = 3 }
	local function Worst(a, b)
		if not a then return b end
		if not b then return a end
		if RANK[a] >= RANK[b] then return a end
		return b
	end
	-- a look change also needs the layout, a filter change both: one Changed() for all of it
	local function Done(kind)
		if kind == "filters" then QueueFilters(); Changed("look")
		elseif kind then Changed(kind) end
	end

	function SP:TT_Copy(key)
		if not SPELL[key] then return end
		clipboard = { from = key, values = Snapshot(key) }
	end

	function SP:TT_Paste(key)
		if not (SPELL[key] and clipboard) then return end
		Done(Take(key, clipboard.values))
	end

	function SP:TT_ClipboardFrom() return clipboard and clipboard.from or nil end

	function SP:TT_CopyTo(fromKey, toKey)
		if not SPELL[fromKey] then return end
		local values = Snapshot(fromKey)
		local kind
		for _, s in ipairs(SPELLS) do
			if s.key ~= fromKey and (toKey == "all" or toKey == s.key) then kind = Worst(kind, Take(s.key, values)) end
		end
		Done(kind)
	end

	function SP:TT_CopyGroupToAll(key, group)
		local only = GROUPS[group]
		if not (SPELL[key] and only) then return end
		local values = Snapshot(key)
		local kind
		for _, s in ipairs(SPELLS) do
			if s.key ~= key then kind = Worst(kind, Take(s.key, values, only)) end
		end
		Done(kind)
	end

	function SP:TT_Reset(key)
		if not SPELL[key] then return end
		if SV().spells[key] == nil then return end
		SV().spells[key] = nil
		if key == "purge" then QueueFilters() end
		Changed("look")
	end

	-- the page: where your debuffs show, how they line up, the gap between them
	function SP:TT_GetPage(opt)
		if opt == "showOn" or opt == "arrange" or opt == "spacing" or opt == "plateSpot"
			or opt == "plateX" or opt == "plateY" or opt == "hideGame" then return SV()[opt] end
		return nil
	end

	function SP:TT_SetPage(opt, v)
		local sv = SV()
		if v == nil then v = DEFAULTS[opt] end
		if opt == "spacing" then
			v = tonumber(v)
			if not v or v ~= v then return end
			v = min(40, max(0, floor(v + 0.5)))
		elseif opt == "plateX" or opt == "plateY" then
			v = tonumber(v)
			if not v or v ~= v then return end
			if opt == "plateX" then v = min(80, max(-80, floor(v + 0.5))) else v = min(120, max(-60, floor(v + 0.5))) end
		elseif opt == "hideGame" then
			if type(v) ~= "boolean" then return end
		elseif not (PAGE[opt] and PAGE[opt][v]) then
			return
		end
		if sv[opt] == v then return end
		sv[opt] = v
		-- (where your debuffs show: their text is sized again for the row's scale)
		if opt == "showOn" then Changed("look") else Changed("layout") end
	end

	-- Move / Move Purge: Unlock UI with only that box (only the two spots are needed:
	-- nothing else is made, nothing starts listening)
	local moveOnly
	function SP:TT_Move(which)
		if which ~= "debuffs" and which ~= "purge" then return end
		if not self.UnlockModuleFrames then return end
		if InCombatLockdown() then
			self:Print("Target Tracker: the spots can be moved out of combat.")
			return
		end
		EnsureHolders()
		moveOnly = which
		self:UnlockModuleFrames(which == "purge" and "ttpurge" or "ttdebuffs")
	end

	function SP:TT_ResetPositions()
		local sv = SV()
		sv.debuffsPos, sv.purgePos = nil, nil
		if built then
			Layout()
			Apply()
		end
		self:Print("Target Tracker: your debuffs and Purge are back where they start.")
	end

	-- Rules
	function SP:TT_Rules() return SV().rules end

	function SP:TT_AddRule()
		local rules = SV().rules
		-- a place to start from: where you are now if it is a raid or dungeon this game knows, else any raid
		local place = "anyraid"
		if zone.map and Places().name[zone.map] then place = "map:" .. zone.map end
		rules[#rules + 1] = { place = place, who = "anyboss", part = "purge:on" }
		Changed("rules")
		return #rules
	end

	local function InList(list, key)
		for _, it in ipairs(list) do
			if it.key == key then return true end
		end
		return false
	end

	function SP:TT_SetRule(i, field, value)
		local rule = SV().rules[i]
		if not rule then return end
		if field == "place" then
			if type(value) ~= "string" or not (MapOf(value) or InList(GENERIC_PLACES, value)) then return end
			rule.place = value
			-- who you fight has to be there: a boss of another place becomes Any Boss (or the place's first choice)
			local who = WhoList(value)
			if not InList(who, rule.who) then
				if InList(who, "anyboss") then rule.who = "anyboss" else rule.who = who[1].key end
			end
		elseif field == "who" then
			if type(value) ~= "string" then return end
			if not (value == "anyboss" or value == "anyone" or value == "name" or value:match("^enc:%d+$")) then return end
			rule.who = value
		elseif field == "name" then
			if value == nil then
				rule.name = nil
			else
				value = strtrim(tostring(value))
				if #value > 60 then value = value:sub(1, 60) end
				rule.name = (value ~= "") and value or nil
			end
		elseif field == "part" then
			if not PART[value] then return end
			rule.part = value
		else
			return
		end
		Changed("rules")
	end

	function SP:TT_RemoveRule(i)
		local rules = SV().rules
		if not rules[i] then return end
		table.remove(rules, i)
		Changed("rules")
	end

	function SP:TT_RulePlaces() return Places().list end
	function SP:TT_RuleWho(place) return WhoList(place) end
	function SP:TT_RuleParts() return PARTS end

	function SP:TT_RuleText(rule)
		if type(rule) ~= "table" then return "", "", "" end
		local part = PART[rule.part]
		return PlaceText(rule.place), WhoText(rule), part and part[3] or "Purge Reminder On"
	end

	function SP:TT_Watch(fn)
		if type(fn) == "function" then watchers[#watchers + 1] = fn end
	end

	-- A profile came in (an import replaced the saved table): everything again
	function SP:TargetTrackerRefresh()
		filledFor = nil
		SV()
		SwitchedOnOff()
		if built then
			Restyle()
			QueueFilters()
		end
		RunWatchers()
	end

	-- -------------------------------------------------------------------------
	-- Unlock UI: the two spots as boxes, with stand-ins in them to grab (only the
	-- two spots and the stand-ins are made for it)
	-- -------------------------------------------------------------------------
	local function SaveSpot(which, frame)
		local rec = SP.GetPositionRecord and SP:GetPositionRecord(frame)
		if not rec then return end
		if which == "debuffs" then SV().debuffsPos = rec elseif which == "ns" then SV().nsPos = rec else SV().purgePos = rec end
		SP:ApplyPositionRecord(frame, rec)
	end

	local standinKeys = {}
	local function StandinFrame(key) return standins.debuffs[key].host end

	function SP:TargetTrackerDebuffsDemo(on)
		EnsureHolders()
		if on then
			demo.debuffs = true
			wipe(standinKeys)
			local samples = { fs = "12", frs = "4", ss = "7" }
			for _, key in ipairs(DEBUFFS) do
				local s = standins.debuffs[key]
				if Get(key, "shown") and Usable(key) then
					local look = DebuffLook(key)
					if not s then
						local host = CreateFrame("Frame", nil, H.debuffs)
						s = DebuffParts(host, key, look)
						s.host = host
						standins.debuffs[key] = s
					else
						StyleDebuff(s, look)
					end
					s.time:SetText(samples[key])
					s.count:SetText(key == "ss" and "2" or "")
					s.host:Show()
					standinKeys[#standinKeys + 1] = key
				elseif s then
					s.host:Hide()
				end
			end
			local w, h = LayoutRow(H.debuffs, standinKeys, StandinFrame)
			H.debuffs:SetSize(w, h)
			if built then Apply() end
			PlaceDebuffs()
			H.debuffs:Show()
		else
			demo.debuffs = nil
			if moveOnly == "debuffs" then moveOnly = nil end
			for _, s in pairs(standins.debuffs) do s.host:Hide() end
			if built then
				Layout()
				Apply()
			else
				H.debuffs:Hide()
			end
		end
	end

	function SP:TargetTrackerPurgeDemo(on)
		EnsureHolders()
		if on then
			demo.purge = true
			local look = { size = Get("purge", "size"), glow = true, picture = true, word = true }
			local s = standins.purge
			if not s then
				local host = CreateFrame("Frame", nil, H.purge)
				host:SetAllPoints(H.purge)
				s = PurgeParts(host, look)
				s.pic:SetTexture(DEMON_ARMOR)
				standins.purge = s
			else
				StylePurge(s, look)
			end
			if built then Apply() end
			PlacePurge()
			s.host:Show()
			H.purge:Show()
		else
			demo.purge = nil
			if moveOnly == "purge" then moveOnly = nil end
			if standins.purge then standins.purge.host:Hide() end
			if built then
				Layout()
				Apply()
			else
				H.purge:Hide()
			end
		end
	end

	if SP.RegisterPreview then
		-- Unlock UI only (the settings preview never borrows these)
		SP:RegisterPreview("ttdebuffs", { frame = function() EnsureHolders() return H.debuffs end, demo = "SP:TargetTrackerDebuffsDemo" })
		SP:RegisterPreview("ttpurge", { frame = function() EnsureHolders() return H.purge end, demo = "SP:TargetTrackerPurgeDemo" })
	end
	if SP.UnlockModules then
		table.insert(SP.UnlockModules, {
			key = "ttdebuffs", label = "Target Tracker",
			enabled = function()
				if moveOnly == "debuffs" then return true end
				if not (SV().enabled and SV().showOn == "spot") then return false end
				for _, key in ipairs(DEBUFFS) do
					if Get(key, "shown") and Usable(key) then return true end
				end
				return false
			end,
			save = function(frame) SaveSpot("debuffs", frame) end,
			reset = function()
				SV().debuffsPos = nil
				PlaceDebuffs()
			end,
		})
		table.insert(SP.UnlockModules, {
			key = "ttpurge", label = "Target Tracker: Purge",
			enabled = function()
				if moveOnly == "purge" then return true end
				return SV().enabled and Get("purge", "shown") and Get("purge", "showOn") == "screen" and Usable("purge") or false
			end,
			save = function(frame) SaveSpot("purge", frame) end,
			reset = function()
				SV().purgePos = nil
				PlacePurge()
			end,
		})
	end
end   -- (the API's block)

-- ---------------------------------------------------------------------------
-- The settings preview (the Target Tracker page's live preview, "targettracker"):
-- on the pane's own background, a pretend enemy target in WoW's own target frame
-- art and the module's parts in their real look, acting out a short fight: your
-- shocks counting down, Stormstrike's charges going, a shock falling off (its
-- Missing look only when that spell's Missing Warning is on), Purge lit while the
-- target has a Magic buff and out when it is purged; with Every Nameplate, another
-- enemy's nameplate with its own row (a shock whose Missing Warning is on is not on
-- it and shows its Missing look; with no warning on, all of them are on it) and its
-- Purge. Rows on a nameplate sit at the page's Nameplate Spot with its nudges, as in
-- play; a plate and its parts always fit on the stage. It follows the settings as
-- they change (the same parts, restyled). Its ticker runs only while the preview
-- is open.
-- ---------------------------------------------------------------------------
do   -- (in a block: this chunk's locals are counted; the preview's own things live in P)
	local P = { W = 330, CYCLE = 12 }   -- W: the stage's width; CYCLE: seconds, the story over and over

	-- a pretend nameplate: its name over a red health bar in WoW's nameplate border, its level at the
	-- right (in the plate: the name 0-10 from its top, the bar 15-21, the level's middle 18)
	function P.Plate(parent, name, hp, dim)
		local f = CreateFrame("Frame", nil, parent)
		f:SetSize(112, 24)
		local a = dim and 0.55 or 1
		f.name = f:CreateFontString(nil, "OVERLAY")
		f.name:SetFontObject(GameFontHighlightSmall)
		f.name:SetPoint("TOP", f, "TOP", 0, 0)
		f.name:SetText(name)
		f.name:SetAlpha(a)
		local bar = f:CreateTexture(nil, "ARTWORK")
		bar:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -15)
		bar:SetSize(88 * hp, 6)
		bar:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
		bar:SetVertexColor(0.85, 0.1, 0.1, a)
		local back = f:CreateTexture(nil, "BACKGROUND")
		back:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -15)
		back:SetSize(88, 6)
		back:SetColorTexture(0, 0, 0, 0.6 * a)
		f.bar = back   -- (the whole bar: what a row lines up with)
		local border = f:CreateTexture(nil, "OVERLAY")
		border:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -12)
		border:SetSize(112, 12)
		border:SetTexture("Interface\\Tooltips\\Nameplate-Border")
		border:SetTexCoord(2 / 256, 134 / 256, 16 / 32, 31 / 32)
		border:SetAlpha(a)
		f.level = f:CreateFontString(nil, "OVERLAY")
		f.level:SetFontObject(GameFontNormalSmall)
		f.level:SetPoint("CENTER", f, "TOPLEFT", 100, -18)
		f.level:SetText("60")
		f.level:SetAlpha(a)
		return f
	end

	-- a row on a pretend nameplate at the page's Nameplate Spot and nudges, as in play (the nudges scale
	-- with the row); returns its top and bottom (downward from the plate's top) and its left and right
	-- (from the plate's left: the plate is 112 wide, its name centered, its bar 2-90, its level's middle 100)
	function P.PlaceRow(block, plate, w, h, sv)
		local sc = K.PLATE_SCALE
		local ox, oy = (sv.plateX or 0) * sc, (sv.plateY or 0) * sc
		local spot = sv.plateSpot
		block:ClearAllPoints()
		-- (left and right with the icons' 1 px black edge)
		if spot == "below" then
			block:SetPoint("TOP", plate.bar, "BOTTOM", ox, -2 * sc + oy)
			local top = 21 + 2 * sc - oy
			return top, top + h, 46 + ox - w / 2 - 1, 46 + ox + w / 2 + 1
		elseif spot == "left" then
			block:SetPoint("RIGHT", plate.bar, "LEFT", -4 * sc + ox, oy)
			local right = 2 - 4 * sc + ox
			return 18 - oy - h / 2, 18 - oy + h / 2, right - w - 1, right + 1
		elseif spot == "right" then
			block:SetPoint("LEFT", plate.level, "RIGHT", 6 * sc + ox, oy)
			local left = P.LevelRight(plate) + 6 * sc + ox
			return 18 - oy - h / 2, 18 - oy + h / 2, left - 1, left + w + 1
		end
		block:SetPoint("BOTTOM", plate.name, "TOP", ox, 3 * sc + oy)
		local bottom = -(3 * sc + oy)
		return bottom - h, bottom, 56 + ox - w / 2 - 1, 56 + ox + w / 2 + 1
	end

	-- the right edge of a pretend nameplate's level, from the plate's left
	function P.LevelRight(plate) return 100 + (plate.level:GetStringWidth() or 0) / 2 end

	-- Purge on a pretend nameplate: right of its level (or of the row when the row sits there); returns
	-- its top and bottom (downward from the plate's top) and its left and right (from the plate's left),
	-- with its glow around it and the buff's picture beside it as StylePurge draws them
	function P.PlacePurge(host, plate, row, rowMid, rowRight, size)
		local ps = K.PURGE_PLATE_SCALE
		host:SetScale(ps)
		host:ClearAllPoints()
		local left
		if row then
			host:SetPoint("LEFT", row, "RIGHT", 6, 0)
			left = rowRight + 6 * ps
		else
			host:SetPoint("LEFT", plate.level, "RIGHT", 6, 0)
			left = P.LevelRight(plate) + 6 * ps
		end
		local mid = row and rowMid or 18
		local half = size * ps / 2
		local glow = Get("purge", "glow") and floor(size * 0.2 + 0.5) or 0
		local right = glow
		if Get("purge", "buffPicture") then right = max(right, 6 + max(12, floor(size * 0.42 + 0.5)) + 1) end
		return mid - half, mid + half, left - glow * ps, left + (size + right) * ps
	end

	-- a pretend nameplate on the stage with its row and Purge: the three centered together, never past the
	-- stage's edges (the stage is made wide enough for them)
	function P.PutPlate(plate, s, W, top, left, right)
		local x = max(4 - left, min(W - 4 - right, W / 2 - (left + right) / 2))
		plate:ClearAllPoints()
		plate:SetPoint("TOPLEFT", s, "TOPLEFT", x, -top)
		plate:Show()
	end

	-- the pretend target: WoW's own (Classic) target frame art, its name and level (in `parent`)
	function P.TargetArt(parent)
		local tf = CreateFrame("Frame", nil, parent)
		tf:SetSize(256, 128)
		local function tex(layer, sub, x, y, w, h, file)
			local t = tf:CreateTexture(nil, layer, nil, sub)
			t:SetPoint("TOPLEFT", tf, "TOPLEFT", x, -y)
			t:SetSize(w, h)
			if file then t:SetTexture(file) end
			return t
		end
		tex("BACKGROUND", 0, 28, 23, 128, 18, "Interface\\TargetingFrame\\UI-TargetingFrame-LevelBackground"):SetVertexColor(1, 0, 0)
		tex("BACKGROUND", 0, 28, 41, 128, 11):SetColorTexture(0, 0, 0, 0.55)
		tex("BACKGROUND", 0, 28, 53, 128, 11):SetColorTexture(0, 0, 0, 0.55)
		tex("ARTWORK", 0, 28, 41, 128 * 0.62, 11, "Interface\\TargetingFrame\\UI-StatusBar"):SetVertexColor(0, 1, 0)
		tex("ARTWORK", 0, 28, 53, 128 * 0.8, 11, "Interface\\TargetingFrame\\UI-StatusBar"):SetVertexColor(0, 0, 1)
		local portrait = tex("ARTWORK", 1, 160, 14, 61, 61, "Interface\\CharacterFrame\\TemporaryPortrait-Monster")
		if tf.CreateMaskTexture then
			local ok, mask = pcall(tf.CreateMaskTexture, tf)
			if ok and mask then
				mask:SetAllPoints(portrait)
				mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
				pcall(portrait.AddMaskTexture, portrait, mask)
			end
		end
		tex("OVERLAY", -1, 0, 0, 256, 128, "Interface\\TargetingFrame\\UI-TargetingFrame")
		local name = tf:CreateFontString(nil, "OVERLAY")
		name:SetFontObject(GameFontNormalSmall)
		name:SetPoint("CENTER", tf, "TOPLEFT", 92, -32)
		name:SetText("Blackrock Warlock")
		local level = tf:CreateFontString(nil, "OVERLAY")
		level:SetFontObject(GameFontNormalSmall)
		level:SetPoint("CENTER", tf, "TOPLEFT", 208, -67)
		level:SetText("60")
		return tf
	end

	function P.Stage()
		if P.stage then return P.stage end
		local s = CreateFrame("Frame", "ShamanPowerTargetTrackerDemo", UIParent)
		s:SetSize(P.W, 320)
		s:Hide()
		local tf = P.TargetArt(s)
		-- its Magic buff, in WoW's own small aura row under the frame (a Magic buff's blue edge)
		local buff = CreateFrame("Frame", nil, tf)
		buff:SetSize(18, 18)
		buff:SetPoint("TOPLEFT", tf, "TOPLEFT", 30, -84)
		local bedge = buff:CreateTexture(nil, "BACKGROUND")
		bedge:SetPoint("TOPLEFT", buff, "TOPLEFT", -1, 1)
		bedge:SetPoint("BOTTOMRIGHT", buff, "BOTTOMRIGHT", 1, -1)
		bedge:SetColorTexture(MAGIC[1], MAGIC[2], MAGIC[3], 1)
		local bicon = buff:CreateTexture(nil, "ARTWORK")
		bicon:SetAllPoints(buff)
		bicon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		bicon:SetTexture(DEMON_ARMOR)
		s.tf, s.buff = tf, buff
		-- your debuffs (the real look: the same parts the game's buttons get), and another enemy's row
		s.block = CreateFrame("Frame", nil, s)
		s.gblock = CreateFrame("Frame", nil, s)
		s.icons, s.gicons = {}, {}
		for _, key in ipairs(DEBUFFS) do
			for _, set in ipairs({ { s.icons, s.block }, { s.gicons, s.gblock } }) do
				local host = CreateFrame("Frame", nil, set[2])
				host:SetSize(36, 36)
				host:Hide()
				local p = DebuffParts(host, key, DebuffLook(key, 36))
				p.host = host
				set[1][key] = p
			end
		end
		-- Every Nameplate: another enemy's plate
		s.grunt = P.Plate(s, "Blackrock Grunt", 0.9, true)
		-- your target's nameplate (where your debuffs or Purge show on it)
		s.plate = P.Plate(s, "Blackrock Warlock", 0.62, false)
		-- Purge, and the other enemy's Purge (their looks change in place)
		local ph = CreateFrame("Frame", nil, s)
		ph:SetSize(64, 64)
		ph:Hide()
		s.purge = PurgeParts(ph, PurgeLook())
		s.purge.pic:SetTexture(DEMON_ARMOR)
		local gph = CreateFrame("Frame", nil, s)
		gph:SetSize(64, 64)
		gph:Hide()
		s.gpurge = PurgeParts(gph, PurgeLook(nil, true))
		s.gpurge.pic:SetTexture(DEMON_ARMOR)
		-- the caption, as dim as the pane's other small print
		s.caption = s:CreateFontString(nil, "OVERLAY")
		s.caption:SetFontObject(_G.ShamanPowerDialogFontTiny or GameFontDisableSmall)
		s.caption:SetWidth(P.W - 16)
		s.caption:SetJustifyH("CENTER")
		s.caption:SetWordWrap(true)
		s.caption:SetText("Your debuffs on your target, and Purge for its Magic buffs.")
		s.list, s.glist = {}, {}
		P.stage = s
		return s
	end

	function P.Icon(key) return P.stage.icons[key].host end
	function P.GIcon(key) return P.stage.gicons[key].host end

	LayoutStage = function()
		local s = P.stage
		if not s then return end
		local sv = SV()
		local where, pWhere = sv.showOn, Get("purge", "showOn")
		local sc = K.PLATE_SCALE
		-- the debuffs that show (shown, and on this game version)
		local list = s.list
		wipe(list)
		for _, key in ipairs(DEBUFFS) do
			s.icons[key].host:Hide()
			if Get(key, "shown") and Usable(key) then list[#list + 1] = key end
		end
		local scale = 1
		if where == "plate" then scale = sc end
		-- the block, laid out as in play (its own spot on the stage)
		local bw, bh = LayoutRow(s.block, list, P.Icon, scale)
		s.block:SetSize(bw, bh)
		s.block:ClearAllPoints()
		for _, key in ipairs(list) do
			StyleDebuff(s.icons[key], DebuffLook(key, Get(key, "size") * scale))
			s.icons[key].demoStart = nil
		end
		local purgeShown = Get("purge", "shown") and Usable("purge")
		local pp = s.purge
		local plook = PurgeLook()
		StylePurge(pp, plook)
		pp.host:SetSize(plook.size, plook.size)
		pp.host:Hide()
		local psize = plook.size
		local wordH = 0
		if plook.word then wordH = WordSize(psize) + 6 end
		-- Every Nameplate: another enemy's row. One of your shocks is not on it: one whose Missing Warning is
		-- on (Flame Shock first), so its warning shows; with no warning on, every one of them is on it (never
		-- an empty row)
		s.grunt:Hide()
		local glist = s.glist
		wipe(glist)
		s.missKey = nil
		for _, key in ipairs(DEBUFFS) do
			s.gicons[key].host:Hide()
			if Get(key, "shown") and Get(key, "everyPlate") and Usable(key) then
				glist[#glist + 1] = key
				if Get(key, "missing") and (s.missKey == nil or key == "fs") then s.missKey = key end
			end
		end
		s.gpurgeOn = purgeShown and Get("purge", "everyPlate") or false
		s.gpurge.host:Hide()
		local gw, gh = LayoutRow(s.gblock, glist, P.GIcon, sc)
		s.gblock:SetSize(gw, gh)
		for _, key in ipairs(glist) do
			StyleDebuff(s.gicons[key], DebuffLook(key, Get(key, "size") * sc))
			s.gicons[key].demoStart = nil
		end
		-- the two pretend nameplates' rows and Purges go on their plates first (each plate with its parts: top,
		-- bottom, left, right), so the stage is made wide enough for the wider one (the pane fits the stage)
		local onPlate = where == "plate" and #list > 0
		local purgeOnPlate = purgeShown and pWhere == "plate"
		local pt, pb, pl, pr   -- your target's plate
		if onPlate or purgeOnPlate then
			pt, pb, pl, pr = 0, 24, 0, 112
			local mid, rowRight = 18, 0
			if onPlate then
				local t, b, l, r = P.PlaceRow(s.block, s.plate, bw, bh, sv)
				pt, pb, pl, pr, mid, rowRight = min(pt, t), max(pb, b), min(pl, l), max(pr, r), (t + b) / 2, r
			end
			if purgeOnPlate then
				local row = nil
				if onPlate and sv.plateSpot == "right" then row = s.block end
				local t, b, l, r = P.PlacePurge(pp.host, s.plate, row, mid, rowRight, psize)
				pt, pb, pl, pr = min(pt, t), max(pb, b), min(pl, l), max(pr, r)
			end
		end
		local gt, gb, gl, gr   -- the other enemy's plate
		if #glist > 0 or s.gpurgeOn then
			gt, gb, gl, gr = 0, 24, 0, 112
			local mid, rowRight = 18, 0
			if #glist > 0 then
				local t, b, l, r = P.PlaceRow(s.gblock, s.grunt, gw, gh, sv)
				gt, gb, gl, gr, mid, rowRight = min(gt, t), max(gb, b), min(gl, l), max(gr, r), (t + b) / 2, r
			end
			if s.gpurgeOn then
				StylePurge(s.gpurge, PurgeLook(psize, true))
				s.gpurge.host:SetSize(psize, psize)
				local row = nil
				if #glist > 0 and sv.plateSpot == "right" then row = s.gblock end
				local t, b, l, r = P.PlacePurge(s.gpurge.host, s.grunt, row, mid, rowRight, psize)
				gt, gb, gl, gr = min(gt, t), max(gb, b), min(gl, l), max(gr, r)
			end
		end
		local W = P.W
		if pl then W = max(W, ceil(pr - pl) + 8) end
		if gl then W = max(W, ceil(gr - gl) + 8) end
		-- the target frame, its left edge where a real one's would be
		local tfx = floor((W - 232) / 2) - 24
		s.tf:ClearAllPoints()
		s.tf:SetPoint("TOPLEFT", s, "TOPLEFT", tfx, -4)
		local cursor = 4 + 104
		-- under the target frame (as in play: Purge goes under your debuffs there)
		if where == "frame" and #list > 0 then
			s.block:SetPoint("TOPLEFT", s, "TOPLEFT", tfx + 24 + K.FRAME_X, -(4 + 100 - K.FRAME_Y))
			cursor = 4 + 100 - K.FRAME_Y + bh
		end
		if purgeShown and pWhere == "frame" then
			local y = 4 + 100 - K.FRAME_Y
			if where == "frame" and #list > 0 then y = cursor + 10 end
			pp.host:SetScale(1)
			pp.host:ClearAllPoints()
			pp.host:SetPoint("TOPLEFT", s, "TOPLEFT", tfx + 24 + K.FRAME_X, -y)
			cursor = max(cursor, y + psize + wordH)
		end
		-- your target's nameplate: your debuffs at the page's Nameplate Spot, Purge right of the bar
		s.plate:Hide()
		if pl then
			local plateTop = cursor + 16 - pt
			P.PutPlate(s.plate, s, W, plateTop, pl, pr)
			cursor = plateTop + pb
		end
		-- the spots you place
		if where == "spot" and #list > 0 then
			s.block:SetPoint("TOPLEFT", s, "TOPLEFT", (W - bw) / 2, -(cursor + 20))
			cursor = cursor + 20 + bh
		end
		if purgeShown and pWhere == "screen" then
			local y = cursor + 22
			pp.host:SetScale(1)
			pp.host:ClearAllPoints()
			pp.host:SetPoint("TOPLEFT", s, "TOPLEFT", (W - psize) / 2, -y)
			cursor = y + psize + wordH
		end
		-- Every Nameplate: the other enemy's plate with its own row at the same spot, and its Purge
		if gl then
			local plateTop = cursor + 22 - gt
			P.PutPlate(s.grunt, s, W, plateTop, gl, gr)
			cursor = plateTop + gb
		end
		s.caption:ClearAllPoints()
		s.caption:SetPoint("TOP", s, "TOPLEFT", W / 2, -(cursor + 18))
		s:SetSize(W, cursor + 18 + max(12, s.caption:GetStringHeight()) + 8)
		s.purgeShown = purgeShown
	end

	-- one of the stand-ins: on the target since `start` for `duration`, or not (the Missing look, or gone)
	function P.Aura(p, on, start, duration, count, missing)
		if not on then
			if missing then
				if not p.missing then MissingLook(p, true) end
				p.demoStart = nil
				p.host:Show()
			else
				p.host:Hide()
			end
			return
		end
		if p.missing then
			MissingLook(p, false)
			p.demoStart = nil
		end
		if p.demoStart ~= start then
			p.demoStart = start
			p.cd:SetCooldown(start, duration)
			SweepBarStart(p, start, duration)
			p.demoLeft = nil
		end
		local left = ceil(start + duration - GetTime())
		if p.demoLeft ~= left then
			p.demoLeft = left
			p.time:SetText(tostring(max(left, 1)))
		end
		if count then p.count:SetText(tostring(count)) else p.count:SetText("") end
		p.host:Show()
	end

	function P.Tick()
		local s = P.stage
		if not (s and stageOn) then return end
		local now = GetTime()
		local t = (now - s.t0) % P.CYCLE
		local c0 = now - t   -- this round's start
		for _, key in ipairs(s.list) do
			local p = s.icons[key]
			local on
			if key == "fs" then
				-- on for 9 s of 12 (cast 3 s before the round), then gone: its Missing look only with its warning on
				on = t < 9
				P.Aura(p, on, c0 - 3, 12, nil, not on and Get("fs", "missing"))
			elseif key == "frs" then
				on = t >= 1 and t < 9
				P.Aura(p, on, c0 + 1, 8, nil, not on and Get("frs", "missing"))
			else
				on = t >= 2
				P.Aura(p, on, c0 + 2, 12, (t < 6) and 2 or 1, not on and Get("ss", "missing"))
			end
		end
		if s.grunt:IsShown() then
			for _, key in ipairs(s.glist) do
				if key == s.missKey then
					-- not on this enemy: its Missing look when that spell's warning is on, else nothing
					P.Aura(s.gicons[key], false, 0, 0, nil, Get(key, "missing"))
				else
					P.Aura(s.gicons[key], true, c0, 12, (key == "ss") and 2 or nil)
				end
			end
		end
		-- the target's Magic buff: on, purged at 5 s, back at 8 s (the other enemy keeps its own)
		local buffed = t < 5 or t >= 8
		s.buff:SetShown(buffed)
		s.purge.host:SetShown(s.purgeShown and buffed or false)
		s.gpurge.host:SetShown(s.gpurgeOn and s.grunt:IsShown() or false)
	end

	function SP:TargetTrackerDemo(on)
		if on then
			P.Stage()
			stageOn = true
			LayoutStage()
			if not P.ticker then
				P.stage.t0 = GetTime()
				P.ticker = C_Timer.NewTicker(0.1, P.Tick)
			end
			P.Tick()
		else
			stageOn = false
			if P.ticker then
				P.ticker:Cancel()
				P.ticker = nil
			end
			if P.stage then P.stage:Hide() end
		end
	end

	if SP.RegisterPreview then
		SP:RegisterPreview("targettracker", { frame = function() return P.Stage() end, demo = "SP:TargetTrackerDemo",
			pad = 16, pane = { maxScale = 1.5 } })
	end
end

-- ---------------------------------------------------------------------------
-- /sptt: what the module is doing (for testing in game)
-- ---------------------------------------------------------------------------
do
	local function Report()
		local p = function(...) SP:Print(...) end
		local function onoff(v) return v and "on" or "off" end
		p(("Target Tracker: on=%s built=%s game draws=%s in a fight=%s place=%s map=%s boss fight=%s"):format(
			tostring(SV().enabled), tostring(built), tostring(engine), tostring(inCombat), zone.kind, tostring(zone.map),
			tostring(encounter.id)))
		local parts, miss, plates = {}, {}, {}
		for _, s in ipairs(SPELLS) do
			local key = s.key
			if key == "purge" then
				parts[#parts + 1] = "Purge " .. onoff(ModuleOn() and PurgeWanted())
			else
				local c = cells[key]
				parts[#parts + 1] = s.name .. " " .. (c and onoff(c.frame:IsShown()) or "not known")
				miss[#miss + 1] = s.name .. " " .. onoff(MissingOn(key))
			end
			plates[#plates + 1] = s.name .. " " .. onoff(PlatesOn(key))
		end
		p("  on here and now (they show on an enemy you target): " .. table.concat(parts, ", "))
		p("  missing warnings: " .. table.concat(miss, ", ") .. "; every nameplate: " .. table.concat(plates, ", "))
		if E.tc then
			local s = {}
			for _, key in ipairs({ "fs", "frs", "ss", "purge" }) do s[#s + 1] = key .. "=" .. tostring(E.slotOn[key]) end
			p(("  the game draws: target container slots %s (bound=%s); state driver %s; boss containers %d; plate containers %d"):format(
				table.concat(s, " "), tostring(E.bound), E.driver and "on" or "off", #E.boss, #E.plateAll))
		end
		local o = {}
		for k, v in pairs(overrides) do o[#o + 1] = k .. "=" .. (v and "on" or "off") end
		p("  rules now: " .. (#o > 0 and table.concat(o, " ") or "none apply") .. " (" .. #SV().rules .. " rules)")
		local n, w, hid = 0, 0, 0
		for _ in pairs(plateUsed) do n = n + 1 end
		for _ in pairs(OnPlate.waiting) do w = w + 1 end
		for _ in pairs(OnPlate.hidden) do hid = hid + 1 end
		p(("  listening: target auras=%s nameplates=%s bosses=%s; nameplates with a row=%d free=%d waiting=%d"):format(
			tostring(L.aura), tostring(L.plates), tostring(L.boss), n, #platePool, w))
		-- Hide WoW's Own Icons: whether the game lets WoW's own nameplate icons be told apart right now
		-- (in a fight on WoW: Forever it may hide which spell an icon is)
		local apart = {}
		local S = C_Secrets
		for _, key in ipairs(DEBUFFS) do
			local hiddenNow = false
			if S and S.ShouldSpellAuraBeSecret then
				for _, id in ipairs(SPELL[key].auraIDs) do
					local ok, v = pcall(S.ShouldSpellAuraBeSecret, id)
					if ok and (secret(v) or v == true) then hiddenNow = true end
				end
			end
			apart[#apart + 1] = SPELL[key].name .. (hiddenNow and " no (hidden by the game)" or " yes")
		end
		local red = 0
		for _ in pairs(OnPlate.servedBy) do red = red + 1 end
		local redrawn = "no (not on this game version)"
		if engine then
			if E.grp then redrawn = red .. " nameplates"
			elseif OnPlate.groupsBuilt then redrawn = "no (the game refused it)"
			else redrawn = "not set up (it is, out of combat, once Hide WoW's Own Icons and WoW's Personal Debuffs are on)" end
		end
		p(("  hide WoW's own icons: %s; WoW's row redrawn by the game without your tracked spells: %s; icons hidden one by one now: %d;"
			.. " WoW's own icons can be told apart right now: %s; another addon's nameplates: %s"):format(
			onoff(OnPlate.hiding), redrawn, hid, table.concat(apart, ", "), OnPlate.addonPlates and "yes" or "no"))
		-- Next Shock: who draws it, your Flame Shock on your target as known now, its last seconds' timer
		local nsStart, nsDur = nil, nil
		if NS.built and ((NS.engine and NS.tWant) or (not NS.engine and NS.wanted)) then nsStart, nsDur = NS.Rec() end
		-- icons of ours (Anniversary), your target's own containers and every nameplate's (WoW: Forever)
		local icons, late, timers = #NS.parts, 0, 0
		for _, q in ipairs(NS.parts) do
			if q.nsLate then late = late + 1 end
			if q.nsT then timers = timers + 1 end
		end
		if NS.c then icons = icons + 1 end
		if NS.lateOn and NS.lc then late = late + 1 end
		if NS.timer then timers = timers + 1 end
		for _, e in ipairs(E.plateAll) do
			if e.nc then icons = icons + 1 end
			local q = e.nsP
			if q and q.nsLate then late = late + 1 end
			if q and q.nsT then timers = timers + 1 end
		end
		p(("  next shock: %s; on %d Flame Shock icons (your target's: %s, its last seconds: %s); your Flame Shock on your"
			.. " target: %s; last %d seconds showing on %d, timers set %d; your target's GUID shown by the game: %s"):format(
			onoff(NS.On()), icons, NS.c and "the game's" or (#NS.parts > 0 and "ours" or "none"),
			NS.lc and "the game's" or (NS.lc == false and "refused" or (#NS.parts > 0 and "ours" or "none")),
			nsStart and ("%.1f s left (from %s)"):format(nsStart + nsDur - GetTime(), NS.from or "your cast") or "not on (or not known)",
			Get("ns", "refresh"), late, timers, NS.Guid() and "yes" or "no"))
		local nsBuilt, nsUsed, nsOn, nsRec, nsBound = 0, 0, 0, 0, 0
		for _, e in ipairs(E.plateAll) do if e.nc then nsBuilt = nsBuilt + 1 end end
		for unit, e in pairs(plateUsed) do
			nsUsed = nsUsed + 1
			if e.nsOn then nsOn = nsOn + 1 end
			if e.nc and e.nc.GetUnit then
				local okU, u = pcall(e.nc.GetUnit, e.nc)
				if okU and not secret(u) and u == unit then nsBound = nsBound + 1 end
			end
			if NS.RecOf(unit) then nsRec = nsRec + 1 end
		end
		local nsLateBuilt = 0
		for _, e in ipairs(E.plateAll) do if e.lc then nsLateBuilt = nsLateBuilt + 1 end end
		p(("  next shock on nameplates: its slot on %d of %d entries (last seconds on %d); %d nameplates now, %d of them on,"
			.. " %d bound to their enemy, %d with your Flame Shock cast on record"):format(nsBuilt, #E.plateAll, nsLateBuilt,
			nsUsed, nsOn, nsBound, nsRec))
		p("  built: " .. (#E.log > 0 and table.concat(E.log, "; ") or "nothing yet"))
	end

	SLASH_SPTARGETTRACKER1 = "/sptt"
	SlashCmdList.SPTARGETTRACKER = function() Report() end
end

-- ---------------------------------------------------------------------------
-- Start
-- ---------------------------------------------------------------------------
SP:OnOnOff(function() SwitchedOnOff() end)

do
	local boot = CreateFrame("Frame")
	boot:RegisterEvent("PLAYER_LOGIN")
	boot:SetScript("OnEvent", function(self)
		self:UnregisterEvent("PLAYER_LOGIN")
		SV()
		-- General > Themes: each spell's looks, so presets, Your Themes and share codes carry them
		if SP.ThemeSpotSettings then
			local entries = {}
			for _, s in ipairs(SPELLS) do
				local key = s.key
				if key ~= "purge" then
					entries[#entries + 1] = { key = "sweepDirection." .. key, label = (s.name or key) .. " Sweep Direction",
						-- A theme-only sentinel preserves the unset, style-dependent default as a text value.
						get = function() local own = Own(key); return own and own.sweepDirection or "default" end,
						set = function(v)
							if v == "default" then v = nil end
							SP:TT_Set(key, "sweepDirection", v)
						end }
					entries[#entries + 1] = { key = "missLook." .. key, label = (s.name or key) .. " Look When Missing",
						get = function() return Get(key, "missLook") end,
						set = function(v) SP:TT_Set(key, "missLook", v) end }
				end
				entries[#entries + 1] = { key = "border." .. key, label = (s.name or key) .. " Icon Edge",
					get = function() return Get(key, "border") end,
					set = function(v) SP:TT_Set(key, "border", v) end }
			end
			-- Next Shock's Look When It's Time to Cast (its Size is not a look: as each spell's Icon Size)
			entries[#entries + 1] = { key = "castLook.ns", label = "Next Shock Look When It's Time to Cast",
				get = function() return Get("ns", "castLook") end,
				set = function(v) SP:TT_Set("ns", "castLook", v) end }
			SP:ThemeSpotSettings("mod.targettracker", entries)
		end
		inCombat = InCombatLockdown() and true or false
		OnPlate.FindAddons()
		SwitchedOnOff()
	end)
end
