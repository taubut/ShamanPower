-- client: forever
-- (3.0.9.13) Reactive Totems on WoW: Forever: the game draws the alerts and ShamanPower only plays the sound. The
-- sound followed the scan, not the alert's own show rule, so with Hide When Totem Active on, feared with your
-- Tremor Totem down, the alert stayed hidden and its sound still played. Now the sound skips whenever that
-- hides the alert; everything else plays as before (Tremor not down, Hide When Totem Active off), and an alert
-- turned off stays silent.
local SP = ShamanPower
local W = __sim.W
local sv = ShamanPower_ReactiveTotems
if not (SP.UpdateReactiveTotemDisplay and sv and C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex) then
	skip("no Reactive Totems scan here")
end

-- what this test changes, put back at the end
local was = {
	live = SP.ReactiveEngineLive, host = SP.SetReactiveHostMode, vis = SP.ApplyReactiveEngineVisibility,
	play = SP.PlayReactiveSound, totem = SP.GetElementTotemInfo, fearKnown = SP.IsKnownFearDebuff,
	knows = SPCompat.KnowsSpellID, get = C_UnitAuras.GetDebuffDataByIndex,
	enabled = sv.enabled, inst = sv.onlyInInstance, track = sv.trackFear, own = sv.alertOwn,
	playSound = sv.playSound, hide = sv.hideWhenTotemActive,
}

-- the game draws the alerts here: only the sound is ShamanPower's
SP.ReactiveEngineLive = function() return true end
SP.SetReactiveHostMode = function() end
SP.ApplyReactiveEngineVisibility = function() end
local played = 0
SP.PlayReactiveSound = function(_, id) if id == "fear" then played = played + 1 end end

-- Tremor Totem learned; feared or not; Tremor down or not
SPCompat.KnowsSpellID = function(id) if id == 8143 then return true end return was.knows(id) end
W.fireEvent("SPELLS_CHANGED")
local feared, tremorDown = false, false
local FEAR = { name = "Psychic Scream", icon = 136184, applications = 1, spellId = 8122 }
C_UnitAuras.GetDebuffDataByIndex = function(unit, i)
	if unit == "player" and feared and i == 1 then return FEAR end
	return nil
end
SP.IsKnownFearDebuff = function(_, name) return name == "Psychic Scream" end
local tremorName = SP.ReactiveTotems.fear.totemName or "Tremor Totem"
SP.GetElementTotemInfo = function(_, element)
	if element == SP.ReactiveTotems.fear.totemElement and tremorDown then return true, tremorName, GetTime(), 120 end
	return false, "", 0, 0
end

sv.enabled, sv.onlyInInstance, sv.trackFear, sv.alertOwn = true, false, true, nil
sv.playSound, sv.hideWhenTotemActive = true, true
if not SP.reactiveFrames.fear then SP:CreateReactiveTotemFrame("fear") end

-- one fear: the sound plays (or not) once
local function fear()
	feared = false; SP:UpdateReactiveTotemDisplay()   -- (the last one over: the sound may play again)
	played = 0
	feared = true; SP:UpdateReactiveTotemDisplay(); SP:UpdateReactiveTotemDisplay()
	return played
end

tremorDown = true
checkEq("Hide When Totem Active, feared with Tremor down: the alert is hidden and silent", fear(), 0)
tremorDown = false
checkEq("feared, no Tremor down: the sound plays, once", fear(), 1)

-- feared with Tremor down, then Tremor runs out while still feared: the alert shows again, and so does its sound
tremorDown = true
fear()
tremorDown = false
SP:UpdateReactiveTotemDisplay()
checkEq("Tremor runs out while still feared: the sound plays then", played, 1)

sv.hideWhenTotemActive = false
tremorDown = true
checkEq("Hide When Totem Active off: Tremor down, the alert shows, the sound plays (as before)", fear(), 1)

sv.hideWhenTotemActive = true
sv.trackFear = false
tremorDown = false
checkEq("the Fear alert turned off: no sound", fear(), 0)

-- put everything back
feared, tremorDown = false, false
SP:UpdateReactiveTotemDisplay()
SP.ReactiveEngineLive, SP.SetReactiveHostMode, SP.ApplyReactiveEngineVisibility = was.live, was.host, was.vis
SP.PlayReactiveSound, SP.GetElementTotemInfo, SP.IsKnownFearDebuff = was.play, was.totem, was.fearKnown
SPCompat.KnowsSpellID, C_UnitAuras.GetDebuffDataByIndex = was.knows, was.get
sv.enabled, sv.onlyInInstance, sv.trackFear, sv.alertOwn = was.enabled, was.inst, was.track, was.own
sv.playSound, sv.hideWhenTotemActive = was.playSound, was.hide
W.fireEvent("SPELLS_CHANGED")
finish()
