-- ShamanPower_Config :: PopOut
-- Settings for popped-out trackers (the gear on a pop-out), expressed as a
-- FrameSettings spec. The engine setters are unchanged.

local ADDON, ns = ...
local FS = ns.FrameSettings

local SP = ShamanPower
if not SP or not FS then return end

local DIRS  = { top = "Top", bottom = "Bottom", left = "Left", right = "Right" }
local ORDER = { "top", "bottom", "left", "right" }

local function Settings(key)
	local o = SP.opt or {}
	local s = o.poppedOutSettings and o.poppedOutSettings[key] or {}
	return {
		scale     = s.scale or o.poppedOutDefaultScale or 1.0,
		opacity   = s.opacity or o.poppedOutDefaultOpacity or 1.0,
		hideFrame = s.hideFrame or false,
		flyoutDir = s.flyoutDirection or "bottom",
	}
end

local function Cap(w) return (w:gsub("^%l", string.upper)) end
local function KeyLabel(key)
	local element = key:match("^totem_(%a+)$")
	if element then return Cap(element) .. " totem" end
	local el, idx = key:match("^single_(%d+)_(%d+)$")
	if el then
		local names = SP.TotemNames and SP.TotemNames[tonumber(el)]
		local n = names and names[tonumber(idx)]
		if n then return n .. " totem" end
	end
	if key == "earthshield" then return "Earth Shield" end
	if key == "dropall" then return "Drop All" end
	local cd = key:match("^cd_(.+)$")
	if cd then
		local names = { "Shield", "Totemic Call", "Reincarnation", "Nature's Swiftness", "Mana Tide", "Bloodlust", "Weapon Imbue" }
		return (names[tonumber(cd)] or Cap((cd:gsub("_", " ")))) .. " cooldown"
	end
	return Cap((key:gsub("_", " ")))
end

local function Spec(key, popOutFrame)
	local shown = popOutFrame and popOutFrame.title
	local spec = {
		key = "popout:" .. key,
		title = "Pop-Out Settings",
		subtitle = (shown and shown ~= "" and shown) or KeyLabel(key),
		scale = {
			min = 50, max = 300,
			get = function() return math.floor(Settings(key).scale * 100 + 0.5) end,
			set = function(v) SP:SetPopOutScale(key, v / 100) end,
		},
		opacity = {
			get = function() return math.floor(Settings(key).opacity * 100 + 0.5) end,
			set = function(v) SP:SetPopOutOpacity(key, v / 100) end,
		},
		hideFrame = {
			get = function() return Settings(key).hideFrame end,
			set = function(v) if Settings(key).hideFrame ~= v then SP:TogglePopOutFrame(key) end end,
		},
		actions = {
			{ text = "Return to Bar", desc = "Put this tracker back on its bar.",
			  func = function() FS:Hide(); SP:ReturnPopOutToBar(key) end },
		},
	}
	if key:match("^totem_") then
		spec.rows = function(Row)
			Row("Dropdown", {
				label = "Flyout Direction", desc = "Where this totem's flyout opens.",
				values = function() return DIRS end,
				order  = function() return ORDER end,
				get = function() return Settings(key).flyoutDir end,
				set = function(v) SP:SetPopOutFlyoutDirection(key, v) end,
			})
		end
	end
	return spec
end

function SP:ShowPopOutSettingsPanel(key, popOutFrame)
	FS:Open(popOutFrame, Spec(key, popOutFrame))
end

return true
