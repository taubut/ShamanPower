-- ============================================================================
-- Bar textures: one place that decides what the bar fills ShamanPower draws
-- look like (totem duration bars, cooldown bar progress, pulse sweeps, other
-- small bars). The companion of ShamanPowerFonts.lua.
--
-- A bar fill is set through SP:SetSPBarColor(tex, area, r, g, b, a) instead of
-- tex:SetColorTexture(r, g, b, a). With no texture chosen that is exactly the
-- old flat colour call; with one chosen, the LibSharedMedia statusbar texture is
-- tinted with the same colour. A StatusBar goes through
-- SP:SetSPStatusBarTexture(bar, area, defaultPath). Every call is remembered
-- (weak keys), so changing the texture restyles everything without a reload.
--
-- Compact's lines keep their own setting (Mode & Twisting > Compact > Line
-- Texture); "Apply This Look Everywhere" writes that one too.
-- ============================================================================

local SP = ShamanPower
if not SP then return end

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

SP.TEXTURE_AREAS = {
	{ key = "duration", label = "Totem Duration Bars", desc = "The bars that run down under your totems, on pop-outs, Grid and Blizzard's bar." },
	{ key = "cooldown", label = "Cooldown Bar",        desc = "The progress bars on the cooldown bar and the weapon imbue bars." },
	{ key = "pulse",    label = "Pulse Sweeps",        desc = "The sweep that shows a totem's next pulse (Tremor, Poison Cleansing ...) and Totem Plates' pulse bar." },
	{ key = "other",    label = "Other Bars",          desc = "Ready Reminders' cooldown bar." },
}

-- Settings (AceDB profile):
--   opt.barTexture             LibSharedMedia statusbar name, or nil = as designed
--   opt.barTextureAreas[key]   a name for one area
local function texturePath(name)
	if not name or not LSM then return nil end
	return LSM:Fetch("statusbar", name, true)
end

-- The texture path for an area, or nil = the call site's own design.
function SP:TextureFor(area)
	local o = self.opt
	if not o then return nil end
	local per = area and o.barTextureAreas and o.barTextureAreas[area]
	local name = per or o.barTexture
	-- a texture being hovered in the settings list, shown without saving it
	-- ("__default" previews the design for the main row, the main texture for an area)
	local pv = SP._texPreview
	if pv then
		if pv.area == area then
			if pv.name == "__default" then name = o.barTexture else name = pv.name end
		elseif pv.area == "all" and not per then
			if pv.name == "__default" then name = nil else name = pv.name end
		end
	end
	return texturePath(name)
end

local registry = setmetatable({}, { __mode = "k" })
-- Bumped whenever TextureFor's answers can change; the per-area answer is cached
-- for the generation, so per-tick callers do one table read.
local gen = 0
local areaPath, areaGen = {}, {}
local function pathFor(area)
	local key = area or "other"
	if areaGen[key] ~= gen then areaPath[key] = SP:TextureFor(area) or false; areaGen[key] = gen end
	return areaPath[key] or nil
end

local function paintFill(t, path, r, g, b, a)
	if path then
		if t.spBarTex ~= path then t:SetTexture(path); t.spBarTex = path end
		t:SetVertexColor(r, g, b, a or 1)
	else
		if t.spBarTex then t:SetVertexColor(1, 1, 1, 1); t.spBarTex = nil end
		t:SetColorTexture(r, g, b, a)
	end
end

-- Drop-in for tex:SetColorTexture(r, g, b, a) on a bar fill.
function SP:SetSPBarColor(t, area, r, g, b, a)
	if not t then return end
	local rec = registry[t]
	if rec and rec.gen == gen and rec.area == area and rec.r == r and rec.g == g and rec.b == b and rec.a == a then
		return   -- nothing changed since the last paint
	end
	if not rec then rec = { kind = "fill" }; registry[t] = rec end
	rec.area, rec.r, rec.g, rec.b, rec.a, rec.gen = area, r, g, b, a, gen
	paintFill(t, pathFor(area), r, g, b, a)
end

-- Drop-in for bar:SetStatusBarTexture(defaultPath) on a StatusBar.
function SP:SetSPStatusBarTexture(bar, area, defaultPath)
	if not bar then return end
	local rec = registry[bar]
	if rec and rec.gen == gen and rec.area == area and rec.path == defaultPath then return end
	if not rec then rec = { kind = "bar" }; registry[bar] = rec end
	rec.area, rec.path, rec.gen = area, defaultPath, gen
	local want = pathFor(area) or defaultPath
	if bar.spBarTex == want then return end
	-- keep the tint the caller gave the fill texture across the swap
	local old = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	local r, g, b, a
	if old and old.GetVertexColor then r, g, b, a = old:GetVertexColor() end
	bar:SetStatusBarTexture(want)
	bar.spBarTex = want
	local new = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if new and r and new.SetVertexColor then new:SetVertexColor(r, g, b, a) end
end

-- A frame still in use hangs off UIParent (or WorldFrame: nameplates); settings
-- previews are rebuilt and their old frames detached, so a refresh skips those
-- (they re-paint the next time their own code sets them).
local function live(obj)
	local p = obj:GetParent()
	while p do
		if p == UIParent or p == WorldFrame then return true end
		p = p:GetParent()
	end
	return false
end

-- Re-apply every remembered bar: called when a texture setting changes.
function SP:RefreshTextures()
	gen = gen + 1
	for obj, rec in pairs(registry) do
		if live(obj) then
			rec.gen = gen
			if rec.kind == "fill" then
				paintFill(obj, pathFor(rec.area), rec.r, rec.g, rec.b, rec.a)
			else
				local path = rec.path
				rec.path = nil          -- force the swap check below
				rec.gen = nil
				self:SetSPStatusBarTexture(obj, rec.area, path)
			end
		end
	end
end

-- Settings hover: show `name` for `area` ("all" = the main texture) until cleared.
function SP:PreviewTexture(area, name)
	if area and name then SP._texPreview = { area = area, name = name } else SP._texPreview = nil end
	self:RefreshTextures()
end

-- A saved texture another addon registers only after our bars were painted
-- fell back to the design: apply it the moment it arrives.
if LSM and LSM.RegisterCallback then
	local function saved(o, key)
		if o.barTexture == key then return true end
		if type(o.barTextureAreas) == "table" then
			for _, name in pairs(o.barTextureAreas) do
				if name == key then return true end
			end
		end
		return false
	end
	LSM.RegisterCallback(SP.TEXTURE_AREAS, "LibSharedMedia_Registered", function(_, mediatype, key)
		if mediatype == "statusbar" and SP.opt and saved(SP.opt, key) then SP:RefreshTextures() end
	end)
end

-- Statusbar names for a picker (LibSharedMedia's list: Blizzard's, ShamanPower's
-- four shipped bars, and every texture other installed addons register).
function SP:TextureList()
	local out = {}
	if LSM then for _, name in ipairs(LSM:List("statusbar")) do out[#out + 1] = name end end
	return out
end

-- One look everywhere: the main font, outline and texture for every area (the
-- per-area choices are cleared), and Compact's lines take the texture too.
function SP:ApplyLookEverywhere()
	local o = self.opt
	if not o then return end
	o.fontAreas, o.barTextureAreas = nil, nil
	if o.barTexture then o.compactLineTexture = o.barTexture end
	if self.RefreshFonts then self:RefreshFonts() end
	self:RefreshTextures()
	if self.ApplyCompactStyle and not InCombatLockdown() then pcall(self.ApplyCompactStyle, self) end
end

-- Back to the designed look: fonts, outline, bar textures and Compact's lines.
function SP:ResetLook()
	local o = self.opt
	if not o then return end
	o.fontName, o.fontOutline, o.fontAreas = nil, nil, nil
	o.barTexture, o.barTextureAreas = nil, nil
	o.compactLineTexture = nil
	if self.RefreshFonts then self:RefreshFonts() end
	self:RefreshTextures()
	if self.ApplyCompactStyle and not InCombatLockdown() then pcall(self.ApplyCompactStyle, self) end
end
