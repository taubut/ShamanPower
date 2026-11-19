-- client: both
-- (3.0.9.17, A111) Windfury Proc, its own module (WoW: Forever only). The game names each proc's own spell in
-- SPELL_UPDATE_COOLDOWN (the owner's test on a dummy, 11-17: 10610 Windfury Totem, 439440 Windfury Weapon); the
-- casts (10614 Windfury Totem, 10486 Windfury Weapon) never show it. Each proc: the proc's own icon for Time On
-- Screen from that proc, its glow, its sound at most once a second. Its own page, its own font row (Appearance >
-- Fonts & Textures), its settings switch with the profile, it moves in Unlock UI. Off by default.
local SP = ShamanPower
local W = __sim.W

if not SPCompat.FOREVER then
	check("Anniversary: no Windfury Proc module", SP.WindfuryProcLoaded == nil)
	check("Anniversary: no page", SP.options.args.fluffy.args.windfuryproc_section == nil)
	local area = false
	for _, a in ipairs(SP.FONT_AREAS) do if a.key == "windfury" then area = true end end
	check("Anniversary: no font row", not area)
	finish()
	return
end

check("the module is loaded", SP.WindfuryProcLoaded == true)
local sv = ShamanPowerWindfuryProcDB
check("its own saved settings", type(sv) == "table")
if type(sv) ~= "table" then finish() return end
local keep = {}
for k, v in pairs(sv) do keep[k] = v end
local f = _G.ShamanPowerWindfuryProcFrame
check("its frame", f ~= nil)
check("off by default", sv.enabled == false)

local sounds = 0
local realPlay = SP.PlaySoundWithVolume
SP.PlaySoundWithVolume = function(...) sounds = sounds + 1 end
local page = SP.options.args.fluffy.args.windfuryproc_section
check("its own page", page ~= nil)
local function setting(key, ...) page.args[key].set(nil, ...) end
local function proc(id) W.fireEvent("SPELL_UPDATE_COOLDOWN", id) end
local function tex(id) return C_Spell.GetSpellTexture(id) end

proc(439440)
check("off: a proc shows nothing", not f:IsShown() and sounds == 0)

setting("wf_enabled", true)
check("Enable Windfury Proc turns it on", sv.enabled == true)

-- a weapon proc
proc(439440)
check("a Windfury Weapon proc: it shows", f:IsShown())
checkEq("with Windfury Weapon's icon", f.icon:GetTexture(), tex(8232))
checkEq("its sound", sounds, 1)
check("its glow", f.glow:IsShown())
__sim.advance(1.4)
check("still up at 1.4 seconds", f:IsShown())
__sim.advance(0.3)
check("gone after Time On Screen (1.5 seconds)", not f:IsShown())

-- a totem proc, reported twice
proc(10610); proc(10610)
check("a Windfury Totem proc: it shows", f:IsShown())
checkEq("with Windfury Totem's icon", f.icon:GetTexture(), tex(8512))
checkEq("reported twice: one sound", sounds, 2)
__sim.advance(1.1)
proc(10610)
checkEq("a proc over a second later: its own sound", sounds, 3)
__sim.advance(1.2)
check("a proc while it shows keeps it up 1.5 seconds from that proc", f:IsShown())
__sim.advance(0.4)
check("then gone", not f:IsShown())

-- the casts and anything else: never
for _, id in ipairs({ 10614, 10486, 8232, 8512, 8042, 2484 }) do proc(id) end
check("casting Windfury Weapon / dropping Windfury Totem and other spells: nothing", not f:IsShown())
proc(__sim.secret("id"))
check("a hidden ID: nothing (never read)", not f:IsShown())
proc(nil)
check("no ID: nothing", not f:IsShown())

-- each kind its own switch
setting("wf_weapon", false)
proc(439440)
check("Windfury Weapon Procs off: a weapon proc shows nothing", not f:IsShown())
proc(10610)
check("Windfury Totem Procs still on", f:IsShown())
__sim.advance(2)
setting("wf_weapon", true)
setting("wf_totem", false)
proc(10608)
check("Windfury Totem Procs off: a totem proc shows nothing", not f:IsShown())
setting("wf_totem", true)

-- Time On Screen
setting("wf_time", 3)
proc(439440); __sim.advance(2.8)
check("Time On Screen 3: still up at 2.8", f:IsShown())
__sim.advance(0.4)
check("Time On Screen 3: gone at 3.2", not f:IsShown())
setting("wf_time", 1.5)

-- Show Internal Cooldown: Windfury Weapon's 1.5 seconds (WoW: Forever's spell data), a sweep on its icon
check("Show Internal Cooldown: on by default", sv.showICD == true and page.args.wf_icd.get() == true)
proc(439440)
check("a weapon proc: the sweep over its icon", f.cd:IsShown())
__sim.advance(1.6)
check("the sweep done: the alert gone with it", not f:IsShown() and not f.cd:IsShown())
proc(10610)
check("a totem proc: no sweep (Windfury Totem has no internal cooldown)", f:IsShown() and not f.cd:IsShown())
__sim.advance(2)
proc(439440); __sim.advance(0.5); proc(10610)
check("a totem proc during the weapon's cooldown: the totem's icon, no sweep", f.icon:GetTexture() == tex(8512) and not f.cd:IsShown())
__sim.advance(2)
setting("wf_time", 1)
proc(439440); __sim.advance(1.2)
check("Time On Screen 1: still up until the sweep is done", f:IsShown() and f.cd:IsShown())
__sim.advance(0.5)
check("then gone", not f:IsShown())
setting("wf_icd", false)
proc(439440)
check("Show Internal Cooldown off: no sweep", f:IsShown() and not f.cd:IsShown())
__sim.advance(1.2)
check("off: Time On Screen 1 is its own again", not f:IsShown())
setting("wf_icd", true); setting("wf_time", 1.5)
setting("wf_display_mode", "text")
proc(439440)
check("Text Only: no icon, no sweep", not f.cd:IsShown())
setting("wf_display_mode", "icon")
check("back to Icon Only while it shows: the sweep again", f.cd:IsShown())
__sim.advance(2)
-- its look (Ready Reminders' While On Cooldown rows that fit 1.5 seconds)
proc(439440)
check("Show Countdown (on by default): the seconds left", f.count:IsShown() and f.count:GetText() == "1.5")
__sim.advance(0.5)
local n = tonumber(f.count:GetText())
check("the countdown runs down", n ~= nil and n <= 1.05 and n >= 0.9, tostring(f.count:GetText()))
local cr, cg, cb = f.count:GetTextColor()
check("white unless Color the Cooldown Numbers", cr == 1 and cg == 1 and cb == 1)
__sim.advance(1.2)
check("done: the countdown goes", not f.count:IsShown())
setting("wf_icd_sweep", "vertical")
check("Sweep Direction shows for Color Fills In", page.args.wf_icd_direction.hidden() == false)
proc(439440); __sim.advance(0.75)
check("Color Fills In: the gray sheet, no clock sweep", f.sheet:IsShown() and not f.cd:IsShown())
local h, ih = f.sheet:GetHeight(), f.icon:GetHeight()
check("Color Fills In: half the icon still gray at half time", math.abs(h - ih * 0.5) < ih * 0.1, tostring(h))
checkEq("From The Bottom: the gray leaves toward the top", select(1, f.sheet:GetPoint(1)), "TOPLEFT")
__sim.advance(1)
setting("wf_icd_direction", "top")
checkEq("From The Top: toward the bottom", select(1, f.sheet:GetPoint(1)), "BOTTOMLEFT")
setting("wf_icd_sweep", "none")
proc(439440)
check("Sweep None: no sweep, the countdown still", not f.cd:IsShown() and not f.sheet:IsShown() and f.count:IsShown())
__sim.advance(2)
setting("wf_icd_sweep", "radial"); setting("wf_icd_direction", "bottom")
check("no bar: Bar Height and Bar Color hidden", page.args.wf_icd_bar_height.hidden() == true)
setting("wf_icd_bar", "below")
check("a bar: Bar Height and Bar Color", page.args.wf_icd_bar_height.hidden() == false and page.args.wf_icd_bar_color.hidden() == false)
proc(439440); __sim.advance(0.75)
check("Progress Bar: half drained at half time", f.bar:IsShown() and math.abs(f.bar:GetValue() - 0.5) < 0.1, tostring(f.bar:GetValue()))
check("Progress Bar: below the icon", select(1, f.bar:GetPoint(1)) == "TOPLEFT" and select(2, f.bar:GetPoint(1)) == f)
__sim.advance(1)
check("done: the bar goes", not f.bar:IsShown())
setting("wf_icd_bar", "above")
check("Progress Bar: above the icon", select(1, f.bar:GetPoint(1)) == "BOTTOMLEFT")
setting("wf_icd_bar_height", 8)
checkEq("Bar Height", math.floor(f.bar:GetHeight() + 0.5), 8)
setting("wf_icd_bar", "none"); setting("wf_icd_bar_height", 4)
setting("wf_icd_gray", true)
proc(439440)
check("Gray Out The Icon while it runs", f.icon:IsDesaturated())
__sim.advance(2)
check("then in color again", not f.icon:IsDesaturated())
setting("wf_icd_gray", false)
setting("wf_display_mode", "both")
setting("wf_icd_count_position", "below")
check("Countdown below the icon: the word goes under it", select(2, f.text:GetPoint(1)) == f.count)
setting("wf_icd_count_position", "center")
check("Countdown on the icon: the word right under the icon", select(2, f.text:GetPoint(1)) == f)
setting("wf_display_mode", "icon")
setting("wf_icd_count_size", 30)
checkEq("Countdown Text Size", select(2, f.count:GetFont()), 30)
setting("wf_icd_count_size", 0)
setting("wf_icd_count_colors", true)
proc(439440); __sim.advance(1.2)
local r1, g1, b1 = f.count:GetTextColor()
local er, eg, eb = SP:CountdownColor(0.3, 1.5, "cd")
check("Color the Cooldown Numbers: your Cooldown Numbers colors", math.abs(r1 - er) < 0.05 and math.abs(g1 - eg) < 0.05 and math.abs(b1 - eb) < 0.05)
__sim.advance(1)
setting("wf_icd_count_colors", false)
setting("wf_icd_countdown", false)
check("Show Countdown off: its rows hide", page.args.wf_icd_count_position.hidden() == true and page.args.wf_icd_count_size.hidden() == true)
proc(439440)
check("Show Countdown off: no number", not f.count:IsShown())
__sim.advance(2)
setting("wf_icd_countdown", true)
setting("wf_icd", false)
check("Show Internal Cooldown off: its look greyed out", page.args.wf_icd_sweep.disabled() == true)
setting("wf_icd", true)
check("Show Internal Cooldown greyed out with Windfury Weapon Procs off",
	(function() sv.weapon = false local d = page.args.wf_icd.disabled() sv.weapon = true return d end)())

-- in a fight
__sim.setCombat(true)
proc(439440)
check("in a fight: it shows", f:IsShown())
__sim.advance(2)
check("in a fight: and goes", not f:IsShown())
__sim.setCombat(false)

-- Display Mode
proc(439440)
check("Icon Only: the icon, no word", f.icon:IsShown() and not f.text:IsShown())
setting("wf_display_mode", "both")
check("Icon + Text: both", f.icon:IsShown() and f.text:IsShown() and f.text:GetText() == "WINDFURY!")
checkEq("Icon + Text: the word under the icon", select(1, f.text:GetPoint(1)), "TOP")
setting("wf_display_mode", "text")
check("Text Only: the word, no icon", f.text:IsShown() and not f.icon:IsShown())
checkEq("Text Only: the word on its spot", select(1, f.text:GetPoint(1)), "CENTER")
check("Text Only: no glow", not f.glow:IsShown())
setting("wf_display_mode", "icon")
setting("wf_icon_size", 90)
checkEq("Icon Size", math.floor(f:GetWidth() + 0.5), 90)
setting("wf_opacity", 0.5)
check("Opacity", math.abs(f:GetAlpha() - 0.5) < 0.01)
setting("wf_opacity", 1); setting("wf_icon_size", 64)
setting("wf_show_glow", false)
proc(439440)
check("Show Glow off: no glow", not f.glow:IsShown())
setting("wf_show_glow", true)
__sim.advance(2)

-- Glow Shape: its own (Square, Round, Proc Glow), else Appearance > Themes' Glow Shape
local procStarts, procThick = 0, nil
local realStart = SP.ProcGlow_Start
SP.ProcGlow_Start = function(fr, opts)
	if fr == f then procStarts = procStarts + 1; procThick = opts and opts.xOffset end
	return realStart(fr, opts)
end
local keepShared = SP.opt.glowShape
local shapes = SP:GlowShapeValues()
check("Glow Shape offers Square, Round and Proc Glow", shapes.default ~= nil and shapes.round ~= nil and shapes.proc ~= nil)
SP.opt.glowShape = "round"
checkEq("not picked: shows the shared Glow Shape", page.args.wf_glow_shape.get(), "round")
proc(439440)
check("not picked: the shared Round glow", f.glow:IsShown() and tostring(f.glow:GetTexture()):lower():find("ring_glow") ~= nil)
__sim.advance(2)
setting("wf_glow_shape", "default")
proc(439440)
check("Square: the square glow", f.glow:IsShown() and tostring(f.glow:GetTexture()):find("IconAlert") ~= nil and procStarts == 0)
__sim.advance(2)
check("Glow Thickness only for Proc Glow", page.args.wf_glow_thick.hidden() == true)
setting("wf_glow_shape", "proc")
check("Proc Glow: Glow Thickness shows", page.args.wf_glow_thick.hidden() == false)
proc(439440)
check("Proc Glow: the ring, not the square glow", procStarts == 1 and not f.glow:IsShown())
__sim.advance(2)
setting("wf_glow_thick", 0.5)
proc(439440)
checkEq("Proc Glow: its own Glow Thickness", procThick, f:GetWidth() * 0.5)
__sim.advance(2)
SP.opt.glowShape = "default"
proc(439440)
check("its own pick wins over the shared one", procStarts == 3 and not f.glow:IsShown())
__sim.advance(2)
SP.ProcGlow_Start = realStart
SP.opt.glowShape = keepShared
sv.glowShape, sv.glowThick = nil, nil

-- its own font row (Appearance > Fonts & Textures), like Shield Charges'
local area = false
for _, a in ipairs(SP.FONT_AREAS) do if a.key == "windfury" then area = true end end
check("Fonts & Textures: a Windfury Proc row", area and SP.options.args.settings.args.settings_fonts.args.font_windfury ~= nil)
local o = SP.opt
local keepAreas = o.fontAreas
o.fontAreas = { windfury = { outline = "THICKOUTLINE" } }
SP:RefreshFonts()
setting("wf_display_mode", "both")
checkEq("its own outline", select(3, f.text:GetFont()), "THICKOUTLINE")
o.fontAreas = { charges = { outline = "THICKOUTLINE" } }
SP:RefreshFonts()
checkEq("Shield Charges' font is not its", select(3, f.text:GetFont()), "OUTLINE")
o.fontAreas = keepAreas
SP:RefreshFonts()
setting("wf_text_size", 30)
checkEq("Font Size", select(2, f.text:GetFont()), 30)
setting("wf_text_size", 24)
setting("wf_display_mode", "icon")

-- the sound off; ShamanPower off
setting("wf_play_sound", false)
local before = sounds
proc(439440)
check("Play Sound off: shown, no sound", f:IsShown() and sounds == before)
setting("wf_play_sound", true)
__sim.advance(2)
local realOff = SP.IsOff
SP.IsOff = function() return true end
SP:UpdateWindfuryProcAppearance()
proc(439440)
check("ShamanPower switched off: nothing", not f:IsShown())
SP.IsOff = realOff
SP:UpdateWindfuryProcAppearance()

-- Test Windfury Proc
before = sounds
page.args.wf_test.func()
check("Test: it shows with its sound", f:IsShown() and sounds == before + 1)
__sim.advance(2)

-- Unlock UI: Move Windfury Proc
check("Move is greyed out while it is off", (function() sv.enabled = false local d = page.args.wf_move.disabled() sv.enabled = true return d end)())
page.args.wf_move.func()
__sim.advance(0.3)
check("Move: it shows for moving", f:IsShown())
__sim.advance(3)
check("Move: it stays up while unlocked", f:IsShown())
SP:SetMasterUnlock(false)
__sim.advance(0.5)
check("Done: gone again", not f:IsShown())
f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", 120, 40)
f:GetScript("OnDragStop")(f)
check("a move is saved", sv.position.x == 120 and sv.position.y == 40)
SP:WindfuryProcReset()
check("Reset: back where it starts", sv.position.x == 0 and sv.position.y == 250)

-- its settings switch with the profile
local db = SP.db
local was = db:GetCurrentProfile()
db:SetProfile("WFP A")
setting("wf_icon_size", 50)
db:SetProfile("WFP B")
setting("wf_icon_size", 100)
db:SetProfile("WFP A")
checkEq("profile A: its own Icon Size", sv.iconSize, 50)
checkEq("profile A: drawn at it", math.floor(f:GetWidth() + 0.5), 50)
db:SetProfile("WFP B")
checkEq("profile B: its own Icon Size", sv.iconSize, 100)
db:SetProfile(was)
for _, n in ipairs({ "WFP A", "WFP B" }) do pcall(db.DeleteProfile, db, n, true) end

-- the settings page draws
local ok, err = pcall(ShamanPowerConfig.Open, ShamanPowerConfig, { "fluffy", "windfuryproc_section" })
__sim.advance(0.3)
check("the page opens", ok, tostring(err))
if ShamanPowerConfigUIFrame then ShamanPowerConfigUIFrame:Hide() end

-- put back
SP.PlaySoundWithVolume = realPlay
wipe(sv); for k, v in pairs(keep) do sv[k] = v end
SP:UpdateWindfuryProcAppearance()
finish()
