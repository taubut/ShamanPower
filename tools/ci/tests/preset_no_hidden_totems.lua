-- client: both
-- Srumar's Layout hid Searing from the fire flyout, so a new shaman who took it at first login had
-- no fire totem to pick (three players' reports, 11-07). A built-in preset now hides no totem; a
-- code a player shares keeps its list, and every other setting lands as before.
local SP = ShamanPower
local preset
for _, p in ipairs(SP.Presets or {}) do if p.key == "srumar" then preset = p end end
if not (preset and preset.str and SP.DecodeShare and SP.EncodeShare) then skip("no Srumar's Layout here") end

local function snap(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do if type(v) ~= "function" then out[k] = snap(v) end end
	return out
end
local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in pairs(a) do if not same(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end
local function hidden(t)
	local list = {}
	for k, v in pairs(type(t) == "table" and t or {}) do if v == false then list[#list + 1] = k end end
	table.sort(list)
	return table.concat(list, ",")
end

-- the same layout shared as a player's code (no preset flag): its list stays
local payload = SP:DecodeShare(preset.str)
check("the preset decodes", type(payload) == "table" and payload.preset)
local shipped = hidden(payload.profile.flyoutTotems)
payload.preset = nil
local shared = SP:EncodeShare(payload)
check("as a shared code it imports", SP:ImportShare(shared, "newProfile", "SPCI Shared") ~= nil)
SP:UseDefaultBarSpots()   -- (what applying the preset does after its import)
local asShared = snap(SP.db.profile)
checkEq("a shared code keeps the totems it hides", hidden(asShared.flyoutTotems), shipped)

-- the preset itself: no totem hidden
check("the preset applies", SP:ApplyPreset("srumar", "newProfile", "SPCI Preset") ~= nil)
local asPreset = snap(SP.db.profile)
checkEq("Srumar's Layout hides no totem", hidden(SP.opt.flyoutTotems), "")
check("Searing is in the fire flyout", SP.opt.flyoutTotems == nil or SP.opt.flyoutTotems.fire_2 ~= false)
if SP.RecreateTotemFlyouts then
	SP:RecreateTotemFlyouts()
	local searing
	for _, b in ipairs(SP.totemFlyouts[2] and SP.totemFlyouts[2].allButtons or {}) do
		if b.totemIndex == 2 then searing = b end
	end
	if searing then check("its flyout button is listed", not searing.isDisabledInFlyout) end
end

-- every other setting the same as the shared code's
asShared.flyoutTotems, asPreset.flyoutTotems = nil, nil
check("nothing else in the layout changes", same(asShared, asPreset))
finish()
