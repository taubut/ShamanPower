-- ShamanPowerStyles.lua
-- One list of the totem bar's styles, shared by the setup tour's style cards,
-- the General page's style dropdown, the Mode & Twisting hover previews and the
-- what's-new card. The flags themselves stay where they always were
-- (compactStyle, dynamicTotemMode, activeTotemAsMain, gridStyle and
-- useBlizzardTotemBar); this file is the one place that reads and writes them
-- as a set, so every surface agrees on which style is "on".
local SP = ShamanPower
if not SP then return end

local function HasGrid() return SP.SetGridStyle ~= nil end
local function HasBlizzardBar()
	return WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and SP.HasTotemBar and SP:HasTotemBar() and SP.RefreshBlizzardTotemBar ~= nil
end

-- key    stable id used by the tour, the dropdown and the what's-new card
-- label  the name every surface shows
-- only   client / module gate (nil = always)
-- apply  sets that style's flags on o, any table shaped like opt (a copy for
--        a preview, or the live options); nothing here touches the bar
-- is     reads the flags back; evaluated in the order of PRECEDENCE below
SP.TOTEM_BAR_STYLES = {
	{ key = "normal", label = "Normal",
	  apply = function(o) o.gridStyle = false; o.useBlizzardTotemBar = nil; o.compactStyle = false; o.dynamicTotemMode = false; o.activeTotemAsMain = false end,
	  is = function(o) return true end },
	{ key = "totemtimers", label = "TotemTimers Style",
	  apply = function(o) o.gridStyle = false; o.useBlizzardTotemBar = nil; o.compactStyle = false; o.dynamicTotemMode = false; o.activeTotemAsMain = true end,
	  is = function(o) return o.activeTotemAsMain == true end },
	{ key = "dynamic", label = "Dynamic (PvP)",
	  apply = function(o) o.gridStyle = false; o.useBlizzardTotemBar = nil; o.compactStyle = false; o.dynamicTotemMode = true; o.activeTotemAsMain = false end,
	  is = function(o) return o.dynamicTotemMode == true end },
	{ key = "compact", label = "Compact (lines)",
	  apply = function(o) o.gridStyle = false; o.useBlizzardTotemBar = nil; o.compactStyle = true; o.dynamicTotemMode = false; o.activeTotemAsMain = false end,
	  is = function(o) return o.compactStyle == true end },
	{ key = "grid", label = "Grid (every totem)", only = HasGrid,
	  apply = function(o) o.useBlizzardTotemBar = nil; o.compactStyle = false; o.activeTotemAsMain = false; o.gridStyle = true end,
	  is = function(o) return o.gridStyle == true end },
	{ key = "blizzard", label = "Blizzard's Totem Bar", only = HasBlizzardBar,
	  apply = function(o) o.gridStyle = false; o.compactStyle = false; o.useBlizzardTotemBar = true end,
	  is = function(o) return o.useBlizzardTotemBar == true end },
}
-- Blizzard's bar wins over Grid, Grid over the four looks of ShamanPower's bar,
-- Compact over Dynamic over TotemTimers; Normal is what is left.
local PRECEDENCE = { "blizzard", "grid", "compact", "dynamic", "totemtimers", "normal" }

local byKey = {}
for _, st in ipairs(SP.TOTEM_BAR_STYLES) do byKey[st.key] = st end

function SP:TotemBarStyle(key)
	local st = byKey[key]
	if st and (not st.only or st.only()) then return st end
	return nil
end

-- The styles this client and character can use, in display order.
function SP:TotemBarStyleList()
	local list = {}
	for _, st in ipairs(self.TOTEM_BAR_STYLES) do
		if not st.only or st.only() then list[#list + 1] = st end
	end
	return list
end

-- Which style o (default: the live options) is showing.
function SP:GetTotemBarStyle(o)
	o = o or self.opt
	if not o then return "normal" end
	for _, key in ipairs(PRECEDENCE) do
		local st = byKey[key]
		if st and (not st.only or st.only()) and st.is(o) then return key end
	end
	return "normal"
end

-- Set the style's flags on o without touching the bar: previews work on a
-- shallow copy of the options. Returns false for a style this client lacks.
function SP:ApplyTotemBarStyleTo(o, key)
	local st = self:TotemBarStyle(key)
	if not (st and o) then return false end
	st.apply(o)
	return true
end

-- Switch the live bar to a style. Out of combat only (the bar's frames are
-- secure); says so and returns false otherwise. Grid and Blizzard's bar go
-- through their own setters so their frames are built or torn down; the four
-- looks of ShamanPower's bar refresh the way the Mode & Twisting toggles do.
function SP:SetTotemBarStyle(key)
	local st = self:TotemBarStyle(key)
	if not (st and self.opt) then return false end
	if InCombatLockdown() then
		print("|cff0070ddShamanPower:|r Cannot change the totem bar style during combat")
		return false
	end
	local o = self.opt
	-- Leave the current style through its own setter first, while the new flags
	-- are still off: Grid tears its rows down, Blizzard's bar gives the custom
	-- bar back, Compact restores the icon bar. Doing this after the new flags
	-- landed would run those teardowns with the next style already "on"
	-- (ApplyCompactStyle's layout pass is hooked by the Blizzard-bar code).
	if o.gridStyle and key ~= "grid" and self.SetGridStyle then self:SetGridStyle(false) end
	if o.useBlizzardTotemBar and key ~= "blizzard" then
		o.useBlizzardTotemBar = nil
		if self.RefreshBlizzardTotemBar then self:RefreshBlizzardTotemBar() end
	end
	if o.compactStyle and key ~= "compact" then
		o.compactStyle = false
		if self.ApplyCompactStyle then self:ApplyCompactStyle() end
	end
	st.apply(o)
	if key == "grid" then
		if self.SetGridStyle then self:SetGridStyle(true) end   -- builds the rows and refreshes the bar itself
	elseif key == "blizzard" then
		if self.SetTotemBarUnlocked and o.display and o.display.moverUnlocked then self:SetTotemBarUnlocked(false) end
		if self.RefreshBlizzardTotemBar then self:RefreshBlizzardTotemBar() end   -- what the Mode & Twisting toggle does
	else
		if self.ApplyCompactStyle then self:ApplyCompactStyle() end
		if self.UpdateLayout then self:UpdateLayout() end
		if self.UpdateMiniTotemBar then self:UpdateMiniTotemBar() end
		if self.UpdateActiveTotemOverlays then self:UpdateActiveTotemOverlays() end
	end
	if self.FollowStyleSpot then self:FollowStyleSpot() end   -- each style keeps its own spot
	if self.RefreshConfig then self:RefreshConfig() end
	local reg = LibStub and LibStub("AceConfigRegistry-3.0", true)
	if reg then reg:NotifyChange("ShamanPower") end
	local cfg = rawget(_G, "ShamanPowerConfig")
	if cfg and cfg.PreviewChanged then cfg:PreviewChanged() end
	return true
end
