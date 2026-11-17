-- ============================================================================
-- ShamanPower Ready Reminders: Clearcasting (3.0.9.14, WoW: Forever; a Discord ask, 11-15)
-- A Ready Reminder that shows a buff while it is on you, instead of a cooldown: Clearcasting
-- (16246), from the Elemental talent Elemental Focus (16164). It looks like every reminder (Size,
-- Opacity, Icon Shape, Background, Border, its name), plays its Effect (Glow, Pulse, both) while
-- the buff is on you, and its Sound when the buff comes.
--
-- In a fight the game hides your buffs from addons, so the game draws it: the reminder's look
-- hangs on the button of an AuraContainer slot filtered to the buff, which the game shows only
-- while the buff is on you. Out of a fight the buff is read: the reminder hides while it is not
-- on you (no hole in a row or the grid); in a fight it stays and the game decides what is drawn.
-- It is built out of combat (a setting changed in a fight lands after it). The settings
-- previews and Unlock UI draw it with frames of our own (Demo).
-- ============================================================================

local SP = ShamanPower
if not SP then return end
local API = SP.ReadyProcAPI   -- the Ready Reminders file's own helpers (it loads first, shamans only)
if not API then return end

local IconOpt, color, Buff = API.IconOpt, API.color, API.Buff
local secret = issecretvalue or function() return false end
local GLOW_FILE = "Interface\\SpellActivationOverlay\\IconAlert"

local P = { of = {} }   -- [reminder frame] = its state
SP.ReadyProcs = P

local function stateOf(f)
	local st = P.of[f]
	if not st then
		st = {}
		P.of[f] = st
		f.procSt = st
	end
	return st
end

local function iconFile(e)
	local id = e.proc.buff
	local t = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
	return t or (GetSpellTexture and GetSpellTexture(id)) or e.proc.icon or 136170   -- (Spell_Shadow_ManaBurn: Clearcasting's own)
end

-- everything its look is built from: a change means a new build (rare: a menu click)
local function signature(e)
	local s = IconOpt(e, "iconSize") or 48
	local bc = IconOpt(e, "borderColor")
	local gc = IconOpt(e, "glowColor")
	return table.concat({ s, tostring(IconOpt(e, "iconShape")), tostring(SP.IconShapeOf and SP:IconShapeOf("ready")),
		tostring(IconOpt(e, "hideBackground")), tostring(IconOpt(e, "hideBorder")),
		tostring(bc and (bc.r or bc[1])) .. tostring(bc and (bc.g or bc[2])) .. tostring(bc and (bc.b or bc[3])),
		tostring(IconOpt(e, "readyEffect") or "glow"), tostring(IconOpt(e, "glowShape") or (SP.opt and SP.opt.glowShape)),
		tostring(gc and (gc.r or gc[1])) .. tostring(gc and (gc.g or gc[2])) .. tostring(gc and (gc.b or gc[3])),
		tostring(IconOpt(e, "glowThick")) }, "|")   -- (3.0.9.16: Proc Glow's Glow Thickness)
end

-- the reminder's look on `host` (the game's button, or a frame of ours): backing, icon, edge,
-- and the Effect (a glow breathing round it, the icon breathing in size), all shown with the host
local function draw(host, e)
	local s = IconOpt(e, "iconSize") or 48
	local parts = Buff.NewParts(host)
	local hideBg = IconOpt(e, "hideBackground") and true or false
	local ed = (s >= 24) and 2 or 1
	parts.bg:SetColorTexture(0, 0, 0, 0.6); parts.bg:SetShown(not hideBg)
	parts.icon:ClearAllPoints()
	parts.icon:SetPoint("TOPLEFT", parts.art, "TOPLEFT", ed, -ed); parts.icon:SetPoint("BOTTOMRIGHT", parts.art, "BOTTOMRIGHT", -ed, ed)
	parts.icon:SetTexture(iconFile(e)); parts.icon:Show()
	local own = IconOpt(e, "iconShape")
	Buff.Shape(parts, own)
	local r, g, b = color(IconOpt(e, "borderColor"), 0.2, 0.7, 1.0)
	Buff.Edges(parts, ed, ed, r, g, b, not hideBg and not IconOpt(e, "hideBorder"), own)
	parts.time:Hide()
	local fx = IconOpt(e, "readyEffect") or "glow"
	local gr, gg, gb = color(IconOpt(e, "glowColor"), 0.3, 0.8, 1.0)
	local shape = IconOpt(e, "glowShape") or (SP.opt and SP.opt.glowShape) or "default"
	if (fx == "glow" or fx == "both") and shape == "proc" and SP.ProcGlow_Plain and SP.ProcGlowOptions then
		-- (3.0.9.16) Proc Glow: the ring, in the Glow Color and at the Glow Thickness its menu offers (it drew the
		-- square glow before). Made on a frame of ours the size of the icon, never a pooled one moved in: the game
		-- refuses that on its aura button (the 3.0.9.15 Maelstrom fix)
		local c = { gr, gg, gb, 1 }
		if gr > 0.98 and gg > 0.98 and gb > 0.98 then c = nil end   -- (white: the game's gold)
		local gf = CreateFrame("Frame", nil, host)
		gf:SetSize(s, s); gf:SetPoint("CENTER", host, "CENTER", 0, 0)
		gf:SetFrameLevel(parts.art:GetFrameLevel() + 2); gf:EnableMouse(false)
		SP.ProcGlow_Plain(gf, SP:ProcGlowOptions(gf, c, "rp", true, IconOpt(e, "glowThick") or SP.PROC_GLOW_OUT or 0.2))
		parts.glow = gf
	elseif fx == "glow" or fx == "both" then
		local gf = CreateFrame("Frame", nil, host)
		gf:SetAllPoints(host); gf:SetFrameLevel(parts.art:GetFrameLevel() + 2); gf:EnableMouse(false)
		local t = gf:CreateTexture(nil, "OVERLAY", nil, 1)
		t:SetPoint("TOPLEFT", host, "TOPLEFT", -10, 10); t:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 10, -10)
		t:SetTexture(GLOW_FILE)
		t:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
		if shape ~= "proc" and SP.PaintGlowShape then SP:PaintGlowShape(t, shape) end
		t:SetBlendMode("ADD")
		t:SetVertexColor(gr, gg, gb)
		local ag = gf:CreateAnimationGroup(); ag:SetLooping("REPEAT")
		local a1 = ag:CreateAnimation("Alpha"); a1:SetFromAlpha(0.15); a1:SetToAlpha(0.8); a1:SetDuration(0.5); a1:SetOrder(1)
		local a2 = ag:CreateAnimation("Alpha"); a2:SetFromAlpha(0.8); a2:SetToAlpha(0.15); a2:SetDuration(0.5); a2:SetOrder(2)
		ag:Play()
		parts.glow = gf
	end
	if fx == "pulse" or fx == "both" then
		local pf = CreateFrame("Frame", nil, host)
		pf:SetAllPoints(host); pf:SetFrameLevel(parts.art:GetFrameLevel() + 1); pf:EnableMouse(false)
		local t = pf:CreateTexture(nil, "ARTWORK")
		t:SetPoint("TOPLEFT", pf, "TOPLEFT", ed, -ed); t:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -ed, ed)
		t:SetTexture(iconFile(e)); t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		if SP.ShapeIconTexture then SP:ShapeIconTexture(t, t, "ready") end
		local ag = pf:CreateAnimationGroup(); ag:SetLooping("REPEAT")
		local p1 = ag:CreateAnimation("Scale"); p1:SetScale(1.12, 1.12); p1:SetDuration(0.45); p1:SetOrder(1)
		local p2 = ag:CreateAnimation("Scale"); p2:SetScale(1 / 1.12, 1 / 1.12); p2:SetDuration(0.45); p2:SetOrder(2)
		ag:Play()
		parts.pulse = pf
	end
	return parts
end

-- ---------------------------------------------------------------------------
-- The game's parts (WoW: Forever): one AuraContainer slot on the buff, built out of combat
-- ---------------------------------------------------------------------------
local function engineOK() return Buff.Engine() and true or false end

local function dropEngine(st)
	local c = st.c
	if not c then return end
	pcall(c.SetEnabled, c, false)
	pcall(c.SetUnit, c, "none")
	c:Hide()
	if st.holder then st.holder:Hide() end
	st.c, st.holder, st.button = nil, nil, nil
end

local function buildEngine(f, st, e)
	dropEngine(st)
	local holder = CreateFrame("Frame", nil, f)
	holder:SetAllPoints(f); holder:EnableMouse(false)
	holder:SetFrameLevel(f:GetFrameLevel() + 1)
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, holder, "CustomAuraContainerTemplate")
	if not (ok and c and type(c.AddAuraSlot) == "function") then st.failed = true return false end
	c:ClearAllPoints(); c:SetSize(1, 1); c:SetPoint("CENTER", f, "CENTER", 0, 0)
	c:SetFrameLevel(holder:GetFrameLevel() + 1)
	if c.SetEditModePreviewEnabled then pcall(c.SetEditModePreviewEnabled, c, false) end   -- (Edit Mode's made-up auras: never here)
	local made = false
	local okSlot = pcall(c.AddAuraSlot, c, "proc", "HELPFUL|PLAYER", {
		candidateFilters = { includeSpellIDs = e.proc.map },
		initializeFrame = function(button)
			button:ClearAllPoints()
			button:SetAllPoints(f)
			if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
			if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
			local host = CreateFrame("Frame", nil, button)
			host:SetAllPoints(f); host:EnableMouse(false)
			draw(host, e)
			-- its Sound when it comes in a fight: a frame of ours on the game's button says when the button
			-- shows (a hook on the game's own button is refused). A refused hook is no error: then no sound in
			-- a fight (out of one the buff is read: P.Pass)
			local mark = CreateFrame("Frame", nil, button)
			mark:SetAllPoints(f); mark:EnableMouse(false)
			st.soundHook = pcall(mark.HookScript, mark, "OnShow", function()
				if InCombatLockdown() then API.readySound(f) end
			end) and true or false
			st.button = button
			made = true
		end,
	})
	if not (okSlot and made) then
		pcall(c.SetEnabled, c, false); c:Hide()
		st.failed = true
		return false
	end
	pcall(c.SetUnit, c, "player")
	pcall(c.SetEnabled, c, true)
	if c.UpdateAllAuras then pcall(c.UpdateAllAuras, c) end
	st.c, st.holder, st.failed = c, holder, nil
	return true
end

local function ensureEngine(f, st, e)
	if st.c and st.engineSig == st.want then
		if not st.cOn then pcall(st.c.SetEnabled, st.c, true); st.cOn = true end
		return true
	end
	if InCombatLockdown() or (SP.GameAuraButtonsLocked and SP:GameAuraButtonsLocked()) then return st.c ~= nil end
	local ok = buildEngine(f, st, e)
	st.engineSig, st.cOn = st.want, ok
	return ok
end

-- ---------------------------------------------------------------------------
-- Our own frames: the previews and Unlock UI (the buff shown as if it were on you)
-- ---------------------------------------------------------------------------
local function demoParts(f, st, e)
	if st.demo and st.demoSig == st.want then return st.demo end
	if st.demo then st.demo:Hide() end
	local d = CreateFrame("Frame", nil, f)
	d:SetAllPoints(f); d:EnableMouse(false)
	d:SetFrameLevel(f:GetFrameLevel() + 3)
	draw(d, e)
	st.demo, st.demoSig = d, st.want
	return d
end

-- ---------------------------------------------------------------------------
-- What the Ready Reminders file calls
-- ---------------------------------------------------------------------------
-- The reminder's own parts step aside: the buff's look draws it. Any setting, a theme, an import; in a
-- fight too (only the size and the parts' alpha change then).
function P.Appearance(f)
	local e = f.entry
	local st = stateOf(f)
	local s = IconOpt(e, "iconSize") or 48
	f:SetSize(s, s)
	f.bg:Hide(); f.icon:Hide(); f.border:Hide()
	if f.ring then f.ring:Hide() end
	f.cooldown:Hide(); f.overlay:Hide(); f.bar:Hide(); f.glow:Hide()
	f.count:SetText("")
	st.want = signature(e)
	if st.demo and st.demo:IsShown() and st.demoSig ~= st.want then demoParts(f, st, e):Show() end
end

-- out of a fight: is the buff on you? (nil: the game would not say)
local function present(e)
	local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
	if not get then return nil end
	local ok, a = pcall(get, e.proc.buff)
	if not ok or secret(a) then return nil end
	return type(a) == "table"
end

-- each pass, while the reminder is in use
function P.Pass(f, inCombat)
	local e = f.entry
	local st = stateOf(f)
	if not st.want then P.Appearance(f) end
	if st.demo then st.demo:Hide() end
	local visible = true
	if engineOK() then
		ensureEngine(f, st, e)
		if not inCombat then
			local on = present(e)
			if on ~= nil then
				visible = on
				if on and st.was == false then API.readySound(f) end   -- (in a fight: the mark's OnShow)
				st.was = on
			end
		else
			st.was = nil   -- (hidden in a fight: the game's button says when it comes)
		end
	else
		-- (no game parts here: our own frames, from what can be read)
		local on = present(e)
		visible = on == true
		if on and st.was == false then API.readySound(f) end
		st.was = on
		if visible then demoParts(f, st, e):Show() end
	end
	f.gridReady = visible
	if visible then
		if not f:IsShown() then f:Show() end
	elseif f:IsShown() then
		f:Hide()
	end
	if inCombat then API.mouseOff(f) else API.mouseBack(f) end   -- (in a fight the mouse goes through it)
	local a = IconOpt(e, "opacity") or 1
	f:SetAlpha(a * (f.fade or 1)); f.fadeBase = a
end

-- hidden out of combat by Only In Combat (or Hide In Town): its game parts made now, so the first fight has them
function P.Prepare(f)
	if InCombatLockdown() or not engineOK() then return end
	local st = stateOf(f)
	if not st.want then P.Appearance(f) end
	ensureEngine(f, st, f.entry)
end

-- off screen (switched off, the module off): the game's slot rests
function P.Idle(f)
	local st = f and P.of[f]
	if not st then return end
	if st.c and st.cOn then pcall(st.c.SetEnabled, st.c, false); st.cOn = false end
	st.was = nil
	if st.demo then st.demo:Hide() end
end

-- the previews, the setup tour and Unlock UI: its look as if the buff were on you
function P.Demo(f)
	local st = stateOf(f)
	if not st.want then P.Appearance(f) end
	demoParts(f, st, f.entry):Show()
	API.mouseBack(f)
	f.gridReady = true
end

-- the support code's line
function P.Diag(f)
	local st = f and P.of[f]
	return string.format("clearcasting engine=%s built=%s failed=%s sound-in-fight=%s",
		tostring(engineOK()), tostring(st ~= nil and st.c ~= nil), tostring(st and st.failed or false),
		tostring(st and st.soundHook))
end
