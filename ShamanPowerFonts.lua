-- ============================================================================
-- Fonts: one place that decides the typeface and outline of every piece of
-- text ShamanPower draws on screen (not the settings window or the tour's own
-- text, which keep their fonts for readability).
--
-- Every on-screen font string is set through SP:SetSPFont(fs, area, size, flags)
-- instead of fs:SetFont(...). With nothing chosen in the settings it applies the
-- exact font and outline the call site passes, so the default look is unchanged.
-- Each call is remembered (weak keys: a string that is thrown away is forgotten),
-- so changing the font restyles everything at once without a reload.
-- ============================================================================

local SP = ShamanPower
if not SP then return end

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

SP.DEFAULT_FONT_PATH = "Fonts\\FRIZQT__.TTF"

-- The areas a player can give their own font. Order = order on the settings page.
SP.FONT_AREAS = {
	{ key = "timers",  label = "Timers and Cooldown Numbers", desc = "Totem timers, duration bar text, cooldown numbers, pop-out and Grid timers." },
	{ key = "charges", label = "Shield Charges",              desc = "The big Lightning / Water / Earth Shield charge numbers." },
	{ key = "alerts",  label = "Alerts and Reminders",        desc = "Expiring Alerts, Tremor Reminder, Ready Reminders and Reactive Totems text." },
	{ key = "labels",  label = "Names and Labels",            desc = "Party names, range counters, Totem Range, Coverage, Totem Plates and other small labels." },
}

SP.FONT_OUTLINES = {
	{ value = "",             label = "None" },
	{ value = "OUTLINE",      label = "Outline" },
	{ value = "THICKOUTLINE", label = "Thick Outline" },
}

-- Settings live in the AceDB profile (so profiles and exports carry them):
--   opt.fontName        LibSharedMedia font name for everything, or nil = as designed
--   opt.fontOutline     "", "OUTLINE", "THICKOUTLINE", or nil = as designed
--   opt.fontAreas[key]  { name = ..., outline = ... } overrides for one area
local function fontPath(name)
	if not name then return nil end
	local path = LSM and LSM:Fetch("font", name, true)
	return path
end

-- The font path and outline flags for an area; the call site's own choice when
-- the player has not picked anything.
function SP:FontFor(area, size, defaultFlags, defaultPath)
	local o = self.opt
	local path, flags = defaultPath or SP.DEFAULT_FONT_PATH, defaultFlags or ""
	if o then
		local a = area and o.fontAreas and o.fontAreas[area]
		local name = (a and a.name) or o.fontName
		local outline = a and a.outline
		if outline == nil then outline = o.fontOutline end
		path = fontPath(name) or path
		if outline ~= nil then flags = outline end
	end
	return path, flags
end

local registry = setmetatable({}, { __mode = "k" })

-- SetFont does not report failure on every client: a path that does not load
-- leaves the string with no font, which GetFont shows as nil.
local function apply(fs, path, size, flags, defaultPath, defaultFlags)
	fs:SetFont(path, size, flags)
	if not fs:GetFont() then fs:SetFont(defaultPath or SP.DEFAULT_FONT_PATH, size, defaultFlags or "") end
end

-- Drop-in for fs:SetFont(path, size, flags). area: one of SP.FONT_AREAS' keys.
function SP:SetSPFont(fs, area, size, defaultFlags, defaultPath)
	if not fs then return end
	size = size or select(2, fs:GetFont()) or 12
	local rec = registry[fs]
	if not rec then rec = {}; registry[fs] = rec end
	rec.area, rec.size, rec.flags, rec.path = area, size, defaultFlags, defaultPath
	local path, flags = self:FontFor(area, size, defaultFlags, defaultPath)
	apply(fs, path, size, flags, defaultPath, defaultFlags)   -- a missing font file falls back to the design
end

-- Re-apply every remembered font string: called when a font setting changes.
function SP:RefreshFonts()
	for fs, rec in pairs(registry) do
		local path, flags = self:FontFor(rec.area, rec.size, rec.flags, rec.path)
		apply(fs, path, rec.size, flags, rec.path, rec.flags)
	end
end

-- Profile switches and imports change opt underneath the strings.
function SP:FontsProfileChanged() self:RefreshFonts() end

-- Font names for a picker: LibSharedMedia's list (Blizzard's four plus every
-- font other installed addons register).
function SP:FontList()
	local out = {}
	if LSM then for _, name in ipairs(LSM:List("font")) do out[#out + 1] = name end end
	return out
end
