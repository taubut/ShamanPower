-- ============================================================================
-- Controller mode: the pad layer (WoW: Forever only; A19, owner 2026-10-07)
--
-- ShamanPower never keeps Blizzard's pad buttons. While the controller look is on
-- (SP.Controller:IsActive(), ShamanPowerController.lua) it takes ONE button, the
-- layer button (binds.layer, LB to start), and points it at a secure handler.
-- Hold it and the handler's own snippet lays ShamanPower's buttons over the pad:
-- the d-pad = the four totems, A = Drop All, RB = open the totem picker
-- (ShamanPowerControllerPicker.lua). Let go and the snippet clears them, so the
-- d-pad, A and RB are Blizzard's again. Both happen in a secure snippet, so the
-- layer works in fights; the layer button's own binding is set and cleared only
-- out of combat (the look turning on / off, a button changed on the Controller
-- page), and a change in a fight waits for the fight to end.
--
-- Override bindings only: ShamanPower never writes Blizzard's own bindings and
-- never saves anything over them (override bindings are not saved by the game).
-- The look off (or ShamanPower switched off) = every pad binding released.
--
-- Two owners, so letting go of the layer never drops the layer button itself:
--   ShamanPowerControllerLayerKey  (plain frame)  owns the layer button's binding
--   ShamanPowerControllerLayer     (secure)       its _onclick snippet owns the layer
--
-- Saved: SP.opt.controller.binds = { layer, earth, fire, water, air, dropall, picker }
-- (pad key names, Blizzard's own: PADLSHOULDER, PADDUP, PAD1 ...; "" = no button).
-- The Controller page's list (ShamanPower_Config/ControllerButtons.lua) sets them.
-- ============================================================================

local SP = ShamanPower
if not SP then return end
if not (SPCompat and SPCompat.FOREVER) then return end   -- Anniversary has no controller mode

local Pad = {}
SP.ControllerPad = Pad

-- the list's order (the Controller page) and the layer's actions
Pad.ORDER = { "layer", "earth", "fire", "water", "air", "dropall", "picker" }
Pad.ACTIONS = { "earth", "fire", "water", "air", "dropall" }   -- SP.Controller:TargetButton keys
Pad.RECOMMENDED = {
	layer = "PADLSHOULDER",
	earth = "PADDUP", fire = "PADDRIGHT", water = "PADDDOWN", air = "PADDLEFT",
	dropall = "PAD1",
	picker = "PADRSHOULDER",
}
Pad.LABEL = {
	layer = "Hold For ShamanPower's Buttons",
	earth = "Earth Totem", fire = "Fire Totem", water = "Water Totem", air = "Air Totem",
	dropall = "Drop All",
	picker = "Open Totem Picker",
}
Pad.PICKER_BUTTON = "ShamanPowerControllerPickerOpen"   -- (agent PICKER's secure button)

local HANDLER_NAME = "ShamanPowerControllerLayer"
local KEY_OWNER_NAME = "ShamanPowerControllerLayerKey"

-- ---------------------------------------------------------------------------
-- Saved buttons
-- ---------------------------------------------------------------------------
local function BindsTable(create)
	local opt = SP.opt
	if not opt then return nil end
	local c = opt.controller
	if not c then
		if not create then return nil end
		c = {}
		opt.controller = c
	end
	local b = c.binds
	if not b and create then
		b = {}
		c.binds = b
	end
	return b
end

-- The pad key set for an entry of the list, or nil (none). A value never saved
-- falls back to the recommended one (BAR's defaults hold the same table).
function Pad:Get(key)
	local b = BindsTable(false)
	local v = b and b[key]
	if v == nil then v = self.RECOMMENDED[key] end
	if v == "" then return nil end
	return v
end

-- Which entry uses this pad key (layer first), or nil.
function Pad:Owner(padKey)
	if not padKey then return nil end
	for _, key in ipairs(self.ORDER) do
		if self:Get(key) == padKey then return key end
	end
	return nil
end

-- Set one entry's button (nil / "" = none). A button another entry had moves
-- over: that entry takes this one's old button (a swap), so one press is never
-- two things. Out of combat only (returns false in a fight).
function Pad:Set(key, padKey)
	if InCombatLockdown() then return false end
	if not self.RECOMMENDED[key] then return false end
	if padKey == "" then padKey = nil end
	local b = BindsTable(true)
	if not b then return false end
	local old = self:Get(key)
	if padKey and padKey ~= old then
		for _, other in ipairs(self.ORDER) do
			if other ~= key and self:Get(other) == padKey then
				b[other] = old or ""
			end
		end
	end
	b[key] = padKey or ""
	self:Apply()
	return true
end

function Pad:UseRecommended()
	if InCombatLockdown() then return false end
	local b = BindsTable(true)
	if not b then return false end
	for _, key in ipairs(self.ORDER) do b[key] = self.RECOMMENDED[key] end
	self:Apply()
	return true
end

-- Reset: every entry without a button (ShamanPower takes no pad button at all).
function Pad:ClearAll()
	if InCombatLockdown() then return false end
	local b = BindsTable(true)
	if not b then return false end
	for _, key in ipairs(self.ORDER) do b[key] = "" end
	self:Apply()
	return true
end

-- ---------------------------------------------------------------------------
-- Pad key names (for words; the pictures are SP.Controller:Glyph)
-- ---------------------------------------------------------------------------
local NAMES_LETTERS = {
	PAD1 = "A", PAD2 = "B", PAD3 = "X", PAD4 = "Y", PAD5 = "Paddle 5", PAD6 = "Paddle 6",
	PADDUP = "D-pad Up", PADDRIGHT = "D-pad Right", PADDDOWN = "D-pad Down", PADDLEFT = "D-pad Left",
	PADLSHOULDER = "LB", PADRSHOULDER = "RB", PADLTRIGGER = "LT", PADRTRIGGER = "RT",
	PADLSTICK = "Left Stick Press", PADRSTICK = "Right Stick Press",
	PADLSTICKUP = "Left Stick Up", PADLSTICKRIGHT = "Left Stick Right", PADLSTICKDOWN = "Left Stick Down", PADLSTICKLEFT = "Left Stick Left",
	PADRSTICKUP = "Right Stick Up", PADRSTICKRIGHT = "Right Stick Right", PADRSTICKDOWN = "Right Stick Down", PADRSTICKLEFT = "Right Stick Left",
	PADBACK = "View", PADFORWARD = "Menu", PADSYSTEM = "Guide", PADSOCIAL = "Share",
	PADPADDLE1 = "Paddle 1", PADPADDLE2 = "Paddle 2", PADPADDLE3 = "Paddle 3", PADPADDLE4 = "Paddle 4",
}
local NAMES_SHAPES = {
	PAD1 = "Cross", PAD2 = "Circle", PAD3 = "Square", PAD4 = "Triangle",
	PADLSHOULDER = "L1", PADRSHOULDER = "R1", PADLTRIGGER = "L2", PADRTRIGGER = "R2",
	PADLSTICK = "L3", PADRSTICK = "R3", PADBACK = "Create", PADFORWARD = "Options", PADSYSTEM = "PS", PADSOCIAL = "Touchpad",
}

local function LabelStyle()
	if not (C_GamePad and C_GamePad.GetActiveDeviceID and C_GamePad.GetDeviceMappedState) then return nil end
	local ok, state = pcall(function() return C_GamePad.GetDeviceMappedState(C_GamePad.GetActiveDeviceID()) end)
	return ok and type(state) == "table" and state.labelStyle or nil
end

-- "D-pad Up", "A" (Cross on a PlayStation pad), "LB" ...
function Pad:KeyName(padKey)
	if not padKey then return "None" end
	if LabelStyle() == "Shapes" and NAMES_SHAPES[padKey] then return NAMES_SHAPES[padKey] end
	return NAMES_LETTERS[padKey] or (padKey:gsub("^PAD", ""))
end

function Pad:IsPadKey(key)
	return type(key) == "string" and key:match("^PAD") ~= nil
end

-- What Blizzard's own bindings do with this pad key (not ShamanPower's
-- overrides), as words, or nil when the game tells us nothing.
function Pad:BlizzardUse(padKey)
	if not (padKey and GetBindingAction) then return nil end
	local ok, action = pcall(GetBindingAction, padKey)
	if not ok or type(action) ~= "string" or action == "" then return nil end
	if action:match("^CLICK ShamanPower") or action:match("^SHAMANPOWER_") then return nil end
	local text = _G["BINDING_NAME_" .. action]
	if type(text) ~= "string" or text == "" then text = action end
	return text
end

-- In Blizzard's controller mode every d-pad / face / shoulder button already
-- does something for Blizzard (its layout is fixed), even when the bindings
-- above read empty.
function Pad:BlizzardControllerMode()
	if not (C_InputInterfaceStyle and C_InputInterfaceStyle.GetCurrentStyle and Enum and Enum.InputDeviceInterfaceType) then return false end
	local ok, style = pcall(C_InputInterfaceStyle.GetCurrentStyle)
	return ok and style == Enum.InputDeviceInterfaceType.Gamepad or false
end

-- ---------------------------------------------------------------------------
-- The layer (secure)
-- ---------------------------------------------------------------------------
-- self, button, down: down = the layer button pressed, up = let go. Pressed: lay
-- the saved buttons over the pad (the handler's own override bindings, not
-- priority: the owner measured that they win over Blizzard's controller
-- bindings, and a priority binding of the totem picker's own header still wins
-- over them while the picker is open). Let go: clear them all. Only this
-- handler's bindings are touched; the layer button's binding has its own owner.
local LAYER_SNIPPET = [[
	self:ClearBindings()
	if not down then return end
	local n = self:GetAttribute("sp-n") or 0
	for i = 1, n do
		local key = self:GetAttribute("sp-key" .. i)
		local target = self:GetAttribute("sp-target" .. i)
		if key and target then
			self:SetBindingClick(false, key, target, self:GetAttribute("sp-mouse" .. i) or "LeftButton")
		end
	end
]]
Pad.LAYER_SNIPPET = LAYER_SNIPPET

local handler, keyOwner
local slots = 0   -- attribute slots written so far (cleared past n on every write)

local function Build()
	if handler then return true end
	if InCombatLockdown() then return false end
	keyOwner = CreateFrame("Frame", KEY_OWNER_NAME, UIParent)
	local h = CreateFrame("Button", HANDLER_NAME, UIParent, "SecureHandlerClickTemplate")
	h:SetSize(1, 1)
	h:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
	h:EnableMouse(false)
	h:RegisterForClicks("AnyDown", "AnyUp")   -- the binding sends the press AND the let-go
	h:SetAttribute("_onclick", LAYER_SNIPPET)
	h:Hide()   -- (a hidden button still answers its binding)
	handler = h
	Pad.handler, Pad.keyOwner = h, keyOwner
	return true
end

local function Controller() return SP.Controller end

function Pad:Active()
	if SP.IsOff and SP:IsOff() then return false end
	local C = Controller()
	if not (C and C.IsActive) then return false end
	local ok, on = pcall(C.IsActive, C)
	return ok and on and true or false
end

-- The secure button and mouse button an action presses (agent BAR's
-- TargetButton; the mouse button falls back to Keybind Mode's own choice).
local function Target(key)
	local C = Controller()
	if not (C and C.TargetButton) then return nil end
	local ok, btn, mouse = pcall(C.TargetButton, C, key)
	if not ok or not btn then return nil end
	local name = type(btn) == "string" and btn or (btn.GetName and btn:GetName())
	if not name or name == "" or name:find(":", 1, true) then return nil end
	if not mouse then mouse = (SP.KeyMouseButton and SP:KeyMouseButton(name)) or "LeftButton" end
	return name, mouse
end

-- Write the layer's list into the handler (out of combat): n entries of key,
-- target button name and mouse button.
local function WriteLayer(layerKey)
	local n = 0
	local function put(key, target, mouse)
		n = n + 1
		handler:SetAttribute("sp-key" .. n, key)
		handler:SetAttribute("sp-target" .. n, target)
		handler:SetAttribute("sp-mouse" .. n, mouse)
	end
	for _, action in ipairs(Pad.ACTIONS) do
		local padKey = Pad:Get(action)
		if padKey and padKey ~= layerKey then
			local target, mouse = Target(action)
			if target then put(padKey, target, mouse) end
		end
	end
	local pick = Pad:Get("picker")
	if pick and pick ~= layerKey and _G[Pad.PICKER_BUTTON] then put(pick, Pad.PICKER_BUTTON, "LeftButton") end
	for i = n + 1, slots do
		handler:SetAttribute("sp-key" .. i, nil)
		handler:SetAttribute("sp-target" .. i, nil)
		handler:SetAttribute("sp-mouse" .. i, nil)
	end
	slots = math.max(slots, n)
	handler:SetAttribute("sp-n", n)
	return n
end

-- Set (or release) everything. Out of combat only: a call in a fight waits for
-- PLAYER_REGEN_ENABLED. Cheap and idempotent; called on the look turning on /
-- off, a button change, the bars being set up again (SetupKeybindings), a
-- profile change and ShamanPower being switched on / off.
function Pad:Apply()
	self:Wire()
	if InCombatLockdown() then
		self.pending = true
		return false
	end
	self.pending = nil
	local active = self:Active()
	if not handler then
		if not active then return true end   -- never used: nothing to release
		if not Build() then self.pending = true return false end
	end
	local C = Controller()
	if C then C.layerHandler = handler end
	ClearOverrideBindings(keyOwner)
	ClearOverrideBindings(handler)   -- a layer still held when this runs is let go
	self.layerKey = nil
	if not active then
		handler:SetAttribute("sp-n", 0)
		return true
	end
	local layerKey = self:Get("layer")
	local n = WriteLayer(layerKey)
	if layerKey and n > 0 then
		SetOverrideBindingClick(keyOwner, false, layerKey, HANDLER_NAME, "LeftButton")
		self.layerKey = layerKey
	end
	return true
end

-- ---------------------------------------------------------------------------
-- Wiring (at login: every file is loaded by then, so SP.Controller is BAR's)
-- ---------------------------------------------------------------------------
-- Once each (a later SP.Controller table is hooked when it shows up).
local function Reapply() Pad:Apply() end
function Pad:Wire()
	local C = Controller()
	if C and C.OnChange and self.wiredController ~= C then
		self.wiredController = C
		C:OnChange(Reapply)
	end
	if self.wired then return end
	self.wired = true
	-- the bars' buttons, the click swap and the keys are set up again here (out of combat)
	if SP.SetupKeybindings then hooksecurefunc(SP, "SetupKeybindings", Reapply) end
	if SP.OnProfileChanged then hooksecurefunc(SP, "OnProfileChanged", Reapply) end
	if SP.OnOnOff then SP:OnOnOff(Reapply) end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		Pad:Apply()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if Pad.pending then Pad:Apply() end
	end
end)
