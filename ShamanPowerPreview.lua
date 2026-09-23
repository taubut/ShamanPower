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
			self.previewPaneActive = container.previewPane and true or nil
			local ok, err = pcall(demoFn, self, true)
			self.previewPaneActive = nil
			if not ok then print("|cffff4040ShamanPower setup|r: preview '" .. key .. "' failed: " .. tostring(err)) end
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
	borrowed[key].container = container   -- so the stage on it can be put away with the frame

	-- Let the module create/populate the frame with sample data. A demo may
	-- read previewPaneActive to lay itself out for the settings window's tall,
	-- narrow pane; the wizard's containers never set it.
	if demoFn then
		self.previewPaneActive = container.previewPane and true or nil
		local ok, err = pcall(demoFn, self, true)
		self.previewPaneActive = nil
		if not ok then print("|cffff4040ShamanPower setup|r: preview '" .. key .. "' failed: " .. tostring(err)) end
	end
	local frames = ResolveFrames(def)
	if #frames == 0 then return nil end

	local pad = def.pad or 24
	-- In the settings pane a re-run (a setting changed) must not flash frames
	-- the demo keeps hidden (icons on cooldown): shown once per mount there,
	-- and the demo owns their visibility from then on.
	local function showFrame(frame)
		-- a demo that runs its own show/hide (icons on cooldown, spells ticked off)
		-- marks the frames it is keeping hidden; showing them here flashed them
		if frame.spDemoHidden then return end
		if container.previewPane then
			if frame.spPaneShown then return end
			frame.spPaneShown = true
		end
		frame:Show()
	end
	-- def.stage = "player": the player's own character, dimmed, behind the
	-- borrowed frames - for displays that float near the character on screen
	-- (shield charges), so the preview says where they live.
	if def.stage == "player" then
		local stage = container.previewStage
		if not stage then
			stage = CreateFrame("PlayerModel", nil, container)
			-- the character lives in the bottom half of the box only; the display
			-- floats above the centre line (lift), so the two can never overlap,
			-- whatever the box size
			stage:SetPoint("TOPLEFT", container, "LEFT", 0, 30)
			-- stop above the caption under the preview (the container's bottom inset)
			stage:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, (container.previewInsetBottom or 0) + 60)
			stage:SetFrameLevel(container:GetFrameLevel() + 2)
			stage:SetAlpha(0.55)
			-- camera, placement and the spell visual only take once the model has
			-- loaded; applied there, so the character does not jump on the first
			-- refresh after loading
			local function dress(m)
				pcall(m.SetCamDistanceScale, m, 1.7)
				pcall(m.SetPosition, m, 0, 0, 0)   -- centred in its (lower) frame; the display sits above it
				pcall(m.SetFacing, m, 0.3)
				-- def.stageKit: a spell visual kit played on the character (Lightning Shield's orbs)
				if m.spKit and m.ApplySpellVisualKit then pcall(m.ApplySpellVisualKit, m, m.spKit, false) end
			end
			stage:SetScript("OnModelLoaded", dress)
			stage.dress = dress
			container.previewStage = stage
		end
		stage.spKit = def.stageKit
		stage.spCastKit = def.stageCastKit
		stage.spAuraKit = def.stageKit
		-- a model forgets its unit once hidden: set it every time (OnModelLoaded dresses it)
		pcall(stage.SetUnit, stage, "player")
		stage.dress(stage)
		stage:Show()
		self.previewStageActive = stage
	elseif container.previewStage then
		container.previewStage:Hide()
		if self.previewStageActive == container.previewStage then self.previewStageActive = nil end
	end
	-- A container may reserve a strip at the bottom (e.g. for a caption) and
	-- cap how far the frame is enlarged (so previews stay life-sized).
	local reserve = container.previewInsetBottom or 0
	local maxScale = container.previewMaxScale or 2.5
	-- with a character on stage the display floats above its head, not on it
	local lift = (def.stage and (def.stageLift or 70)) or 0
	-- The settings window's tall, narrow preview pane flags itself and reads
	-- the registration's `pane` hints (overlap, grid, maxScale). The wizard's
	-- containers never do, so its step pages keep their own layout.
	local hints = container.previewPane and def.pane or nil
	if hints and hints.maxScale then maxScale = hints.maxScale end
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
	-- pane hint overlap: the frames take turns (the demo lights one at a
	-- time), so they share one centred spot instead of a mostly empty stack.
	if hints and hints.overlap then
		local maxH = 0
		for _, frame in ipairs(frames) do maxH = math.max(maxH, frame:GetHeight()) end
		scale = 1
		if maxW > 0 and maxH > 0 and cw > 0 and ch > 0 then
			scale = math.max(math.min(cw / maxW, ch / maxH, maxScale), 0.4)
		end
		for _, frame in ipairs(frames) do
			frame:SetParent(container)
			frame:SetFrameStrata(container:GetFrameStrata())
			frame:SetFrameLevel(container:GetFrameLevel() + 5)
			frame:SetScale(scale)
			frame:ClearAllPoints()
			-- anchor offsets are in the frame's own scaled units: parent pixels / scale
			frame:SetPoint("CENTER", container, "CENTER", 0, (reserve / 2 + lift) / scale)
			showFrame(frame)
		end
		return frames[1]
	end
	-- pane hint grid: icons in a centred grid, enlarged to fill the pane
	if hints and hints.grid and #frames > 1 then
		local n = #frames
		local cols = math.min(hints.columns or math.ceil(math.sqrt(n)), n)
		local rows = math.ceil(n / cols)
		local maxH = 0
		for _, frame in ipairs(frames) do maxH = math.max(maxH, frame:GetHeight()) end
		local cellW, cellH = maxW + 12, maxH + 12
		scale = 1
		if maxW > 0 and maxH > 0 and cw > 0 and ch > 0 then
			scale = math.max(math.min(cw / (cols * cellW), ch / (rows * cellH), maxScale), 0.4)
		end
		for i, frame in ipairs(frames) do
			local r, c = math.floor((i - 1) / cols), (i - 1) % cols
			frame:SetParent(container)
			frame:SetFrameStrata(container:GetFrameStrata())
			frame:SetFrameLevel(container:GetFrameLevel() + 5)
			frame:SetScale(scale)
			frame:ClearAllPoints()
			-- cell geometry is in frame units already; the pixel extras are divided by the scale
			frame:SetPoint("CENTER", container, "CENTER", (c - (cols - 1) / 2) * cellW, ((rows - 1) / 2 - r) * cellH + (reserve / 2 + lift) / scale)
			showFrame(frame)
		end
		return frames[1]
	end
	if def.stage then
		-- with a character on stage (bottom half of the box) the frames stack
		-- UPWARD from just above the centre line, so none of them reaches down
		-- into the character. Offsets are in the frame's own scaled units.
		-- The upper half is all there is: shrink to fit it.
		local half = (container:GetHeight() / 2) - 140
		if totalH > 0 and half > 0 then scale = math.min(scale, half / totalH) end
		local up = 128   -- the label hangs below the number's frame: clear the character's head with it
		for i = #frames, 1, -1 do
			local frame = frames[i]
			frame:SetParent(container)
			frame:SetFrameStrata(container:GetFrameStrata())
			frame:SetFrameLevel(container:GetFrameLevel() + 5)
			frame:SetScale(scale)
			frame:ClearAllPoints()
			frame:SetPoint("BOTTOM", container, "CENTER", 0, up / scale)
			showFrame(frame)
			up = up + (frame:GetHeight() + 16) * scale
		end
		return frames[1]
	end
	local y = totalH / 2
	for _, frame in ipairs(frames) do
		frame:SetParent(container)
		frame:SetFrameStrata(container:GetFrameStrata())
		frame:SetFrameLevel(container:GetFrameLevel() + 5)
		frame:SetScale(scale)
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", container, "CENTER", 0, (y - frame:GetHeight() / 2) * scale + reserve / 2 + lift)
		showFrame(frame)
		y = y - frame:GetHeight() - 16
	end
	return frames[1]
end

-- A demo can act out its story on the staged character: "cast" reloads the
-- model (which drops the aura visual), then plays a cast animation with the
-- cast kit; "aura" puts the aura visual back. Nothing happens without a stage.
function SP:PreviewStageEvent(what)
	local stage = self.previewStageActive
	if not (stage and stage:IsShown()) then return end
	if what == "cast" then
		stage.spKit = nil                       -- the reload must not dress the orbs back on
		pcall(stage.SetUnit, stage, "player")   -- a fresh model: no aura visual
		C_Timer.After(0.3, function()
			if not stage:IsShown() then return end
			local anim = (Enum and Enum.AnimationDataEnum and Enum.AnimationDataEnum.SpellCastDirected) or 53
			pcall(stage.SetAnimation, stage, anim)
			if stage.spCastKit then pcall(stage.ApplySpellVisualKit, stage, stage.spCastKit, true) end
		end)
	elseif what == "aura" then
		stage.spKit = stage.spAuraKit
		if stage.spKit then pcall(stage.ApplySpellVisualKit, stage, stage.spKit, false) end
		pcall(stage.SetAnimation, stage, 0)
	end
end

-- Restore one borrowed frame to exactly how it was.
function SP:RestorePreview(key)
	local b = borrowed[key]
	if not b then return end
	local def = self.PreviewRegistry[key]
	if b.container and b.container.previewStage then b.container.previewStage:Hide() end
	if self.previewStageActive and b.container and self.previewStageActive == b.container.previewStage then self.previewStageActive = nil end
	for _, saved in ipairs(b.saved) do
		local frame = saved.frame
		frame.spPaneShown = nil
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
