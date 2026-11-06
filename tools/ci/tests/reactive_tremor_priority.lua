-- client: forever
-- regime: secrets
-- Your Tremor alert (3.0.9.7): build 70790 hides the kind of your own loss of control, so every
-- root showed the alert. A hidden kind now shows it only at priority 5 or more (fear and sheep
-- read 5, a root 1); a readable kind is judged by its name as before.
local SP = ShamanPower
local sv = ShamanPower_ReactiveTotems
if not sv then skip("no Reactive Totems") end
local keep = { enabled = sv.enabled, onlyInInstance = sv.onlyInInstance, trackFear = sv.trackFear, hide = sv.hideWhenTotemActive }
sv.enabled, sv.onlyInInstance, sv.trackFear, sv.hideWhenTotemActive = true, false, true, false
local realCan = SP.ReactiveCanAnswer
SP.ReactiveCanAnswer = function() return true end
SP:RebuildReactiveEngine()
local slot = SP.reactiveEngine.fear and SP.reactiveEngine.fear[1]
local c = slot and slot.container
if not c then
	SP.ReactiveCanAnswer = realCan
	sv.enabled, sv.onlyInInstance, sv.trackFear, sv.hideWhenTotemActive = keep.enabled, keep.onlyInInstance, keep.trackFear, keep.hide
	skip("no game-drawn Tremor alert here")
end

local realLoC = C_LossOfControl
local list = {}
C_LossOfControl = {
	GetActiveLossOfControlDataCount = function() return #list end,
	GetActiveLossOfControlData = function(i) return list[i] end,
}
local function hidden(p) return { locType = __sim.secret("locType"), displayText = __sim.secret("displayText"), priority = p, displayType = 2 } end
local function shown(entries)
	list = entries
	SP:ApplyReactiveEngineVisibility()
	return c:IsShown()
end

checkEq("nothing on you: hidden", shown({}), false)
checkEq("a root, its kind hidden (priority 1): hidden", shown({ hidden(1) }), false)
checkEq("a fear, its kind hidden (priority 5): shown", shown({ hidden(5) }), true)
checkEq("a root and a fear together, hidden: shown", shown({ hidden(1), hidden(5) }), true)
checkEq("priority hidden too: shown, as before", shown({ hidden(__sim.secret("priority")) }), true)
checkEq("a readable root: hidden, as before", shown({ { locType = "ROOT", displayText = "Rooted", priority = 1, displayType = 2 } }), false)
checkEq("a readable fear: shown, as before", shown({ { locType = "FEAR", displayText = "Feared", priority = 5, displayType = 2 } }), true)
checkEq("a readable stun: hidden, as before", shown({ { locType = "STUN", displayText = "Stunned", priority = 5, displayType = 2 } }), false)

C_LossOfControl = realLoC
SP.ReactiveCanAnswer = realCan
sv.enabled, sv.onlyInInstance, sv.trackFear, sv.hideWhenTotemActive = keep.enabled, keep.onlyInInstance, keep.trackFear, keep.hide
list = {}
SP:ApplyReactiveEngineVisibility()
finish()
