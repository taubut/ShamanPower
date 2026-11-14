-- client: both
-- (3.0.9.13) Dark Icons (mockup A102): a black edge and a slight vignette on each icon, one switch per bar,
-- on any Icon Shape (Square / Flat / Rounded / Circle), and the Dark theme card that turns all three on.
-- Off (the default) nothing is made; the theme cards save, reset and share the switches like every look.
local SP = ShamanPower
local W = __sim.W
if not (SP.SetIconDark and SP.ApplyIconDark) then skip("no Dark Icons here") end

local function darkOf(host) return host and rawget(host, "spDark") end
local function fileOf(host) local d = darkOf(host) return d and d:IsShown() and d.spFile or nil end
local function ends(s, tail) return type(s) == "string" and s:sub(-#tail) == tail end

local tb = SP.totemButtons and SP.totemButtons[1]
local cd = SP.cooldownButtons and SP.cooldownButtons[1]
check("the totem bar's first button is there", tb ~= nil)

-- off by default: nothing made
checkEq("off by default (totem bar)", SP:IconDarkOf("totem"), false)
checkEq("off by default (cooldown bar)", SP:IconDarkOf("cooldown"), false)
checkEq("off by default (Ready Reminders)", SP:IconDarkOf("ready"), false)
SP:ApplyIconDark()
check("off: no dark picture made on the totem bar", darkOf(tb) == nil)

-- the totem bar on: its own buttons only
SP:SetIconDark(true, "totem")
check("on: the totem bar's button has the square picture (k 6)", ends(fileOf(tb), "Dark_Square_6"), tostring(fileOf(tb)))
if cd then check("the cooldown bar stays as it was", fileOf(cd) == nil) end
local dropAll = _G.ShamanPowerAutoDropAll
if dropAll then check("Drop All too", fileOf(dropAll) ~= nil) end

-- every shape
SP:SetIconShape("flat", "totem")
check("Flat: the square picture", ends(fileOf(tb), "Dark_Square_6"), tostring(fileOf(tb)))
SP:SetIconShape("rounded", "totem")
check("Rounded: the rounded picture", ends(fileOf(tb), "Dark_Rounded_6"), tostring(fileOf(tb)))
SP:SetIconShape("circle", "totem")
check("Circle: the circle picture", ends(fileOf(tb), "Dark_Circle_6"), tostring(fileOf(tb)))
SP:SetIconShape("default", "totem")
check("Square again: the square picture", ends(fileOf(tb), "Dark_Square_6"), tostring(fileOf(tb)))
local d = darkOf(tb)
check("the picture lies over the icon", d and d:GetLeft() == tb.icon:GetLeft() and d:GetTop() == tb.icon:GetTop())

-- off again: hidden
SP:SetIconDark(false, "totem")
check("off again: hidden", fileOf(tb) == nil)

-- the cooldown bar: its own thickness (k 7)
if cd then
	SP:SetIconDark(true, "cooldown")
	check("the cooldown bar on: k 7", ends(fileOf(cd), "Dark_Square_7"), tostring(fileOf(cd)))
	SP:SetIconDark(false, "cooldown")
end

-- Ready Reminders: the picture on the icon and the border black
local f
if SP.ReadyRemindersDemo then SP:ReadyRemindersDemo(true); __sim.advance(0.3) end
for _, fr in pairs(SP.readyReminderFrames or {}) do if fr.icon then f = fr break end end
if f then
	SP:SetIconDark(true, "ready")
	check("Ready Reminders on: the picture (k 5)", ends(fileOf(f), "Dark_Square_5"), tostring(fileOf(f)))
	local r, g, b = f.border:GetBackdropBorderColor()
	check("and the border black", r == 0 and g == 0 and b == 0, string.format("%s %s %s", tostring(r), tostring(g), tostring(b)))
	SP:SetIconDark(false, "ready")
	r, g, b = f.border:GetBackdropBorderColor()
	check("off: the border's own color back", not (r == 0 and g == 0 and b == 0))
	check("off: the picture hidden", fileOf(f) == nil)
	if SP.ReadyRemindersDemo then SP:ReadyRemindersDemo(false) end
end

-- the Dark theme card
SP:SetThemeGlobal("dark")
checkEq("the Dark card: in use", SP:ThemeCard(), "dark")
check("the Dark card: all three on", SP:IconDarkOf("totem") and SP:IconDarkOf("cooldown") and SP:IconDarkOf("ready"))
checkEq("the Dark card: not Custom", SP:ThemeIsCustom(), false)
check("the Dark card: the totem bar dark", fileOf(tb) ~= nil)
SP:SetIconDark(false, "cooldown")
checkEq("a switch changed: Custom", SP:ThemeIsCustom(), true)
-- saved as a theme, shared, imported: the switches come with it
local id = SP:ThemeSaveAs("CI Dark Test")
check("saved as a theme", id ~= nil)
local code = id and SP:ThemeShareCode(id)
check("its share code", type(code) == "string" and #code > 10)
SP:SetThemeGlobal("standard")
checkEq("Standard: in use", SP:ThemeCard(), "standard")
check("Standard: all three off", not SP:IconDarkOf("totem") and not SP:IconDarkOf("cooldown") and not SP:IconDarkOf("ready"))
check("Standard: the totem bar as it was", fileOf(tb) == nil)
if id then
	SP:ThemePickMine(id)
	check("the saved theme brings them back", SP:IconDarkOf("totem") and not SP:IconDarkOf("cooldown") and SP:IconDarkOf("ready"))
	SP:SetThemeGlobal("standard")
	SP:ThemeDelete(id)
end
if code then
	local th = SP:ThemeImport(code)
	check("the share code imports", th ~= nil)
	local flat = th and th.flat or {}
	check("and carries the switches", flat["o.iconDark"] == true and flat["o.iconDarkReady"] == true and flat["o.iconDarkCooldown"] == nil)
	if th and th.id then SP:ThemeDelete(th.id) end
end
SP:SetThemeGlobal("standard")
SP:SetIconShape("default", "totem")
finish()
