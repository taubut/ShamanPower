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
function SP:FontFor(area, _, defaultFlags, defaultPath)
	local o = self.opt
	local path, flags = defaultPath or SP.DEFAULT_FONT_PATH, defaultFlags or ""
	if o then
		local a = area and o.fontAreas and o.fontAreas[area]
		local name = (a and a.name) or o.fontName
		local outline = a and a.outline
		if outline == nil then outline = o.fontOutline end
		-- a font being hovered in the settings list, shown without saving it
		-- ("__default" previews the design for the main font, the main font for an area)
		local pv = SP._fontPreview
		if pv then
			if pv.area == area then
				if pv.name == "__default" then name = o.fontName else name = pv.name end
			elseif pv.area == "all" and not (a and a.name) then
				if pv.name == "__default" then name = nil else name = pv.name end
			end
		end
		path = fontPath(name) or path
		if outline ~= nil then flags = outline end
	end
	return path, flags
end

-- Settings hover: show `name` for `area` ("all" = the main font) until cleared.
function SP:PreviewFont(area, name)
	if area and name then
		SP._fontPreview = { area = area, name = name }
	else
		SP._fontPreview = nil
	end
	self:RefreshFonts()
end

local registry = setmetatable({}, { __mode = "k" })
-- Bumped whenever the answer of FontFor can change (a setting, a hover preview,
-- a profile switch). A call with the same arguments in the same generation is a
-- no-op, which keeps the few per-tick callers (timer text) free.
local gen = 0

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
	if rec and rec.gen == gen and rec.area == area and rec.size == size and rec.flags == defaultFlags and rec.path == defaultPath then
		return
	end
	if not rec then rec = {}; registry[fs] = rec end
	rec.area, rec.size, rec.flags, rec.path, rec.gen = area, size, defaultFlags, defaultPath, gen
	rec.template = nil
	local path, flags = self:FontFor(area, size, defaultFlags, defaultPath)
	apply(fs, path, size, flags, defaultPath, defaultFlags)   -- a missing font file falls back to the design
end

-- A string that should look like another one (a game-drawn copy of our text):
-- the source's design and area, and it follows later font changes.
function SP:CopySPFont(dst, src, area)
	if not (dst and src) then return end
	local rec = registry[src]
	if rec then self:SetSPFont(dst, area or rec.area, rec.size, rec.flags, rec.path) return end
	local path, size, flags = src:GetFont()
	if path then self:SetSPFont(dst, area or "timers", size, flags or "", path) end
end

-- For a string whose font came from a template (NumberFont*, GameFont*): its
-- current font becomes the designed default, then it follows the settings.
-- While nothing is chosen for its area the template is left alone: SetFont
-- would cut the string loose from its font object (other addons restyling
-- Blizzard's fonts) and swap the font family, with its fallbacks for other
-- alphabets (Cyrillic, Korean ... names), for one font file.
function SP:AdoptSPFont(fs, area)
	if not fs then return end
	local rec = registry[fs]
	local path, size, flags
	if rec then
		-- already known: something reset it to its template (SetFontObject)
		path, size, flags = rec.path, rec.size, rec.flags
	else
		path, size, flags = fs:GetFont()
		size, flags = size or 12, flags or ""
	end
	local wantPath, wantFlags = self:FontFor(area, size, flags, path)
	if wantPath == path and wantFlags == flags then
		if not rec then rec = {}; registry[fs] = rec end
		rec.area, rec.size, rec.flags, rec.path, rec.gen = area, size, flags, path, gen
		rec.template = true
		return
	end
	if rec then rec.gen = nil end   -- force the re-apply
	self:SetSPFont(fs, area, size, flags, path)
end

-- Re-apply every remembered font string: called when a font setting changes.
-- A string in use hangs off UIParent (or WorldFrame: nameplates). Settings previews
-- are rebuilt and their old frames detached (WoW never frees them); a refresh skips
-- detached strings, so a long settings session does not restyle dead copies. A
-- skipped one re-applies the next time its own code sets it (rec.gen stays old).
local function live(fs)
	local p = fs:GetParent()
	while p do
		if p == UIParent or p == WorldFrame then return true end
		p = p:GetParent()
	end
	return false
end

function SP:RefreshFonts()
	gen = gen + 1
	for fs, rec in pairs(registry) do
		if live(fs) then
		rec.gen = gen
		local path, flags = self:FontFor(rec.area, rec.size, rec.flags, rec.path)
		-- a template string still on its own font stays there while the design applies
		if not (rec.template and path == rec.path and flags == rec.flags) then
			rec.template = nil
			apply(fs, path, rec.size, flags, rec.path, rec.flags)
		end
		end
	end
	-- game-drawn cooldown numbers copy their font from our strings when placed
	if self.ResetEngineBarCooldowns then pcall(self.ResetEngineBarCooldowns, self) end
end

-- Font names for a picker: LibSharedMedia's list (Blizzard's four plus every
-- font other installed addons register).
function SP:FontList()
	local out = {}
	if LSM then for _, name in ipairs(LSM:List("font")) do out[#out + 1] = name end end
	return out
end
