-- client: both
-- Miska's PR #26, finished for 3.0.9.5 (Totem Bar > Duration Bars): Pulse Bar Position's On Icon (Clock Sweep)
-- is saved as On Icon plus pulseOnIconSweep and draws the pulse as a sweep on the icon, in the pulse bar's color
-- (Pulse Bar Color, else the theme's, else white); Time Left Position has On Icon (Top) / (Center) / (Bottom)
-- in its one dropdown (no second one), and both times have Inside Bar (Center).
local SP = ShamanPower
local W = __sim.W
local o = SP.opt
local d = SP.options.args.fluffy.args.totembar_duration_section.args
local saved = { o.pulseBarPosition, o.pulseOnIconSweep, o.durationTextLocation, o.pulseBarColor }

-- Pulse Bar Position
check("no Clock Sweep switch of its own", d.pulse_icon_sweep == nil)
local pp = d.pulse_bar_position
checkEq("Pulse Bar Position: On Icon (Sliding Bar)", pp.values.on_icon, "On Icon (Sliding Bar)")
checkEq("Pulse Bar Position: On Icon (Clock Sweep)", pp.values.on_icon_sweep, "On Icon (Clock Sweep)")
pp.set({}, "on_icon_sweep")
check("Clock Sweep is saved as On Icon plus the sweep", o.pulseBarPosition == "on_icon" and o.pulseOnIconSweep == true)
checkEq("and reads back as Clock Sweep", pp.get({}), "on_icon_sweep")
pp.set({}, "on_icon")
check("Sliding Bar: On Icon, the sweep off", o.pulseBarPosition == "on_icon" and not o.pulseOnIconSweep)
checkEq("and reads back as Sliding Bar", pp.get({}), "on_icon")
pp.set({}, "on_icon_sweep")
pp.set({}, "below")
check("another position: the sweep off", o.pulseBarPosition == "below" and not o.pulseOnIconSweep)

-- Time Left Position
check("no Icon Text Position dropdown of its own", d.duration_icon_side == nil)
local tl = d.show_duration_text
checkEq("Time Left: On Icon (Top)", tl.values.icon_top, "On Icon (Top)")
checkEq("Time Left: On Icon (Center) is the saved On Icon", tl.values.icon, "On Icon (Center)")
checkEq("Time Left: On Icon (Bottom)", tl.values.icon_bottom, "On Icon (Bottom)")
checkEq("Time Left: Inside Bar (Center)", tl.values.inside_center, "Inside Bar (Center)")
local n = 0
for _ in pairs(tl.values) do n = n + 1 end
checkEq("Time Left: every choice in the list's order", #tl.sorting, n)
tl.set({}, "icon_bottom")
checkEq("On Icon (Bottom) saved as it is", o.durationTextLocation, "icon_bottom")
checkEq("and reads back", tl.get({}), "icon_bottom")
checkEq("Pulse Time: Inside Bar (Center)", d.pulse_time_display and d.pulse_time_display.values.inside_center, "Inside Bar (Center)")

-- the sweep on the bar (Earth's pulse visual)
local ov = SP.pulseOverlays and SP.pulseOverlays[1]
local host = ov and (ov.button or ov.frame)
if ov and ov.wipe and host and host:IsVisible() then
	pp.set({}, "on_icon_sweep")
	check("Earth's pulse visual is On Icon", ov.isOnIcon == true)
	local now = GetTime()
	ov._pState = nil
	SP:PulseVisualSync(ov, now - 1, 2, now)
	check("the sweep shows", ov.sweep ~= nil and ov.sweep:IsShown())
	check("the sliding bar does not", not ov.wipe:IsShown())
	local function color()
		local c = ov.sweep and W.ST[ov.sweep].swipeColor
		return c and string.format("%.1f %.1f %.1f", c[1], c[2], c[3]) or "none"
	end
	o.pulseBarColor = { r = 1, g = 0, b = 0 }
	SP:RepaintPulseBarColors()
	checkEq("the sweep takes Pulse Bar Color", color(), "1.0 0.0 0.0")
	o.pulseBarColor = nil
	SP:RepaintPulseBarColors()
	local r, g, b = SP:ThemeColor("tb.pulse", 1)
	checkEq("then the theme's pulse color, else white", color(),
		string.format("%.1f %.1f %.1f", r or 1, g or 1, b or 1))
	pp.set({}, "on_icon")
	ov._pState = nil
	SP:PulseVisualSync(ov, now - 1, 2, now)
	check("Sliding Bar again: the sweep goes", not ov.sweep:IsShown())
	check("and the sliding bar is back", ov.wipe:IsShown())
else
	skip("Earth's pulse visual not on screen here")
end

o.pulseBarPosition, o.pulseOnIconSweep, o.durationTextLocation, o.pulseBarColor = saved[1], saved[2], saved[3], saved[4]
SP:UpdatePulseBarPositions()
SP:UpdateTotemProgressBarPositions()
SP:RepaintPulseBarColors()
finish()
