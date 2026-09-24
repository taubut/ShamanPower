-- ============================================================================
-- Hover keybind mode (like Bartender's): /sp bind, or General > Main.
--
-- Every ShamanPower button that can take a key gets a highlight with its
-- current key. Hover one and press a key (with Shift / Ctrl / Alt) to bind it;
-- Escape over a button clears its key, Escape anywhere else leaves (keeping the
-- changes). The bar at the top has Done (save) and Cancel (put every key back
-- the way it was when the mode opened).
--
-- Buttons that have one of the addon's own binding actions (Bindings.xml:
-- SHAMANPOWER_EARTH_TOTEM, SHAMANPOWER_CD_NS, ...) are bound to that action,
-- so the existing override-click setup (SetupKeybindings, the click swap) keeps
-- working exactly as with keys set in Blizzard's Key Bindings window. Flyout
-- totems have no action of their own; their buttons have stable global names
-- (ShamanPowerFlyout<element>Btn<index>, ShamanPowerShieldFlyout<i>,
-- ShamanPowerImbueFlyout<i>), so they get a CLICK binding on the mouse button
-- that casts.
--
-- Costs nothing outside the mode: every frame here is made the first time the
-- mode opens, and the only OnUpdate runs while it is open. Out of combat only;
-- a fight starting cancels it (every key put back) before the lockdown begins.
-- ============================================================================

local SP = ShamanPower
if not SP then return end

local GetSpellInfo = GetSpellInfo

local ACTIVE = false
local capture, topBar, topText, hoverLine   -- built on first use
local overlays = {}          -- [button frame] = overlay frame
local entries = {}           -- this session's bindable buttons: { frame, action, label }
local byFrame = {}           -- [button frame] = entry
local changed = {}           -- [key] = the action the key had when the mode opened ("" = none)
local hovered                -- entry under the mouse

local ELEMENT_NAMES = { "Earth", "Fire", "Water", "Air" }
local CD_ACTION = {}         -- cooldownType -> SHAMANPOWER_CD_* action (from the core's table)

local function isShaman() return select(2, UnitClass("player")) == "SHAMAN" end

local function shortKey(key)
	if not key then return nil end
	key = key:gsub("CTRL%-", "C-"):gsub("ALT%-", "A-"):gsub("SHIFT%-", "S-")
	key = key:gsub("NUMPAD", "N"):gsub("BUTTON", "M"):gsub("MOUSEWHEELUP", "MWU"):gsub("MOUSEWHEELDOWN", "MWD")
	return key
end

-- ---------------------------------------------------------------------------
-- What can be bound
-- ---------------------------------------------------------------------------
local function add(frame, action, label)
	if not frame or byFrame[frame] then return end
	local e = { frame = frame, action = action, label = label }
	entries[#entries + 1] = e
	byFrame[frame] = e
end

-- The cast click of a flyout totem button (the other click assigns it).
local function flyoutCastButton()
	return SP.opt and SP.opt.swapFlyoutClickButtons and "RightButton" or "LeftButton"
end

local function collect()
	wipe(entries); wipe(byFrame)
	for bindingName, cdType in pairs(SP.CooldownBarKeybinds or {}) do CD_ACTION[cdType] = bindingName end

	-- totem bar: the four element buttons and Drop All
	for element = 1, 4 do
		add(_G["ShamanPowerTotemBtn" .. element], "SHAMANPOWER_" .. ELEMENT_NAMES[element]:upper() .. "_TOTEM",
			"Assigned " .. ELEMENT_NAMES[element] .. " totem")
	end
	add(_G["ShamanPowerAutoDropAll"], "SHAMANPOWER_DROPALL", "Drop All")
	add(_G["ShamanPowerEarthShieldBtn"], "SHAMANPOWER_EARTH_SHIELD", "Earth Shield")

	-- cooldown bar (and Totemic Call when it sits on the totem bar): the types
	-- with a binding action. The rest (Shamanistic Rage, Elemental Mastery, Rage
	-- of the Farseer, Totemic Projection) have none, and their button names
	-- follow the bar's order, so a CLICK binding would move with a reorder.
	for cdType, action in pairs(CD_ACTION) do
		local btn = SP.GetCooldownButtonByCooldownType and SP:GetCooldownButtonByCooldownType(cdType)
		if btn then add(btn, action, _G["BINDING_NAME_" .. action] or action) end
	end

	-- flyout totems (named buttons; the Empty button at index 0 is not a cast)
	local cast = flyoutCastButton()
	for element = 1, 4 do
		local flyout = SP.totemFlyouts and SP.totemFlyouts[element]
		for _, btn in ipairs(flyout and flyout.allButtons or {}) do
			local name = btn:GetName()
			if name and btn.totemIndex and btn.totemIndex > 0 then
				local spell = btn.spellID and GetSpellInfo(btn.spellID) or btn:GetAttribute("mySpell")
				add(btn, "CLICK " .. name .. ":" .. cast, spell or (ELEMENT_NAMES[element] .. " flyout totem"))
			end
		end
	end
	for _, flyout in ipairs({ SP.shieldFlyout, SP.weaponImbueFlyout }) do
		for _, btn in ipairs(flyout and flyout.buttons or {}) do
			local name = btn:GetName()
			if name then
				local spell = btn.spellName or (btn.spellID and GetSpellInfo(btn.spellID))
				add(btn, "CLICK " .. name .. ":LeftButton", spell or name)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Binding changes (every key touched is remembered for Cancel)
-- ---------------------------------------------------------------------------
local function remember(key)
	if changed[key] == nil then changed[key] = GetBindingAction(key) or "" end
end

local function clearAction(action)
	local keys = { GetBindingKey(action) }
	for _, key in ipairs(keys) do
		remember(key)
		SetBinding(key)
	end
end

local function bindKey(entry, key)
	local previous = GetBindingAction(key)
	clearAction(entry.action)          -- one key per button: the new key replaces the old
	remember(key)
	local ok
	if entry.action:find("^CLICK ") then
		local name, mouse = entry.action:match("^CLICK (.-):(.+)$")
		ok = SetBindingClick(key, name, mouse)
	else
		ok = SetBinding(key, entry.action)
	end
	if ok and previous and previous ~= "" and previous ~= entry.action then
		local was = GetBindingText and GetBindingText(previous, "BINDING_NAME_") or previous
		print("|cff0070ddShamanPower|r: " .. key .. " was " .. tostring(was) .. "; it now casts " .. entry.label .. ".")
	end
end

local function restore()
	for key, action in pairs(changed) do
		if action == "" then SetBinding(key) else SetBinding(key, action) end
	end
	wipe(changed)
end

-- ---------------------------------------------------------------------------
-- Overlays
-- ---------------------------------------------------------------------------
local function overlayFor(frame)
	local o = overlays[frame]
	if o then return o end
	o = CreateFrame("Frame", nil, UIParent)
	o:EnableMouse(false)   -- the button underneath keeps its hover (flyouts still open)
	o.bg = o:CreateTexture(nil, "OVERLAY")
	o.bg:SetAllPoints(o)
	o.edges = {}
	for i = 1, 4 do o.edges[i] = o:CreateTexture(nil, "OVERLAY", nil, 1) end
	o.edges[1]:SetPoint("TOPLEFT"); o.edges[1]:SetPoint("TOPRIGHT"); o.edges[1]:SetHeight(2)
	o.edges[2]:SetPoint("BOTTOMLEFT"); o.edges[2]:SetPoint("BOTTOMRIGHT"); o.edges[2]:SetHeight(2)
	o.edges[3]:SetPoint("TOPLEFT"); o.edges[3]:SetPoint("BOTTOMLEFT"); o.edges[3]:SetWidth(2)
	o.edges[4]:SetPoint("TOPRIGHT"); o.edges[4]:SetPoint("BOTTOMRIGHT"); o.edges[4]:SetWidth(2)
	o.key = o:CreateFontString(nil, "OVERLAY", nil, 2)
	SP:SetSPFont(o.key, "labels", 11, "OUTLINE")
	o.key:SetPoint("CENTER", o, "CENTER", 0, 0)
	o.key:SetTextColor(1, 1, 1)
	overlays[frame] = o
	return o
end

local function paintOverlay(e)
	local o = overlayFor(e.frame)
	local lit = (hovered == e)
	o.bg:SetColorTexture(0.25, 0.55, 1, lit and 0.45 or 0.2)
	for _, t in ipairs(o.edges) do t:SetColorTexture(lit and 1 or 0.3, lit and 0.82 or 0.65, lit and 0 or 1, 1) end
	o.key:SetText(shortKey((GetBindingKey(e.action))) or "")
end

local function refreshOverlays()
	for _, e in ipairs(entries) do
		local o = overlayFor(e.frame)
		if e.frame:IsVisible() then
			o:ClearAllPoints()
			o:SetAllPoints(e.frame)
			o:SetFrameStrata("TOOLTIP")
			paintOverlay(e)
			o:Show()
		else
			o:Hide()
		end
	end
end

local function hideOverlays()
	for _, o in pairs(overlays) do o:Hide() end
end

-- ---------------------------------------------------------------------------
-- Hover and keys
-- ---------------------------------------------------------------------------
local function entryUnderMouse()
	local list = (GetMouseFoci and GetMouseFoci()) or { GetMouseFocus and GetMouseFocus() }
	for _, f in ipairs(list) do
		local depth = 0
		while f and depth < 6 do
			local e = byFrame[f]
			if e and f:IsVisible() then return e end
			f = f.GetParent and f:GetParent()
			depth = depth + 1
		end
	end
	return nil
end

local function setHoverLine()
	if hovered then
		local key = shortKey((GetBindingKey(hovered.action)))
		hoverLine:SetText(hovered.label .. (key and ("  |cffffd200" .. key .. "|r") or "  |cff8a94a6(no key)|r"))
	else
		hoverLine:SetText("|cff8a94a6Hover a highlighted button|r")
	end
end

local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
	LMETA = true, RMETA = true, UNKNOWN = true }

local Leave   -- forward

local function onKey(_, key)
	if MODIFIER_KEYS[key] then return end
	if key == "ESCAPE" then
		if hovered then
			clearAction(hovered.action)
			refreshOverlays(); setHoverLine()
		else
			Leave(true)
		end
		return
	end
	if not hovered then return end
	local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
	bindKey(hovered, combo)
	refreshOverlays(); setHoverLine()
end

-- ---------------------------------------------------------------------------
-- The mode
-- ---------------------------------------------------------------------------
local function build()
	if capture then return end
	capture = CreateFrame("Frame", "ShamanPowerKeybindCapture", UIParent)
	capture:SetAllPoints(UIParent)
	capture:SetFrameStrata("TOOLTIP")
	capture:EnableMouse(false)
	capture:Hide()
	capture:SetScript("OnKeyDown", onKey)
	local acc = 0
	capture:SetScript("OnUpdate", function(_, elapsed)
		acc = acc + elapsed
		if acc < 0.05 then return end
		acc = 0
		local e = entryUnderMouse()
		if e ~= hovered then
			local old = hovered
			hovered = e
			if old then paintOverlay(old) end
			if e then paintOverlay(e) end
			setHoverLine()
		end
		-- flyouts open and close as the mouse moves: keep their highlights in step
		for _, en in ipairs(entries) do
			local o = overlays[en.frame]
			local vis = en.frame:IsVisible()
			if o and o:IsShown() ~= vis then refreshOverlays() break end
		end
	end)
	capture:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			SP.keybindReturnToConfig = nil   -- no settings window popping up as the fight starts
			Leave(false, "a fight started, so every key is back the way it was.")
		end
	end)

	topBar = CreateFrame("Frame", "ShamanPowerKeybindBar", UIParent, "BackdropTemplate")
	topBar:SetSize(620, 74)
	topBar:SetPoint("TOP", UIParent, "TOP", 0, -40)
	topBar:SetFrameStrata("TOOLTIP")
	topBar:SetFrameLevel(50)
	topBar:EnableMouse(true)
	if topBar.SetBackdrop then
		topBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		topBar:SetBackdropColor(0.07, 0.08, 0.1, 0.95)
		topBar:SetBackdropBorderColor(0.2, 0.55, 1, 1)
	end
	topText = topBar:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(topText, "labels", 12, "")
	topText:SetPoint("TOPLEFT", topBar, "TOPLEFT", 12, -10)
	topText:SetPoint("RIGHT", topBar, "RIGHT", -190, 0)
	topText:SetJustifyH("LEFT"); topText:SetWordWrap(true)
	topText:SetTextColor(0.9, 0.92, 0.95)
	topText:SetText("|cff3fa9f5Keybind mode|r - hover a button and press a key (Shift / Ctrl / Alt work). Esc over a button clears its key; Esc elsewhere leaves and keeps your keys.")
	hoverLine = topBar:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(hoverLine, "labels", 12, "")
	hoverLine:SetPoint("TOPLEFT", topText, "BOTTOMLEFT", 0, -6)
	hoverLine:SetPoint("RIGHT", topBar, "RIGHT", -190, 0)
	hoverLine:SetJustifyH("LEFT"); hoverLine:SetWordWrap(true)

	local done = SP:CreateSPButton(topBar, "Done", 80, true)
	done:SetPoint("RIGHT", topBar, "RIGHT", -12, 0)
	done:SetScript("OnClick", function() Leave(true) end)
	local cancel = SP:CreateSPButton(topBar, "Cancel", 80, false)
	cancel:SetPoint("RIGHT", done, "LEFT", -8, 0)
	cancel:SetScript("OnClick", function() Leave(false) end)
	topBar:Hide()
end

local function fitBar()
	local h = 10 + topText:GetStringHeight() + 6 + hoverLine:GetStringHeight() + 12
	topBar:SetHeight(math.max(56, h))
end

-- Hide Out of Combat and Hide When No Totems really hide the totem bar, and the
-- mode is out of combat only: put back on screen what that rule hid (the same
-- pieces it shows) for the length of the mode. On leaving, the rule decides
-- again from scratch.
local barShown = false
local function showHiddenTotemBar()
	if not (SP.totemBarHidden and SP.autoButton and SP.opt) then return end
	if SP.UsingBlizzardTotemBar and SP:UsingBlizzardTotemBar() then return end
	if SP.TotemBarEnabled and not SP:TotemBarEnabled() then return end
	SP.autoButton:Show()
	for element = 1, 4 do
		local btn = SP.totemButtons and SP.totemButtons[element]
		if btn then btn:Show() end
	end
	local dropAll = _G["ShamanPowerAutoDropAll"]
	if dropAll and SP.opt.showDropAllButton ~= false then dropAll:Show() end
	local es = _G["ShamanPowerEarthShieldBtn"]
	if es and SP.HasEarthShield and SP:HasEarthShield() then es:Show() end
	barShown = true
end

function Leave(save, why)
	if not ACTIVE then return end
	ACTIVE = false
	if save then
		wipe(changed)
		SaveBindings(GetCurrentBindingSet())
	else
		restore()
	end
	hovered = nil
	capture:UnregisterEvent("PLAYER_REGEN_DISABLED")
	capture:EnableKeyboard(false)
	capture:Hide()
	topBar:Hide()
	hideOverlays()
	-- a fight starting lands here before the lockdown, so the bar can still hide
	if barShown then
		barShown = false
		if SP.UpdateTotemBarVisibility then SP:UpdateTotemBarVisibility(true) end
	end
	if why then print("|cff0070ddShamanPower|r: keybind mode closed - " .. why) end
	-- the addon's override clicks and key labels follow the new bindings
	if SP.SetupKeybindings then SP:SetupKeybindings() end
	if SP.QueueKeybindTextRefresh then SP:QueueKeybindTextRefresh() end
	if SP.keybindReturnToConfig then
		SP.keybindReturnToConfig = nil
		-- the same page, tab and scroll it was hidden on (ShamanPowerUnlock.lua)
		if SP.ReopenSettingsWindow then
			SP:ReopenSettingsWindow()
		else
			local cfg = rawget(_G, "ShamanPowerConfig")
			if cfg and cfg.Open then pcall(cfg.Open, cfg) end
		end
	end
end

function SP:KeybindModeActive() return ACTIVE end

function SP:SetKeybindMode(on)
	if not on then Leave(true) return end
	if ACTIVE then return end
	if not isShaman() then print("|cff0070ddShamanPower|r: keybind mode is for shamans (their totem and cooldown buttons).") return end
	if InCombatLockdown() then print("|cff0070ddShamanPower|r: keybind mode opens out of combat.") return end
	build()
	collect()
	if #entries == 0 then print("|cff0070ddShamanPower|r: no ShamanPower buttons to bind right now (is the totem bar shown?).") return end
	ACTIVE = true
	wipe(changed)
	hovered = nil
	-- our own windows would sit on top of the buttons
	local cfg = _G["ShamanPowerConfigUIFrame"]
	if cfg and cfg:IsShown() then cfg:Hide(); SP.keybindReturnToConfig = true end
	showHiddenTotemBar()
	capture:RegisterEvent("PLAYER_REGEN_DISABLED")
	capture:Show()
	capture:EnableKeyboard(true)
	capture:SetPropagateKeyboardInput(false)
	topBar:Show()
	setHoverLine()
	fitBar()
	refreshOverlays()
end

function SP:ToggleKeybindMode() self:SetKeybindMode(not ACTIVE) end

-- ---------------------------------------------------------------------------
-- Flyout totems bound here have CLICK bindings, which the core's flyout label
-- pass (action bar keys only) does not know about: show those keys too.
-- ---------------------------------------------------------------------------
hooksecurefunc(SP, "UpdateFlyoutKeybindText", function(self, enabled)
	if not enabled then return end
	local cast = flyoutCastButton()
	local function label(btn, mouse)
		if not (btn and btn.keybindText) or (btn.keybindText:IsShown() and btn.keybindText:GetText() ~= "") then return end
		local name = btn:GetName()
		local key = name and GetBindingKey("CLICK " .. name .. ":" .. mouse)
		if key then
			btn.keybindText:SetText(shortKey(key))
			btn.keybindText:Show()
		end
	end
	for element = 1, 4 do
		local flyout = self.totemFlyouts and self.totemFlyouts[element]
		for _, btn in ipairs(flyout and flyout.allButtons or {}) do label(btn, cast) end
	end
	for _, flyout in ipairs({ self.shieldFlyout, self.weaponImbueFlyout }) do
		for _, btn in ipairs(flyout and flyout.buttons or {}) do label(btn, "LeftButton") end
	end
end)

SLASH_SPBIND1 = "/spbind"
SlashCmdList["SPBIND"] = function() SP:ToggleKeybindMode() end

-- General > Main: the button (next to Unlock UI)
do
	local settings = SP.options and SP.options.args and SP.options.args.settings
	local main = settings and settings.args and settings.args.settings_show
	if main and main.args then
		main.args.keybind_mode = {
			order = 0.25,
			type = "execute",
			name = "Keybind Mode (hover and press a key)",
			desc = "Highlights every ShamanPower button that can take a key: the totem bar, Drop All, the cooldown bar and the flyout totems. Hover one and press a key (Shift, Ctrl and Alt work) to bind it; Escape over a button clears its key. Done saves, Cancel puts every key back. Out of combat only. Also: /sp bind",
			hidden = function() return not isShaman() end,
			func = function() SP:SetKeybindMode(true) end,
		}
	end
end

-- Appearance > Visibility: the same button beside "Show Keybinds on Buttons",
-- where players look for anything about keys
do
	local vis = SP.options and SP.options.args and SP.options.args.fluffy
		and SP.options.args.fluffy.args.visibility_section
	if vis and vis.args then
		vis.args.keybind_mode = {
			order = 4.1,
			type = "execute",
			name = "Keybind Mode (hover and press a key)",
			desc = "Hides this window and highlights every ShamanPower button that can take a key. Hover one and press a key to bind it; Done or Cancel brings this window back. Also: /sp bind",
			hidden = function() return not isShaman() end,
			func = function() SP:SetKeybindMode(true) end,
		}
	end
end
