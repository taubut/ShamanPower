-- ShamanPowerControllerCooldowns.lua
-- Controller mode (3.0.8 alpha, A19b), WoW: Forever only: your cooldowns in the
-- controller look. Show My Cooldowns (Bars > Controller):
--   On The Controller Bar: Controller Layout puts the first four items of the
--     Cooldown Bar (its order, only items shown on it) in the cross's four diagonal
--     corners, small, and the rest in a small row under the cross; Round Slots In A
--     Row / Square put them all in a smaller row above the totems.
--   Separate: a frame of its own (own spot, own Size, own Unlock UI box) with its
--     own Cooldown Layout: Cross (four around a fifth in the middle, the rest in a
--     small row under) or Row.
-- Display and mouse only: no pad buttons. Each slot is a secure "click" slot that
-- presses the REAL cooldown bar button (the controller bar's wiring, with its
-- ActionButtonUseKeyDown wrap: SP.Controller:WireClick), set up out of combat only.
--
-- What a slot shows is what its real button shows, mirrored from it: its icon and
-- gray, the dark "missing" shade, the cooldown (the same Cooldown calls, so the game
-- draws the sweep and its numbers from the same duration object in fights), the
-- addon's own time text and the shield's charge count (copied at the end of the
-- cooldown bar's own pass), and the Cooldown Ready gold when a cooldown comes back
-- (the item's own Cooldown Ready effect). In a fight on WoW: Forever the shield's
-- charges are drawn by the game, as on the real button: a game-drawn layer of our
-- own, shown exactly while the real button's is. Nothing polls: hooks on the real
-- button and on the cooldown bar's pass, which already sleeps when nothing changes.
--
-- Hide The Cooldown Bar While This Shows (on to start): the normal cooldown bar
-- hides while these show (ShamanPower.lua UpdateCooldownBar asks
-- SP:ControllerHidesCooldownBar); its pass keeps running, its hidden buttons keep
-- working for their keys and for these slots. Shown / hidden / moved / resized out
-- of combat only; a change during a fight waits for its end.

local SP = ShamanPower
if not SP then return end
if not (SPCompat and SPCompat.FOREVER) then return end   -- (Anniversary: nothing new)
local C = SP.Controller
if not C then return end

local isSecret = issecretvalue or function() return false end
local TEX = "Interface\\AddOns\\ShamanPower\\Media\\Textures\\"
local MASK_CIRCLE = TEX .. "Mask_Circle"
local RING = TEX .. "Ring_Circle_5"
local GLOW = TEX .. "Ring_Circle_8"

-- sizes in UI units before Size: the controller bar's 40-unit totem slot and 46 step;
-- a small cooldown is 0.52 of a totem slot, the corners 0.82 of the step out (A19b)
local SLOT, STEP = C.SLOT or 40, C.STEP or 46
local SMALL = math.floor(SLOT * 0.52 + 0.5)   -- 21
local SMALL_STEP = SMALL + 5
local DIAG = STEP * 0.82
local GAP = 8                                 -- between the totems (and their pad pictures) and a small row
local DEFAULT_POSITION = { anchor = "CENTER", x = -230, y = -280 }   -- (to the right of the controller bar)

local function O() return SP.opt and SP.opt.controller end
local function Mode()
	local o = O()
	local v = o and o.cooldowns
	if v == "bar" or v == "separate" then return v end
	return "off"
end

-- WoW's gold (each client's NORMAL_FONT_COLOR): the Cooldown Ready gold
local GOLD = { 1, 0.82, 0 }
do
	local c = NORMAL_FONT_COLOR
	if c and c.GetRGB then
		local ok, r, g, b = pcall(c.GetRGB, c)
		if ok and type(r) == "number" then GOLD[1], GOLD[2], GOLD[3] = r, g, b end
	end
end

-- ---------------------------------------------------------------------------
-- Which items: the Cooldown Bar's buttons in its order, only those shown on it
-- ---------------------------------------------------------------------------
local items = {}   -- real cooldown bar buttons, in order (rebuilt out of combat only)

local function ItemShown(btn)
	if not btn or btn.isHiddenInOptions then return false end
	local po = SP.opt and SP.opt.poppedOut
	if po and btn.cooldownType and po["cd_" .. btn.cooldownType] then return false end   -- popped out: not on the bar
	return true
end

local function Collect()
	wipe(items)
	if not (SP.opt and SP.opt.showCooldownBar) or SP:IsOff() then return items end
	local list = SP.cooldownButtons
	if not list or #list == 0 then return items end
	local order = SP.GetCooldownBarOrder and SP:GetCooldownBarOrder() or {}
	local used = {}
	for _, t in ipairs(order) do
		for i = 1, #list do
			local b = list[i]
			if b.cooldownType == t and not used[b] then
				used[b] = true
				if ItemShown(b) then items[#items + 1] = b end
			end
		end
	end
	for i = 1, #list do   -- anything the order never named, at the end
		local b = list[i]
		if not used[b] and ItemShown(b) then items[#items + 1] = b end
	end
	return items
end

-- ---------------------------------------------------------------------------
-- The slots
-- ---------------------------------------------------------------------------
local slots = {}     -- pooled secure slots, ShamanPowerControllerCD1..n
local slotOf = setmetatable({}, { __mode = "k" })   -- real button -> its slot now
local hooked = setmetatable({}, { __mode = "k" })
local cdFrame        -- the Separate frame
local shownN = 0     -- slots on screen now
local live = false   -- on screen because the controller look is on (not an Unlock UI preview)
local demo = false   -- Unlock UI: the Separate frame on screen to be moved
local pending = false
C.cdSlot = slots

local function SlotTooltip(s)
	local real = s.real
	if not (real and GameTooltip) then return end
	if SP.opt and SP.opt.ShowTooltips == false then return end
	GameTooltip:SetOwner(s, "ANCHOR_TOP")
	local id = real.spellID
	local shown = false
	if real.spellType ~= "shield" and type(id) == "number" and GameTooltip.SetSpellByID then
		shown = pcall(GameTooltip.SetSpellByID, GameTooltip, SPCompat.HighestKnownRank and SPCompat.HighestKnownRank(id) or id)
	end
	if not shown then GameTooltip:SetText(real.spellName or (real.cooldownType == 7 and "Weapon Imbue") or "Shield", 1, 1, 1) end
	GameTooltip:AddLine("Click: the same as this button on your cooldown bar.", 0.8, 0.8, 0.8, true)
	GameTooltip:Show()
end

local function MakeSlot(i)
	local s = CreateFrame("Button", "ShamanPowerControllerCD" .. i, UIParent, "SecureActionButtonTemplate")
	s:SetSize(SMALL, SMALL)
	s:RegisterForClicks("LeftButtonUp", "RightButtonUp")   -- (a middle-click would pop the item out of the bar)
	s:SetAttribute("type", "click")
	s:SetAttribute("useOnKeyDown", false)   -- acts on the release (C:WireClick's wrap)
	s:Hide()

	-- the round plate, the icon (masked to a circle), a hover light
	s.plate = s:CreateTexture(nil, "BACKGROUND")
	s.plate:SetTexture(MASK_CIRCLE)
	s.plate:SetVertexColor(0.04, 0.05, 0.06, 0.85)
	s.icon = s:CreateTexture(nil, "ARTWORK")
	s.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	s.iconMask = s:CreateMaskTexture()
	s.iconMask:SetAllPoints(s.icon)
	s.iconMask:SetTexture(MASK_CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	s.icon:AddMaskTexture(s.iconMask)
	s.dark = s:CreateTexture(nil, "ARTWORK", nil, 2)   -- the real button's "missing" shade
	s.dark:SetAllPoints(s.icon)
	s.dark:SetColorTexture(0, 0, 0, 0.6)
	s.dark:AddMaskTexture(s.iconMask)
	s.dark:Hide()
	s.hl = s:CreateTexture(nil, "HIGHLIGHT")
	s.hl:SetAllPoints(s.icon)
	s.hl:SetColorTexture(1, 1, 1, 0.15)
	s.hl:AddMaskTexture(s.iconMask)

	-- the cooldown: the game draws the sweep (and its numbers when the real button's show)
	s.cd = CreateFrame("Cooldown", nil, s, "CooldownFrameTemplate")
	s.cd:SetAllPoints(s.icon)
	s.cd:SetDrawEdge(false)
	if s.cd.SetDrawBling then s.cd:SetDrawBling(false) end
	s.cd:SetSwipeTexture(MASK_CIRCLE)
	s.cd:SetSwipeColor(0, 0, 0, 0.6)
	s.cd:SetHideCountdownNumbers(true)

	-- the ring and the Cooldown Ready gold
	s.ringFrame = CreateFrame("Frame", nil, s)
	s.ringFrame:SetAllPoints(s)
	s.ringFrame:SetFrameLevel(s.cd:GetFrameLevel() + 1)
	s.track = s.ringFrame:CreateTexture(nil, "ARTWORK")
	s.track:SetAllPoints(s)
	s.track:SetTexture(RING)
	s.glow = s.ringFrame:CreateTexture(nil, "OVERLAY")
	s.glow:SetTexture(GLOW)
	s.glow:SetBlendMode("ADD")
	s.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	s.glow:SetAlpha(0)   -- only the animation lights it
	s.glowAnim = s.glow:CreateAnimationGroup()
	local a1 = s.glowAnim:CreateAnimation("Alpha")
	a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(0.15); a1:SetOrder(1)
	local a2 = s.glowAnim:CreateAnimation("Alpha")
	a2:SetFromAlpha(1); a2:SetToAlpha(1); a2:SetDuration(0.6); a2:SetOrder(2)
	local a3 = s.glowAnim:CreateAnimation("Alpha")
	a3:SetFromAlpha(1); a3:SetToAlpha(0); a3:SetDuration(1.4); a3:SetOrder(3)
	-- a cooldown that ends by itself (never one the bar clears): ready again
	s.cd:HookScript("OnCooldownDone", function()
		local real = s.real
		if real and real.spellType ~= "shield" and real.cooldownType ~= 7 and SP:CdItemOpt(real.cooldownType, "cueReady") then
			s.glowAnim:Stop(); s.glowAnim:Play()
		end
	end)

	-- the time and the shield's charges, over everything
	s.top = CreateFrame("Frame", nil, s)
	s.top:SetAllPoints(s)
	s.top:SetFrameLevel(s.ringFrame:GetFrameLevel() + 4)
	s.time = s.top:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(s.time, "timers", 9, "OUTLINE")
	s.time:SetPoint("CENTER", s, "CENTER", 0, 0)
	s.time:SetTextColor(1, 1, 1)
	s.count = s.top:CreateFontString(nil, "OVERLAY")
	SP:SetSPFont(s.count, "charges", 9, "OUTLINE")
	s.count:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 1, -1)

	s:SetScript("OnEnter", SlotTooltip)
	s:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	slots[i] = s
	return s
end

-- a slot's size: small (corners, the small rows) or a totem slot's (Separate)
local function SizeSlot(s, size)
	if s.size == size then return end
	s.size = size
	s:SetSize(size, size)
	local plate = math.max(1, size * 0.05)
	s.plate:ClearAllPoints()
	s.plate:SetPoint("TOPLEFT", -plate, plate); s.plate:SetPoint("BOTTOMRIGHT", plate, -plate)
	local inset = size * 0.1
	s.icon:ClearAllPoints()
	s.icon:SetPoint("TOPLEFT", inset, -inset); s.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
	local g = size * 0.12
	s.glow:ClearAllPoints()
	s.glow:SetPoint("TOPLEFT", -g, g); s.glow:SetPoint("BOTTOMRIGHT", g, -g)
	local small = size < SLOT * 0.75
	local fsize = small and 8 or 13
	SP:SetSPFont(s.time, "timers", fsize, "OUTLINE")
	SP:SetSPFont(s.count, "charges", small and 8 or 12, "OUTLINE")
	local ok, nums = pcall(s.cd.GetCountdownFontString, s.cd)
	if ok and nums then SP:SetSPFont(nums, "timers", fsize, "OUTLINE") end
	if s.engineCount then SP:SetSPFont(s.engineCount, "charges", small and 8 or 12, "OUTLINE") end
end

-- ---------------------------------------------------------------------------
-- Mirroring the real button (hooks: they run only when the bar changes it)
-- ---------------------------------------------------------------------------
local function MirrorIcon(s, tex)
	if tex == nil then return end
	if isSecret(tex) then s.iconTex = nil; s.icon:SetTexture(tex) return end
	if s.iconTex == tex then return end
	s.iconTex = tex
	s.icon:SetTexture(tex)
end
local function MirrorDesat(s, on)
	if on == nil or isSecret(on) then return end
	s.icon:SetDesaturated(on and true or false)
end

local function Owner(real)
	local s = slotOf[real]
	if s and s.real == real and s:IsShown() then return s end
	return nil
end

local function HookReal(real)
	if hooked[real] then return end
	hooked[real] = true
	if real.icon then
		hooksecurefunc(real.icon, "SetTexture", function(_, tex) local s = Owner(real); if s then MirrorIcon(s, tex) end end)
		hooksecurefunc(real.icon, "SetDesaturated", function(_, on) local s = Owner(real); if s then MirrorDesat(s, on) end end)
	end
	if real.darkOverlay then
		hooksecurefunc(real.darkOverlay, "Show", function() local s = Owner(real); if s then s.dark:Show() end end)
		hooksecurefunc(real.darkOverlay, "Hide", function() local s = Owner(real); if s then s.dark:Hide() end end)
	end
	local cd = real.cooldown
	if cd then
		-- the same calls with the same values (a duration object in fights): the game draws both
		hooksecurefunc(cd, "SetCooldown", function(_, start, dur)
			local s = Owner(real); if s then pcall(s.cd.SetCooldown, s.cd, start, dur) end
		end)
		if cd.SetCooldownFromDurationObject then
			hooksecurefunc(cd, "SetCooldownFromDurationObject", function(_, d, clearIfZero)
				local s = Owner(real); if s then pcall(s.cd.SetCooldownFromDurationObject, s.cd, d, clearIfZero) end
			end)
		end
		hooksecurefunc(cd, "Clear", function() local s = Owner(real); if s then s.cd:Clear() end end)
		hooksecurefunc(cd, "SetHideCountdownNumbers", function(_, hide)
			local s = Owner(real); if s then s.cd:SetHideCountdownNumbers(hide and true or false) end
		end)
	end
end

-- The shield's charges in a fight on WoW: Forever: the game draws them (auras are secret),
-- as on the real button. A game-drawn layer of our own (one slot per shield, built out of
-- combat), shown exactly while the real button's is.
local function ShieldLayer(s)
	if s.auraC or not (SPCompat.secretsRegime and SP.ShieldAuraSets) then return end
	if InCombatLockdown() then return end
	if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, s, "CustomAuraContainerTemplate")
	if not ok or not c then return end
	c:SetAllPoints(s)
	c:SetFrameLevel(s.ringFrame:GetFrameLevel() + 2)
	local ct = 1
	local chargeCount = SP:CdItemOpt(ct, "chargeCount")
	for _, set in ipairs(SP.ShieldAuraSets) do
		local idMap, iconFile = {}, nil
		for _, id in ipairs(set.ids) do
			idMap[id] = true
			iconFile = iconFile or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id))
		end
		pcall(c.AddAuraSlot, c, "ctrl_" .. set.name:gsub("%s", ""), "HELPFUL|PLAYER", {
			candidateFilters = { includeSpellIDs = idMap },
			initializeFrame = function(button)
				button:ClearAllPoints()
				button:SetAllPoints(s)
				if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
				if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
				local icon = button:CreateTexture(nil, "ARTWORK")
				icon:SetAllPoints(s.icon)
				icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
				if iconFile then icon:SetTexture(iconFile) end
				local mask = button:CreateMaskTexture()
				mask:SetAllPoints(s.icon)
				mask:SetTexture(MASK_CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
				icon:AddMaskTexture(mask)
				pcall(button.SetIcon, button, icon)
				local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
				cd:SetAllPoints(s.icon)
				cd:SetDrawEdge(false)
				cd:SetDrawBling(false)
				cd:SetHideCountdownNumbers(true)
				cd:SetSwipeTexture(MASK_CIRCLE)
				cd:SetSwipeColor(0, 0, 0, 0.7)
				cd:SetDrawSwipe(SP:CdItemOpt(ct, "sweep") ~= "none")
				pcall(button.SetDurationCooldown, button, cd)
				if chargeCount then
					local texts = CreateFrame("Frame", nil, button)
					texts:SetAllPoints(s)
					texts:SetFrameLevel(s.top:GetFrameLevel() + 1)
					local count = texts:CreateFontString(nil, "OVERLAY")
					SP:SetSPFont(count, "charges", (s.size or SMALL) < SLOT * 0.75 and 8 or 12, "OUTLINE")
					if SP.SPFontGameOwned then SP:SPFontGameOwned(count) end
					count:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 1, -1)
					count:SetTextColor(1, 1, 1)
					local fmt = SP.ShieldCountFormatter and SP:ShieldCountFormatter(3, ct)
					pcall(button.SetApplicationCount, button, count, { formatter = fmt })
					s.engineCount = count
				end
			end,
		})
	end
	pcall(c.SetUnit, c, "player")
	pcall(c.UpdateAllAuras, c)
	c:Hide()
	s.auraC = c
end

local hookedContainer = setmetatable({}, { __mode = "k" })
local function FollowShieldContainer(s, real)
	local rc = real and real.chargeContainer
	if not (rc and s.auraC) then if s.auraC then s.auraC:Hide() end return end
	if not hookedContainer[rc] then
		hookedContainer[rc] = true
		local function follow()
			local slot = Owner(real)
			if slot and slot.auraC then slot.auraC:SetShown(rc:IsShown()) end
		end
		hooksecurefunc(rc, "Show", follow)
		hooksecurefunc(rc, "Hide", follow)
		hooksecurefunc(rc, "SetShown", follow)
	end
	s.auraC:SetShown(rc:IsShown())
end

-- the slot takes its real button now (out of combat)
local function Wire(s, real)
	if s.real and s.real ~= real and slotOf[s.real] == s then slotOf[s.real] = nil end
	s.real = real
	slotOf[real] = s
	C:WireClick(s, real)
	HookReal(real)
	-- the state it shows now; the cooldown comes again with the bar's next pass (below)
	s.iconTex = nil
	if real.icon then
		local ok, tex = pcall(real.icon.GetTexture, real.icon)
		if ok then MirrorIcon(s, tex) end
		local okD, desat = pcall(real.icon.IsDesaturated, real.icon)
		if okD then MirrorDesat(s, desat) end
	end
	s.dark:SetShown(real.darkOverlay and real.darkOverlay:IsShown() or false)
	s.cd:Clear()
	s.cd:SetHideCountdownNumbers(true)
	s.time:SetText(""); s.count:SetText("")
	-- the item's own look: no sweep when its Sweep is None
	s.cd:SetDrawSwipe(SP:CdItemOpt(real.cooldownType, "sweep") ~= "none")
	-- the ring: the shield's color (Shield Charge Strip, a theme holds it), the rest a quiet one
	if real.spellType == "shield" then
		local r, g, b = SP:ThemeColor("cd.strip", "strip")
		if not r then r, g, b = 0.2, 0.6, 1 end
		s.track:SetVertexColor(r, g, b, 1)
		ShieldLayer(s)
		FollowShieldContainer(s, real)
	else
		s.track:SetVertexColor(1, 1, 1, 0.28)
		if s.auraC then s.auraC:Hide() end
	end
end

-- ---------------------------------------------------------------------------
-- The pass: at the end of the cooldown bar's own pass, its texts
-- ---------------------------------------------------------------------------
local TEXT_KEYS = { "iconText", "timeText", "insideText", "outsideText" }
local function RealTime(real)
	for i = 1, #TEXT_KEYS do
		local fs = real[TEXT_KEYS[i]]
		if fs and fs:IsShown() then
			local t = fs:GetText()
			if t ~= nil then
				if isSecret(t) then return t, fs end
				if t ~= "" then return t, fs end
			end
		end
	end
	return nil
end

local function Pass()
	if shownN == 0 then return end
	for i = 1, shownN do
		local s = slots[i]
		local real = s and s.real
		if real then
			local t, fs = RealTime(real)
			if t ~= nil then
				s.time:SetText(t)
				local r, g, b = fs:GetTextColor()
				if r ~= nil and not isSecret(r) then s.time:SetTextColor(r, g, b) end
			elseif s.timeSet ~= false then
				s.time:SetText("")
			end
			s.timeSet = t ~= nil
			local ch = real.chargeText
			if ch then
				local c = ch:GetText()
				if c ~= nil then
					s.count:SetText(c)
					local r, g, b = ch:GetTextColor()
					if r ~= nil and not isSecret(r) then s.count:SetTextColor(r, g, b) end
				end
			end
		end
	end
end
C.CdPass = Pass

-- ---------------------------------------------------------------------------
-- Layout (out of combat only)
-- ---------------------------------------------------------------------------
local function BarLayoutKey()
	local o = O()
	local l = o and o.layout
	if l == "row" or l == "square" then return l end
	return "dpad"
end

-- On The Controller Bar: the room your cooldowns need above / under the totems
-- (ShamanPowerController.lua Place asks while it sizes the bar)
function C:CdExtent(lk)
	if Mode() ~= "bar" then return 0, 0 end
	local n = #Collect()
	if n == 0 then return 0, 0 end
	if lk == "dpad" then
		if n > 4 then return 0, GAP + SMALL end
		return 0, 0
	end
	return GAP + SMALL, 0
end

local function SeparateFrame()
	if cdFrame then return cdFrame end
	cdFrame = CreateFrame("Frame", "ShamanPowerControllerCooldowns", UIParent)
	cdFrame:SetFrameStrata("MEDIUM")
	cdFrame:SetClampedToScreen(true)
	cdFrame:SetSize(SLOT * 3, SLOT * 3)
	cdFrame:Hide()
	C.cdFrame = cdFrame
	return cdFrame
end

-- a small row of slots first..last, centered on (x, y) of `anchor`
local function SmallRow(first, last, anchor, x, y)
	local n = last - first + 1
	for i = first, last do
		local s = slots[i]
		SizeSlot(s, SMALL)
		s:ClearAllPoints()
		s:SetPoint("CENTER", anchor, "CENTER", x + ((i - first) - (n - 1) / 2) * SMALL_STEP, y)
	end
end

local CORNER = { { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 } }       -- top-left, top-right, bottom-left, bottom-right
local AROUND = { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 }, { 0, 0 } } -- up, right, down, left, the middle

local function LayoutBar(n)
	local bar = C.frame
	local lk = BarLayoutKey()
	for i = 1, n do slots[i]:SetParent(bar); slots[i]:SetFrameLevel(bar:GetFrameLevel() + 2) end
	if lk == "dpad" then
		local center = C.slot.dropall
		for i = 1, math.min(n, 4) do
			local s = slots[i]
			SizeSlot(s, SMALL)
			s:ClearAllPoints()
			s:SetPoint("CENTER", center, "CENTER", CORNER[i][1] * DIAG, CORNER[i][2] * DIAG)
		end
		if n > 4 then SmallRow(5, n, center, 0, -(STEP + SLOT / 2 + GAP + SMALL / 2)) end
	else
		SmallRow(1, n, C.slot.water, 0, SLOT / 2 + GAP + SMALL / 2)
	end
end

local function LayoutSeparate(n)
	local f = SeparateFrame()
	local o = O()
	local row = o and o.cdLayout == "row"
	for i = 1, n do slots[i]:SetParent(f); slots[i]:SetFrameLevel(f:GetFrameLevel() + 2) end
	local w, h
	if row then
		w, h = (n - 1) * STEP + SLOT + 8, SLOT + 8
		for i = 1, n do
			local s = slots[i]
			SizeSlot(s, SLOT)
			s:ClearAllPoints()
			s:SetPoint("CENTER", f, "CENTER", ((i - 1) - (n - 1) / 2) * STEP, 0)
		end
	else
		local extra = (n > 5) and (GAP + SMALL) or 0
		local rowW = (n > 5) and ((n - 6) * SMALL_STEP + SMALL) or 0
		w = math.max(2 * STEP + SLOT, rowW) + 8
		h = 2 * STEP + SLOT + 8 + extra
		for i = 1, math.min(n, 5) do
			local s = slots[i]
			SizeSlot(s, SLOT)
			s:ClearAllPoints()
			s:SetPoint("CENTER", f, "CENTER", AROUND[i][1] * STEP, AROUND[i][2] * STEP + extra / 2)
		end
		if n > 5 then SmallRow(6, n, f, 0, extra / 2 - (STEP + SLOT / 2 + GAP + SMALL / 2)) end
	end
	f:SetSize(w, h)
	local scale = tonumber(o and o.cdScale) or 1
	if scale < 0.5 then scale = 0.5 elseif scale > 2.5 then scale = 2.5 end
	f:SetScale(scale)
	SP:ApplyPositionRecord(f, (o and o.cdPosition) or DEFAULT_POSITION)
end

local regen = CreateFrame("Frame")
regen:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	if pending then C:CdRefresh() end
end)

-- what hides the cooldown bar now (ShamanPower.lua UpdateCooldownBar / UpdateCooldownBarPosition)
function SP:ControllerHidesCooldownBar()
	if not live or shownN == 0 then return false end
	local o = O()
	return not (o and o.hideCooldownBar == false)
end
local barHidden = false
local function ApplyCooldownBarHide()
	local want = SP:ControllerHidesCooldownBar()
	if want == barHidden then return end
	barHidden = want
	if SP.cooldownBar and SP.UpdateCooldownBar then SP:UpdateCooldownBar() end
end

local busy = false
-- Show / hide / place the slots (out of combat only; a fight's change waits for its end)
function C:CdRefresh()
	if busy then return end
	if InCombatLockdown() then
		pending = true
		regen:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	pending = false
	busy = true
	local mode = Mode()
	local list = Collect()
	local n = #list
	local where   -- the frame the slots go in, or nil
	live = false
	if n > 0 and mode == "bar" and C.frame and C.frame:IsShown() then
		where, live = "bar", C:IsActive()
	elseif n > 0 and mode == "separate" and (C:IsActive() or demo) then
		where, live = "separate", C:IsActive()
	elseif demo and mode == "separate" then
		where = "separate"   -- Unlock UI with nothing on the bar yet: an empty box to move
	end
	if where then
		for i = 1, n do if not slots[i] then MakeSlot(i) end end
		for i = 1, n do Wire(slots[i], list[i]) end
		if where == "bar" then LayoutBar(n) else LayoutSeparate(n) end
		for i = 1, n do slots[i]:Show() end
		shownN = n
	else
		shownN = 0
	end
	for i = shownN + 1, #slots do
		local s = slots[i]
		s:Hide()
		if s.auraC then s.auraC:Hide() end
		if s.real and slotOf[s.real] == s then slotOf[s.real] = nil end
		s.real = nil
	end
	if cdFrame then cdFrame:SetShown(where == "separate") end
	ApplyCooldownBarHide()   -- (still busy: the cooldown bar's own layout pass does not come back here)
	busy = false
	if shownN > 0 then
		-- the bar hands every cooldown to its widget again on its next pass (mirrored above)
		if SP.ResetEngineBarCooldowns then SP:ResetEngineBarCooldowns() end
		if SP.cooldownButtons then for i = 1, #SP.cooldownButtons do SP.cooldownButtons[i]._ebStale = true end end
		if SP.WakeCooldownBar then SP:WakeCooldownBar() end
		if SP.UpdateCooldownButtons then SP:UpdateCooldownButtons() end
	end
end

-- a setting changed: the controller bar is sized again around them (its Refresh runs ours)
local lastBarN = -1
function C:CdChanged()
	lastBarN = -1
	if C.Refresh then C:Refresh() else C:CdRefresh() end
end

-- the cooldown bar changed (items, order, made again): the controller bar makes room when the
-- count it holds changes, else only our slots move
local function BarChanged()
	if busy or InCombatLockdown() then
		if InCombatLockdown() then pending = true; regen:RegisterEvent("PLAYER_REGEN_ENABLED") end
		return
	end
	local n = (Mode() == "bar") and #Collect() or 0
	if n ~= lastBarN and C.frame and C.frame:IsShown() then
		lastBarN = n
		C:Refresh()
	else
		C:CdRefresh()
	end
end

-- Unlock UI: the Separate frame on screen to be moved even when the controller look is off now
function SP:ControllerCooldownsUnlockDemo(on)
	demo = on and true or false
	C:CdRefresh()
end
if SP.RegisterPreview then
	SP:RegisterPreview("controllerCooldowns", { frame = function() return cdFrame end, demo = "SP:ControllerCooldownsUnlockDemo" })
end
if SP.UnlockModules then
	table.insert(SP.UnlockModules, { key = "controllerCooldowns", label = "My Cooldowns (Controller)",
		enabled = function()
			local o = O()
			return o and o.enabled and Mode() == "separate" and select(2, UnitClass("player")) == "SHAMAN" and true or false
		end,
		frames = function()
			SeparateFrame()
			return { cdFrame }
		end,
		save = function(frame)
			local o = O()
			if o then o.cdPosition = SP:SavePositionRecord(frame) end
		end,
		reset = function()
			local o = O()
			if o then o.cdPosition = nil end
			if cdFrame and not InCombatLockdown() then SP:ApplyPositionRecord(cdFrame, DEFAULT_POSITION) end
		end })
end

-- ---------------------------------------------------------------------------
-- Hooks
-- ---------------------------------------------------------------------------
hooksecurefunc(C, "Refresh", function()
	lastBarN = (Mode() == "bar") and #Collect() or 0
	C:CdRefresh()
end)
if SP.UpdateCooldownButtons then hooksecurefunc(SP, "UpdateCooldownButtons", Pass) end
if SP.UpdateCooldownBarLayout then hooksecurefunc(SP, "UpdateCooldownBarLayout", BarChanged) end
if SP.RecreateCooldownBar then hooksecurefunc(SP, "RecreateCooldownBar", BarChanged) end
if SP.RebuildShieldChargeContainer then hooksecurefunc(SP, "RebuildShieldChargeContainer", function()
	for i = 1, shownN do
		local s = slots[i]
		if s and s.real and s.real.spellType == "shield" then FollowShieldContainer(s, s.real) end
	end
end) end
