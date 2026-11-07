-- client: forever
-- The shield setup and WoW's Tracked Buffs bar (3.0.9.7, a player's ticket): with that bar Hidden in Edit
-- Mode the game never builds its shield item, so ShamanPower never saw the shield and asked again after
-- every reload, although its layout was saved. The setup now puts the bar on Always in the active Edit
-- Mode layout (from Hidden or In Combat; nothing else changes), and the ask comes only when ShamanPower's
-- layout isn't saved or the bar is Hidden.
local SP = ShamanPower
if not SP.ShieldGoneSetup then skip("no Shield Charges module") end

-- the game's Edit Mode: two presets, then the saved layouts (activeLayout counts the presets first)
local realE, realM = C_EditMode, EditModePresetLayoutManager
local realEnum = { s = Enum.EditModeSystem, i = Enum.EditModeCooldownViewerSystemIndices,
	v = Enum.EditModeCooldownViewerSetting, vis = Enum.CooldownViewerVisibleSetting }
-- (the game's values, WoW: Forever's API documentation; the sim's own tables are empty stand-ins)
Enum.EditModeSystem = { CooldownViewer = 20 }
Enum.EditModeCooldownViewerSystemIndices = { Essential = 1, Utility = 2, BuffIcon = 3, BuffBar = 4 }
Enum.EditModeCooldownViewerSetting = { IconSize = 3, VisibleSetting = 6, HideWhenInactive = 8 }
Enum.CooldownViewerVisibleSetting = { Always = 0, InCombat = 1, Hidden = 2 }
local CV, IDX = Enum.EditModeSystem.CooldownViewer, Enum.EditModeCooldownViewerSystemIndices
local VIS, ICON, HIDE = Enum.EditModeCooldownViewerSetting.VisibleSetting, Enum.EditModeCooldownViewerSetting.IconSize,
	Enum.EditModeCooldownViewerSetting.HideWhenInactive
local ALWAYS, INCOMBAT, HIDDEN = 0, 1, 2

local saves, saveFails, active = 0, false, 3
local function layouts(buffVis)
	return { activeLayout = active, layouts = {
		{ layoutName = "Mine", layoutType = 1, systems = {
			{ system = 0, systemIndex = 1, settings = { { setting = 0, value = 1 } } },
			{ system = CV, systemIndex = IDX.Essential, settings = { { setting = VIS, value = HIDDEN } } },
			{ system = CV, systemIndex = IDX.BuffIcon, settings = { { setting = ICON, value = 7 }, { setting = VIS, value = buffVis }, { setting = HIDE, value = 1 } } },
		} },
	} }
end
local current, last = layouts(HIDDEN), nil
C_EditMode = {
	GetLayouts = function() return current end,
	SaveLayouts = function(info) if saveFails then error("refused") end saves = saves + 1; last = info end,
}
EditModePresetLayoutManager = { GetCopyOfPresetLayouts = function() return { {}, {} } end }
local function buff(info)
	for _, sys in ipairs(info.layouts[1].systems) do
		if sys.system == CV and sys.systemIndex == IDX.BuffIcon then
			local out = {}
			for _, s in ipairs(sys.settings) do out[s.setting] = s.value end
			return out
		end
	end
end
local function essential(info) return info.layouts[1].systems[2].settings[1].value end

-- Hidden: switched to Always, the rest of the layout as it was
check("Hidden: seen as hidden", SP:ShieldGoneTrackedHidden())
check("Hidden: switched", SP:ShieldGoneShowTrackedBuffs())
checkEq("saved once", saves, 1)
local b = last and buff(last) or {}
checkEq("the bar on Always", b[VIS], ALWAYS)
check("its other settings untouched", b[ICON] == 7 and b[HIDE] == 1)
checkEq("the other bars untouched (Essential stays Hidden)", last and essential(last), HIDDEN)

-- In Combat: not hidden (its items come in the first fight), but the setup puts it on Always too
current, saves = layouts(INCOMBAT), 0
check("In Combat: not counted as hidden", not SP:ShieldGoneTrackedHidden())
check("In Combat: switched", SP:ShieldGoneShowTrackedBuffs() and saves == 1 and buff(last)[VIS] == ALWAYS)

-- Always: nothing saved
current, saves = layouts(ALWAYS), 0
local ok, why = SP:ShieldGoneShowTrackedBuffs()
check("Always: left alone", not ok and why == nil and saves == 0)

-- one of the game's presets active: never saved
active = 2
current, saves = layouts(HIDDEN), 0
check("a preset active: left alone", not SP:ShieldGoneShowTrackedBuffs() and saves == 0)
check("a preset active: not counted as hidden", not SP:ShieldGoneTrackedHidden())
active = 3

-- the game refuses the save: a reason, and the layout as it was
current, saves, saveFails = layouts(HIDDEN), 0, true
ok, why = SP:ShieldGoneShowTrackedBuffs()
check("refused: false and why", not ok and type(why) == "string")
checkEq("refused: the value put back", buff(current)[VIS], HIDDEN)
saveFails = false

-- the ask
local realComplete = SP.ShieldGoneLayoutComplete
local complete = true
SP.ShieldGoneLayoutComplete = function() return complete end
current = layouts(INCOMBAT)
check("layout saved, bar In Combat: no ask", not SP:ShieldGoneAskNeeded())
current = layouts(ALWAYS)
check("layout saved, bar Always: no ask", not SP:ShieldGoneAskNeeded())
current = layouts(HIDDEN)
check("layout saved, bar Hidden: ask (the setup shows it)", SP:ShieldGoneAskNeeded())
complete = false
current = layouts(ALWAYS)
check("layout not saved: ask", SP:ShieldGoneAskNeeded())
SP.ShieldGoneLayoutComplete = realComplete

-- the whole setup, the bar Hidden: afterwards it is on Always
local LS_CID, LS_ID = 200311, 324
local store, savedStr, n = {}, nil, 0
local realC, realEnc, realKnows, realCat = C_CooldownViewer, C_EncodingUtil, SPCompat.KnowsSpellID, Enum.CooldownViewerCategory
C_EncodingUtil = {
	SerializeCBOR = function(t) n = n + 1; store["k" .. n] = t; return "k" .. n end,
	CompressString = function(s) return s end, DecompressString = function(s) return s end,
	EncodeBase64 = function(s) return s end, DecodeBase64 = function(s) return s end,
	DeserializeCBOR = function(s) return store[s] end,
}
C_CooldownViewer = {
	IsCooldownViewerAvailable = function() return true end,
	GetLayoutData = function() return savedStr end,
	SetLayoutData = function(s) savedStr = s end,
	GetCooldownViewerCategorySet = function(cat) if cat == 2 then return { LS_CID } end return {} end,
	GetCooldownViewerCooldownInfo = function(id) if id == LS_CID then return { spellID = LS_ID } end return { spellID = 1000 + id } end,
}
Enum.CooldownViewerCategory = { Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 3, HiddenActive = -1, HiddenPassive = -2 }
SPCompat.KnowsSpellID = function(id) return id == LS_ID end
__sim.W.fireEvent("SPELLS_CHANGED")
current, saves = layouts(HIDDEN), 0
local keepHide = SP.opt.cdmHideShieldIcon
ok, why = SP:ShieldGoneSetup()
check("the setup works: " .. tostring(why), ok)
check("the setup put the bar on Always", saves == 1 and last and buff(last)[VIS] == ALWAYS)

C_CooldownViewer, C_EncodingUtil, SPCompat.KnowsSpellID, Enum.CooldownViewerCategory = realC, realEnc, realKnows, realCat
SP.opt.cdmHideShieldIcon = keepHide
SP.opt.cdmLayoutBackup = nil
__sim.W.fireEvent("SPELLS_CHANGED")
C_EditMode, EditModePresetLayoutManager = realE, realM
Enum.EditModeSystem, Enum.EditModeCooldownViewerSystemIndices = realEnum.s, realEnum.i
Enum.EditModeCooldownViewerSetting, Enum.CooldownViewerVisibleSetting = realEnum.v, realEnum.vis
finish()
