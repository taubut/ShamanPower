-- Own-totem minimap markers. Geometry is plain world-yard data, never aura coverage.
local SP = ShamanPower
if not SP then return end
-- The markers need the minimap's view radius in yards. The Anniversary client
-- has no C_Minimap.GetViewRadius, so there the feature is off entirely: no
-- events, no retries on every step, and the options stay hidden.
if not (C_Minimap and C_Minimap.GetViewRadius) then
	function SP.RefreshMinimapTotems() end
	SP.MinimapTotemsAvailable = false
	return
end
SP.MinimapTotemsAvailable = true
local secret = issecretvalue or function() return false end
local mainline = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
local pins, classicDrops, blockedDrops, blocked = {}, {}, {}, {}
for element = 1, 4 do classicDrops[element] = {} end
local circleX, circleY = {}, {}
local SEGMENTS = 32
for i = 0, SEGMENTS do
	circleX[i], circleY[i] = math.cos(i * 2 * math.pi / SEGMENTS), math.sin(i * 2 * math.pi / SEGMENTS)
end
-- The buff families listed by the optional Totem Range Tracker; its load is not required.
local buffIndexes = {
	{ [1] = true, [2] = true }, { [1] = true, [5] = true, [6] = true },
	{ [1] = true, [2] = true, [3] = true, [6] = true },
	{ [1] = true, [2] = true, [3] = true, [4] = true, [6] = true, [7] = true },
}
local ticker, expiryTimer, expiryAt, active, moving, turning, looking
local ready, playerShaman, failed, pending, queued, rotate, swapAxes
local worldID, eastX, eastY, northX, northY, pixelsPerYard, clipRadius, searingRange
local lastX, lastY, lastFacing
local refreshModels, redraw, syncTicker

local function number(value)
	return not secret(value) and type(value) == "number" and value > -math.huge and value < math.huge
end

local function position()
	if not UnitPosition then return end
	local ok, a, b, _, map = pcall(UnitPosition, "player")
	if ok and number(a) and number(b) and number(map) then return a, b, map end
end

local function allowed()
	if not playerShaman or not SP.opt or SP:IsOff() or SP.opt.minimapTotemMarkers == false then
		return false
	end
	local ok, inside = pcall(IsInInstance)
	return ok and not secret(inside) and inside == false
end

local function hideAll()
	for i = 1, 4 do if pins[i] then pins[i]:Hide() end end
	if ticker then ticker:Cancel(); ticker = nil end
	if expiryTimer then expiryTimer:Cancel(); expiryTimer, expiryAt = nil, nil end
end

-- Both APIs return vectors (FILE4637132); keep these allocating reads event-only.
local function worldPoint(map, x, y)
	local ok, continent, vector = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
	if not ok or not number(continent) or secret(vector) or not vector then return end
	local read, a, b = pcall(vector.GetXY, vector)
	if read and number(a) and number(b) then return continent, a, b end
end

local function calibrate()
	ready = false
	if not allowed() or not Minimap or not C_Map or not C_Map.GetBestMapForUnit
		or not C_Map.GetPlayerMapPosition or not C_Map.GetWorldPosFromMapPos or not CreateVector2D
		or not C_Minimap or not C_Minimap.GetViewRadius then return end
	local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
	if not ok or not number(map) then return end
	local got, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
	if not got or secret(pos) or not pos then return end
	local read, px, py = pcall(pos.GetXY, pos)
	if not read or not number(px) or not number(py) then return end
	local continent, wx, wy = worldPoint(map, px, py)
	local a, b, unitMap = position()
	if not a or not continent or unitMap ~= continent then return end
	-- Establish vector/UnitPosition correspondence rather than assuming axis order.
	local direct = math.abs(a - wx) < 0.05 and math.abs(b - wy) < 0.05
	local swapped = math.abs(b - wx) < 0.05 and math.abs(a - wy) < 0.05
	if direct == swapped then return end
	swapAxes = swapped
	local c0, ox, oy = worldPoint(map, 0, 0)
	local ce, ex, ey = worldPoint(map, 1, 0)
	local cs, sx, sy = worldPoint(map, 0, 1)
	if not c0 or not ce or not cs or c0 ~= continent or ce ~= continent or cs ~= continent then return end
	ex, ey, sx, sy = ex - ox, ey - oy, sx - ox, sy - oy
	local el, sl = math.sqrt(ex * ex + ey * ey), math.sqrt(sx * sx + sy * sy)
	if not number(el) or not number(sl) or el <= 0 or sl <= 0 then return end
	ex, ey, sx, sy = ex / el, ey / el, sx / sl, sy / sl
	if math.abs(ex * sx + ey * sy) > 0.0001 then return end
	local radiusOK, yards = pcall(C_Minimap.GetViewRadius)
	local widthOK, width = pcall(Minimap.GetWidth, Minimap)
	local heightOK, height = pcall(Minimap.GetHeight, Minimap)
	if not radiusOK or not widthOK or not heightOK or not number(yards) or yards <= 0
		or not number(width) or not number(height) or width <= 4 or height <= 4 then return end
	clipRadius = math.min(width, height) / 2 - 1
	pixelsPerYard = (clipRadius + 1) / yards
	worldID, eastX, eastY, northX, northY = continent, ex, ey, -sx, -sy
	local cv = C_CVar and C_CVar.GetCVarBool or GetCVarBool
	local cvOK, rotation = false, false
	if cv then cvOK, rotation = pcall(cv, "rotateMinimap") end
	if not cvOK or secret(rotation) or type(rotation) ~= "boolean" then return end
	rotate = rotation
	if C_Minimap.IsRotateMinimapIgnored then
		local ignoredOK, ignored = pcall(C_Minimap.IsRotateMinimapIgnored)
		if not ignoredOK or secret(ignored) or type(ignored) ~= "boolean" then return end
		rotate = rotate and not ignored
	end
	ready = true
	lastX, lastY, lastFacing = nil, nil, nil
end

local function buildPins()
	for element = 1, 4 do
		local pin = pins[element]
		if not pin or not pin.complete then
			if pin then pin:Hide() end
			pin = CreateFrame("Frame", nil, Minimap)
			pins[element] = pin
			pin:Hide()
			pin:SetAllPoints(Minimap)
			pin:EnableMouse(false)
			pin.icon = pin:CreateTexture(nil, "OVERLAY")
			pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			pin.lines = {}
			for i = 1, SEGMENTS do
				local line = pin:CreateLine(nil, "ARTWORK")
				line:SetThickness(1)
				pin.lines[i] = line
			end
			pin.complete, classicDrops[element] = true, classicDrops[element] or {}
		end
	end

end

local function createPins()
	if pins[4] and pins[4].complete then return true end
	if InCombatLockdown() or not Minimap then pending = true; return false end
	local ok = pcall(buildPins)
	if not ok then failed = true; hideAll(); return false end
	return true
end

-- Clip a segment to the minimap disc; no arrays or callbacks on this hot path.
local function clip(ax, ay, bx, by, radius)
	local dx, dy = bx - ax, by - ay
	local a = dx * dx + dy * dy
	if a <= 0 then return end
	local b = 2 * (ax * dx + ay * dy)
	local c = ax * ax + ay * ay - radius * radius
	local discriminant = b * b - 4 * a * c
	if discriminant <= 0 then return end
	local root = math.sqrt(discriminant)
	local lo, hi = math.max(0, (-b - root) / (2 * a)), math.min(1, (-b + root) / (2 * a))
	if hi <= lo then return end
	return ax + lo * dx, ay + lo * dy, ax + hi * dx, ay + hi * dy
end

local function draw()
	local a, b, map = position()
	if not a or map ~= worldID then return false end
	local wx, wy = a, b
	if swapAxes then wx, wy = b, a end
	local facing, forwardEast, forwardNorth = 0, 0, 1
	if rotate then
		local ok, value = pcall(GetPlayerFacing)
		if not ok or not number(value) then return false end
		facing = value
		-- Assumed north-zero/counter-clockwise facing; the docs leave this UNVERIFIED.
		local fx, fy = math.cos(facing), math.sin(facing)
		if swapAxes then fx, fy = fy, fx end
		forwardEast, forwardNorth = fx * eastX + fy * eastY, fx * northX + fy * northY
	end
	if wx == lastX and wy == lastY and facing == lastFacing then return true end
	lastX, lastY, lastFacing = wx, wy, facing
	local now = GetTime()
	for element = 1, 4 do
		local pin = pins[element]
		if pin and pin.active and pin.expires > now and pin.map == map then
			local dx, dy = pin.x - wx, pin.y - wy
			local east, north = (dx * eastX + dy * eastY) * pixelsPerYard, (dx * northX + dy * northY) * pixelsPerYard
			local x, y = east * forwardNorth - north * forwardEast, east * forwardEast + north * forwardNorth
			local fit = clipRadius - pin.size * 0.7071067812
			if number(x) and number(y) and fit > 0 and x * x + y * y <= fit * fit then
				pin.icon:ClearAllPoints()
				pin.icon:SetPoint("CENTER", Minimap, "CENTER", x, y)
				pin:Show()
				local radius = pin.radius and pin.radius * pixelsPerYard
				for i = 1, SEGMENTS do
					local line = pin.lines[i]
					local ax, ay, bx, by
					if radius then
						ax, ay, bx, by = clip(x + circleX[i - 1] * radius, y + circleY[i - 1] * radius,
							x + circleX[i] * radius, y + circleY[i] * radius, clipRadius)
					end
					if ax then
						line:SetStartPoint("CENTER", Minimap, ax, ay)
						line:SetEndPoint("CENTER", Minimap, bx, by)
						line:Show()
					else line:Hide() end
				end
			else pin:Hide() end
		elseif pin then pin:Hide() end
	end
	return true
end

redraw = function()
	if failed or not ready or not allowed() then hideAll(); return end
	local ok, shown = pcall(draw)
	if not ok then failed = true end
	if not ok or not shown then ready = false; hideAll() end
end

syncTicker = function()
	local want = active and ready and not failed and allowed() and (moving or turning or looking)
	if want and not ticker then ticker = C_Timer.NewTicker(0.2, redraw)
	elseif not want and ticker then ticker:Cancel(); ticker = nil end
end

local function expire()
	expiryTimer, expiryAt = nil, nil
	refreshModels()
end

local function radiusFor(element, index)
	if element == 2 and index == 2 then return searingRange end
	if element == 2 and index == 3 then return 8 end -- Magma effect 8187, SpellRadius 14 in supplied DB2.
	if not index then return nil end
	local tracked = false
	if SP.TrackableTotems then
		for i = 1, #SP.TrackableTotems do
			local totem = SP.TrackableTotems[i]
			if totem.element == element and totem.index == index then tracked = true; break end
		end
	else tracked = buffIndexes[element][index] end
	if not tracked then return nil end
	if mainline then return SP:GetTotemRangeModelRadius() end
	return element == 4 and index == 1 and 30 or 20 -- Classic baseline; talent changes are not modeled.
end

refreshModels = function()
	queued = false
	active = false
	if not allowed() or failed or not ready or not createPins() then hideAll(); return end
	local now, earliest = GetTime(), nil
	for element = 1, 4 do
		local pin = pins[element]
		local ok, have, name, start, duration, icon = pcall(SP.GetElementTotemInfo, SP, element)
		local drop = mainline and SP.totemDropPos[element] or classicDrops[element]
		if blocked[element] and drop ~= blockedDrops[element] then blocked[element], blockedDrops[element] = nil, nil end
		pin.active = false
		if not blocked[element] and ok and not secret(have) and have == true and not secret(name)
			and number(start) and number(duration) and duration > 0 and number(start + duration) and start + duration > now
			and not secret(icon) and (type(icon) == "string" or type(icon) == "number")
			and drop and number(drop.x) and number(drop.y) and number(drop.map) and drop.map == worldID then
			-- Core records reverse the UnitPosition tuple; Classic records use the same convention.
			local a, b = drop.y, drop.x
			pin.x, pin.y = a, b
			if swapAxes then pin.x, pin.y = b, a end
			pin.map, pin.expires, pin.active = drop.map, start + duration, true
			pin.icon:SetTexture(icon)
			local size = SP.opt.minimapTotemPinSize
			pin.size = number(size) and math.min(28, math.max(8, size)) or 14
			pin.icon:SetSize(pin.size, pin.size)
			local indexOK, index = pcall(SP.GetActiveTotemIndex, SP, element)
			pin.radius = nil
			if indexOK and number(index) and SP.opt.minimapTotemRings ~= false then pin.radius = radiusFor(element, index) end
			local color = SP.ElementColors[element]
			for i = 1, SEGMENTS do pin.lines[i]:SetColorTexture(color.r, color.g, color.b, 0.65) end
			active = true
			if not earliest or pin.expires < earliest then earliest = pin.expires end
		else pin:Hide() end
	end
	if expiryAt ~= earliest then
		if expiryTimer then expiryTimer:Cancel(); expiryTimer = nil end
		expiryAt = earliest
		if earliest then expiryTimer = C_Timer.NewTimer(math.max(0.01, earliest - now), expire) end
	end
	lastX, lastY, lastFacing = nil, nil, nil
	redraw()
	syncTicker()
end

local function runRefresh()
	queued = false
	if not ready then SP:RefreshMinimapTotems() else refreshModels() end
end

local function queueRefresh()
	if queued then return end
	queued = true
	C_Timer.After(0, runRefresh)
end

local function classicDrop(element)
	if not element or not classicDrops[element] then return end
	local a, b, map = position()
	local drop = classicDrops[element]
	drop.x, drop.y, drop.map = b, a, map
	blocked[element], blockedDrops[element] = nil, nil
end

local function afterTotem(_self, _event, slot)
	if not mainline and number(slot) and allowed() then
		local ok, have, _, start = pcall(GetTotemInfo, slot)
		if ok and not secret(have) and have == true and number(start)
			and GetTime() - start >= 0 and GetTime() - start <= 1.5 then
			for element = 1, 4 do if SP.ElementToSlot[element] == slot then classicDrop(element) end end
		end
	end
	queueRefresh()
end

local function afterCast(_self, _event, unit, _guid, spellID)
	if secret(unit) or unit ~= "player" or not number(spellID) then return end
	if mainline and spellID == 437009 then
		for element = 1, 4 do blocked[element], blockedDrops[element] = true, SP.totemDropPos[element] end
	elseif not mainline and allowed() then
		local ok, element = pcall(SP.TotemCastElement, SP, spellID)
		if ok and number(element) then classicDrop(element) end
	end
	queueRefresh()
end

function SP.RefreshMinimapTotems()
	if not InCombatLockdown() then failed, pending = false, false end
	local classOK, _, class = pcall(UnitClass, "player")
	playerShaman = classOK and not secret(class) and class == "SHAMAN"
	local moveOK, isMoving = pcall(IsPlayerMoving)
	moving = moveOK and not secret(isMoving) and isMoving == true
	if not allowed() then ready = false; hideAll(); return end
	local ok = pcall(calibrate)
	if not ok then ready = false end
	-- Spell 3606 is Searing's attack, not its summoning spell. Unknown range means no ring.
	searingRange = nil
	if C_Spell and C_Spell.GetSpellInfo then
		local infoOK, info = pcall(C_Spell.GetSpellInfo, 3606)
		if infoOK and not secret(info) and type(info) == "table" and number(info.maxRange) and info.maxRange > 0 then
			searingRange = info.maxRange
		end
	elseif GetSpellInfo then
		local infoOK, _, _, _, _, _, range = pcall(GetSpellInfo, 3606)
		if infoOK and number(range) and range > 0 then searingRange = range end
	end
	refreshModels()
end

local events = CreateFrame("Frame")
if SPCompat and SPCompat.StressRegister then SPCompat.StressRegister(events, "Minimap Totems") end
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
	"MINIMAP_UPDATE_ZOOM", "CVAR_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING",
	"PLAYER_STARTED_TURNING", "PLAYER_STOPPED_TURNING", "PLAYER_STARTED_LOOKING", "PLAYER_STOPPED_LOOKING" }) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_STARTED_MOVING" then moving = true
	elseif event == "PLAYER_STOPPED_MOVING" then moving = false
	elseif event == "PLAYER_STARTED_TURNING" then turning = true
	elseif event == "PLAYER_STOPPED_TURNING" then turning = false
	elseif event == "PLAYER_STARTED_LOOKING" then looking = true
	elseif event == "PLAYER_STOPPED_LOOKING" then looking = false
	else
		if event == "PLAYER_REGEN_ENABLED" and not pending and not failed then return end
		SP:RefreshMinimapTotems()
		return
	end
	if not ready and allowed() then SP:RefreshMinimapTotems() end
	redraw()
	syncTicker()
end)
hooksecurefunc(SP, "PLAYER_TOTEM_UPDATE", afterTotem)
hooksecurefunc(SP, "UNIT_SPELLCAST_SUCCEEDED", afterCast)
hooksecurefunc(SP, "UpdateLayout", SP.RefreshMinimapTotems)
