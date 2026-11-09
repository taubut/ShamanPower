-- Click Through The Totem Bar / Click Through The Cooldown Bar (3.0.9, a user's ask: a bar placed
-- mid-screen caught the mouse in fights, the tooltip on every hover and a right-click pulling a
-- totem back). One setting per bar, Off / In Combat / Always: Totem Bar > Clicks, and the Clicks
-- band on the Cooldown Bar page. Click through: the bar's buttons ignore the mouse, so there is
-- no tooltip, no click and no flyout from hovering, and a click lands on whatever is behind the
-- bar. Keybinds still cast and still open the flyouts: a key presses the button itself, which
-- needs no mouse. Nothing on screen changes. Off, nothing changes for anyone.
--
-- Who flips the mouse. Out of a fight: this file (ApplyClickThrough), after every rebuild of the
-- bars and on a setting change; Show Items Only When Running Out keeps its hidden items' mouse
-- off through it (ShamanPowerCues.lua asks ClickThroughMouse before it gives one its mouse
-- back). In Combat: the mouse has to go at the fight's START, and the game locks every button's
-- mouse the moment a fight begins, so the game's own secure side does it: one state driver
-- ("[combat] 1; 0") on a secure handler frame, whose snippet turns the mouse off on every button
-- listed with it (the restricted frame handle has EnableMouse). PLAYER_REGEN_DISABLED arrives a
-- moment before the lock as well (the Cues file's hidden items rely on it), so the same is done
-- from here then, for the fight's first frame. At the fight's end the mouse comes back from here
-- (PLAYER_REGEN_ENABLED, out of the lock), and a setting changed during the fight lands then.
--
-- A flyout open as the fight starts (hovered a moment before the pull) would hang there: with
-- the mouse gone, the "mouse left" that closes a flyout never comes. So the same secure step
-- shuts every flyout of a bar under In Combat or Always: ChildUpdate("show", false) on the
-- flyout's button, the call picking a totem makes in a fight; in box mode (Blizzard-Style
-- Flyout Arrows) the box's unit to "none" and the key's toggle back to "open", what the close
-- arrow presses. Opened by a key during the fight, a flyout closes by the key or by picking.
--
-- The list: every button on the two bars, gathered again after each rebuild (the hooks at the
-- end). A button follows the bar it sits on: the Totem Bar's element buttons, their flyouts and
-- flyout arrows, Drop All, Totemic Call, the Earth Shield button and its flyout, Compact's shield
-- and Totem Rows' copies; the Cooldown Bar's items, their flyout arrows, and the shield's and the
-- imbue's flyouts. A popped-out element is the same button, so it follows the Totem Bar.
local SP = ShamanPower

local MODES = { off = true, combat = true, always = true }
local driver            -- the secure handler frame carrying the [combat] state driver
local frames = {}       -- the last gather: every button on the two bars (f.spClickThroughBar: "tb" / "cd")
local listed = {}       -- of those, the ones under In Combat or Always (the driver's frame refs)
local parents = {}      -- the flyout parents (f.spClickThroughBar as above): shut at the fight's start
local queued            -- a gather asked for this frame (the rebuild hooks): once

local function Mode(bar)
	local v = SP.opt and SP.opt[bar == "cd" and "cdbarClickThrough" or "totemBarClickThrough"]
	return MODES[v] and v or "off"
end

function SP:TotemBarClickThrough() return Mode("tb") end
function SP:CooldownBarClickThrough() return Mode("cd") end

local function Fighting()
	return InCombatLockdown() or UnitAffectingCombat("player") or false
end

-- the mouse a button of that bar ("tb" / "cd") should have right now, by the bar's setting:
-- ShamanPowerCues.lua asks before it gives a hidden Running Out item its mouse back
function SP:ClickThroughMouse(bar)
	local mode = Mode(bar)
	if mode == "always" then return false end
	if mode == "combat" and Fighting() then return false end
	return true
end

local seen = {}
local function put(f, bar)
	if not f or seen[f] then return end
	seen[f] = true
	frames[#frames + 1] = f
	f.spClickThroughBar = bar
end

local function parent(f, bar)   -- (ChildUpdate is a secure handle's method only: no Lua-side check)
	if not f then return end
	parents[#parents + 1] = f
	f.spClickThroughBar = bar
end

local function Gather()
	wipe(frames)
	wipe(seen)
	wipe(parents)
	local tb = SP.totemButtons or {}
	for e = 1, 4 do
		local b = tb[e]
		put(b, "tb")
		parent(b, "tb")
		if b then
			put(b.spFlyoutOpenArrow, "tb")
			put(b.spFlyoutCloseArrow, "tb")
		end
		local fl = SP.totemFlyouts and SP.totemFlyouts[e]
		if fl then
			for _, fb in ipairs(fl.allButtons or {}) do put(fb, "tb") end
			for _, fb in ipairs(fl.buttons or {}) do put(fb, "tb") end
		end
		put(_G["ShamanPowerFlyout" .. e .. "Btn0"], "tb")   -- Empty (WoW: Forever)
		if SP.RowsCopies then
			for _, c in ipairs(SP:RowsCopies(e) or {}) do put(c, "tb") end
		end
	end
	put(_G.ShamanPowerAutoDropAll, "tb")
	-- (3.0.9.9) Call Flyout on Drop All: its Calls, and its holder shut at the fight's start
	for _, b in pairs(SP.callFlyoutButtons or {}) do put(b, "tb") end
	parent(SP.callFlyoutHeader, "tb")
	put(_G.ShamanPowerAutoTotemicCall, "tb")
	put(_G.ShamanPowerEarthShieldBtn, "tb")
	parent(_G.ShamanPowerEarthShieldBtn, "tb")
	for _, b in ipairs(SP.esFlyoutButtons or {}) do put(b, "tb") end
	put(_G.ShamanPowerCompactShieldBtn, "tb")
	for _, b in ipairs(SP.cooldownButtons or {}) do
		put(b, "cd")
		put(b.spFlyoutOpenArrow, "cd")
		put(b.spFlyoutCloseArrow, "cd")
	end
	-- (3.0.9.9) the Cooldown Bar's own frame while it stands on its own: it takes the mouse to be
	-- dragged (UpdateCooldownBarPosition), and with its buttons let go it still held the cursor
	-- (a Discord report). Unlock UI moves it by a box of its own; attached, it never has the mouse.
	local bar = SP.cooldownBar
	if bar and SP.opt and not SP.opt.cooldownBarLocked and bar:GetParent() == UIParent then put(bar, "cd") end
	local sh, im = SP.shieldFlyout, SP.weaponImbueFlyout
	if sh then for _, b in ipairs(sh.buttons or {}) do put(b, "cd") end end
	if im then for _, b in ipairs(im.buttons or {}) do put(b, "cd") end end
	parent(SP.shieldButton, "cd")
	parent(SP.weaponImbueButton, "cd")
end

local function Driver()
	if driver then return driver end
	driver = CreateFrame("Frame", "ShamanPowerClickThrough", UIParent, "SecureHandlerStateTemplate")
	-- the fight's start (inside the lock): the mouse off on every listed button, and every flyout
	-- of those bars shut. The fight's end is left alone: the mouse comes back from Lua then, out
	-- of the lock, by the settings
	driver:SetAttribute("_onstate-spct", [[
		if tostring(newstate) ~= "1" then return end   -- (the driver hands over the number 1, not "1")
		local n = self:GetAttribute("spctN") or 0
		for i = 1, n do
			local f = self:GetFrameRef("spct" .. i)
			if f and f.EnableMouse then f:EnableMouse(false) end
		end
		local p = self:GetAttribute("spctFlyouts") or 0
		for i = 1, p do
			local f = self:GetFrameRef("spctFly" .. i)
			if f and f.ChildUpdate then f:ChildUpdate("show", false) end
		end
		local b = self:GetAttribute("spctBoxes") or 0
		for i = 1, b do
			local box = self:GetFrameRef("spctBox" .. i)
			local toggle = self:GetFrameRef("spctBoxToggle" .. i)
			local reset = self:GetFrameRef("spctBoxReset" .. i)
			if box then box:SetAttribute("unit", "none") end
			if toggle and reset then toggle:SetAttribute("macrotext", reset:GetAttribute("attribute-value")) end
		end
	]])
	RegisterStateDriver(driver, "spct", "[combat] 1; 0")
	return driver
end

-- every button on both bars gets the mouse its bar's setting says, and the driver its list.
-- Out of a fight only (the buttons and the driver are locked in one); asked in a fight, the
-- fight's end runs it
function SP:ApplyClickThrough()
	if InCombatLockdown() then return end
	Gather()
	local d = Driver()
	local fight = Fighting()
	wipe(listed)
	local n = 0
	for _, f in ipairs(frames) do
		local mode = Mode(f.spClickThroughBar)
		local owner = f.spOwner or f   -- (a flyout arrow: its button's Running Out state)
		local on = mode ~= "always" and not (mode == "combat" and fight) and not owner._roMouseOff
		f:EnableMouse(on)
		if mode ~= "off" then
			listed[#listed + 1] = f
			-- (3.0.9.9) the driver only gets protected frames: in a fight the game refuses a handle to any
			-- other, and that would stop the snippet. The Cooldown Bar's own frame is protected through
			-- its secure buttons; it is checked all the same (the buttons are secure themselves).
			if f ~= SP.cooldownBar or f:IsProtected() then
				n = n + 1
				d:SetFrameRef("spct" .. n, f)
			end
		end
	end
	d:SetAttribute("spctN", n)
	-- the flyouts to shut at the fight's start: the parents under In Combat or Always, and in
	-- box mode each box with its key's toggle (SPFT<K>) and the helper holding its "open" text
	-- (SPFR<K>, see EnsureFlyoutBox in ShamanPower.lua)
	local p, b = 0, 0
	for _, f in ipairs(parents) do
		if Mode(f.spClickThroughBar) ~= "off" then
			p = p + 1
			d:SetFrameRef("spctFly" .. p, f)
			local key
			for k, entry in pairs(SP.boxFlyouts or {}) do
				if entry.button == f then key = k break end
			end
			local box = f.spFlyoutBox
			local toggle, reset = key and _G["SPFT" .. key], key and _G["SPFR" .. key]
			if box and toggle and reset then
				b = b + 1
				d:SetFrameRef("spctBox" .. b, box)
				d:SetFrameRef("spctBoxToggle" .. b, toggle)
				d:SetFrameRef("spctBoxReset" .. b, reset)
			end
		end
	end
	d:SetAttribute("spctFlyouts", p)
	d:SetAttribute("spctBoxes", b)
end

-- the fight's start: a moment before the lock (when it is), the mouse off at once; the driver
-- does the same a frame later, inside the lock. The fight's end: back by the settings
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		if InCombatLockdown() then return end   -- (too late: locked already; the driver has it)
		for _, f in ipairs(listed) do f:EnableMouse(false) end
	elseif SP.opt then
		SP:ApplyClickThrough()
	end
end)

-- the bars are built and rebuilt in many places: after each, one gather (coalesced to a frame)
local function Queue()
	if queued then return end
	queued = true
	C_Timer.After(0, function()
		queued = nil
		if SP.opt and SP.totemButtons then SP:ApplyClickThrough() end
	end)
end
for _, name in ipairs({ "UpdateMiniTotemBar", "CreateTotemFlyout", "CreateShieldFlyout", "CreateWeaponImbueFlyout",
	"CreateEarthShieldFlyout", "UpdateOrCreateESFlyoutButton", "CreateCooldownBar", "RefreshRowsStyle",
	"EnsureCompactShieldButton", "ApplyClickSwap", "UpdateFlyoutClickBehavior", "UpdateCooldownBarPosition" }) do
	if type(SP[name]) == "function" then hooksecurefunc(SP, name, Queue) end
end
