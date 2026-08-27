-- ShamanPowerPreview
-- Lets the setup wizard show a module's REAL frame inside its own panel:
-- borrow the frame into a container, scale it to fit, fill it with sample data
-- via the module's Demo function, then restore everything exactly on exit.
-- All these frames are non-secure, so reparenting is taint-free.

local SP = ShamanPower

-- registry: key -> { frame = "GlobalFrameName" or function()->frame,
--                    demo = "SP:MethodName" (called with true to show sample
--                           data, false to clear), pad = px }
SP.PreviewRegistry = {}

function SP:RegisterPreview(key, def)
	self.PreviewRegistry[key] = def
end

local borrowed = {}   -- key -> { frame, parent, points = {...}, scale, shown }

local function Resolve1(f)
	if type(f) == "function" then return f() end
	if type(f) == "string" then return _G[f] end
	return f
end

-- A preview may borrow one frame (def.frame) or several (def.frames = {..}),
-- which get stacked vertically inside the panel.
local function ResolveFrames(def)
	local out = {}
	if def.frames then
		for _, f in ipairs(def.frames) do
			local fr = Resolve1(f)
			if fr then out[#out + 1] = fr end
		end
	else
		local fr = Resolve1(def.frame)
		if fr then out[1] = fr end
	end
	return out
end

-- Show a preview inside `container`. Returns the borrowed frame (or nil).
function SP:ShowPreview(key, container)
	local def = self.PreviewRegistry[key]
	if not def or not container then return nil end

	local demoFn
	if def.demo then demoFn = self[(def.demo):match("^SP:(.+)$") or def.demo] end

	-- Snapshot the frame BEFORE the demo touches it, so "was it shown?" is the
	-- real answer and not the demo's. Frames that only exist once the demo has
	-- created them count as hidden.
	if not borrowed[key] then
		local frames = ResolveFrames(def)
		local existed = {}
		for _, f in ipairs(frames) do existed[f] = true end
		if #frames == 0 and demoFn then
			pcall(demoFn, self, true)
			frames = ResolveFrames(def)
		end
		if #frames == 0 then return nil end
		local saved = {}
		for _, frame in ipairs(frames) do
			local pts = {}
			for i = 1, frame:GetNumPoints() do pts[i] = { frame:GetPoint(i) } end
			saved[#saved + 1] = {
				frame = frame, parent = frame:GetParent(), points = pts,
				scale = frame:GetScale(), shown = existed[frame] and frame:IsShown() or false,
				strata = frame:GetFrameStrata(),
			}
		end
		borrowed[key] = { saved = saved }
	end

	-- Let the module create/populate the frame with sample data.
	if demoFn then pcall(demoFn, self, true) end
	local frames = ResolveFrames(def)
	if #frames == 0 then return nil end

	local pad = def.pad or 24
	-- A container may reserve a strip at the bottom (e.g. for a caption) and
	-- cap how far the frame is enlarged (so previews stay life-sized).
	local reserve = container.previewInsetBottom or 0
	local maxScale = container.previewMaxScale or 2.5
	local cw, ch = container:GetWidth() - pad, container:GetHeight() - pad - reserve
	-- Measure the group (largest width, summed heights).
	local totalH, maxW = 0, 0
	for _, frame in ipairs(frames) do
		maxW = math.max(maxW, frame:GetWidth())
		totalH = totalH + frame:GetHeight()
	end
	totalH = totalH + (#frames - 1) * 16
	local scale = 1
	if maxW > 0 and totalH > 0 and cw > 0 and ch > 0 then
		scale = math.max(math.min(cw / maxW, ch / totalH, maxScale), 0.4)
	end
	local y = totalH / 2
	for _, frame in ipairs(frames) do
		frame:SetParent(container)
		frame:SetFrameStrata(container:GetFrameStrata())
		frame:SetFrameLevel(container:GetFrameLevel() + 5)
		frame:SetScale(scale)
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", container, "CENTER", 0, (y - frame:GetHeight() / 2) * scale + reserve / 2)
		frame:Show()
		y = y - frame:GetHeight() - 16
	end
	return frames[1]
end

-- Restore one borrowed frame to exactly how it was.
function SP:RestorePreview(key)
	local b = borrowed[key]
	if not b then return end
	local def = self.PreviewRegistry[key]
	for _, saved in ipairs(b.saved) do
		local frame = saved.frame
		frame:SetParent(saved.parent or UIParent)
		frame:SetFrameStrata(saved.strata or "MEDIUM")
		frame:SetScale(saved.scale or 1)
		frame:ClearAllPoints()
		if #saved.points > 0 then
			for _, p in ipairs(saved.points) do frame:SetPoint(unpack(p)) end
		else
			frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		end
		frame:SetShown(saved.shown)
	end
	borrowed[key] = nil
	-- Clear the sample data LAST, once the frame is back where it lives, so the
	-- module's own "what should show now" logic has the final say.
	if def and def.demo then
		local m = self[(def.demo):match("^SP:(.+)$") or def.demo]
		if m then pcall(m, self, false) end
	end
end

function SP:RestoreAllPreviews()
	for key in pairs(borrowed) do self:RestorePreview(key) end
end
