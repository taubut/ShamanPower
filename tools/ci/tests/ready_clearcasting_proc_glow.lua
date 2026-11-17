-- client: forever
-- regime: gameparts
-- (3.0.9.16) Clearcasting's menu offers Glow Shape (Proc Glow among them) and, for Proc Glow, Glow Thickness,
-- but with Proc Glow picked it drew the plain square glow and ignored the thickness (found by the 11-16 sweep).
-- Now Proc Glow is the ring, looping, in the Glow Color, as thick as Glow Thickness says, made on the game's
-- aura button with nothing the game refuses (the sim's game parts regime); the other shapes keep the square glow.
local SP = ShamanPower
local W = __sim.W
local e
for _, x in ipairs(SP.ReadyReminderSpells or {}) do if x.key == "clearcasting" then e = x end end
if not (e and SP.ReadyProcs and W.onGameButton) then skip("no Clearcasting reminder or game parts regime here") end

local KN = SPCompat.KnowsSpellID
SPCompat.KnowsSpellID = function(id) if id == 16164 then return true end return KN(id) end
W.fireEvent("SPELLS_CHANGED")
local get = C_UnitAuras.GetPlayerAuraBySpellID
C_UnitAuras.GetPlayerAuraBySpellID = function(id)
	if id == 16246 then return nil end
	return get and get(id)
end
local errs = {}
local geh = geterrorhandler
geterrorhandler = function() return function(err) errs[#errs + 1] = tostring(err) end end
local function pass() W.fireEvent("UNIT_AURA", "player", {}); SP:UpdateReadyReminders(); __sim.advance(0.3) end
local function opt(k, v) SP:ReadyReminderSetIconOpt("clearcasting", k, v); pass() end

-- every Proc Glow ring, and every square glow on the game's button, drawn so far, oldest first (a redraw makes
-- new parts)
local LOOP = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local SQUARE = "Interface\\SpellActivationOverlay\\IconAlert"
local function collect(fr, out, depth)
	if depth > 14 then return out end
	for _, r in ipairs({ fr:GetRegions() }) do
		if r.GetAtlas and r:GetAtlas() == LOOP then out.rings[#out.rings + 1] = { tex = r, frame = fr } end
		if r.GetTexture and r:GetTexture() == SQUARE and W.onGameButton(fr) then out.squares[#out.squares + 1] = r end
	end
	for _, c in ipairs({ fr:GetChildren() }) do collect(c, out, depth + 1) end
	return out
end
local function scan() return collect(UIParent, { rings = {}, squares = {} }, 0) end

SP:SetReadyRemindersEnabled(true)
SP:ReadyReminderSetSpell("clearcasting", true)
opt("readyEffect", "glow")
opt("glowShape", "round")
local before = scan()
opt("glowShape", "proc")
local after = scan()
check("Proc Glow: a ring is drawn", #after.rings > #before.rings, #before.rings .. " -> " .. #after.rings)
local ring = after.rings[#after.rings]
check("no new square glow with it", #after.squares == #before.squares, #before.squares .. " -> " .. #after.squares)
check("made on the game's aura button", ring and W.onGameButton(ring.frame))
check("looping", ring and ring.frame.ProcLoopAnim and ring.frame.ProcLoopAnim:IsPlaying())
local r, g, b = 1, 1, 1
if ring then r, g, b = ring.tex:GetVertexColor() end
check("in the Glow Color", ring and math.abs(r - 0.3) < 0.02 and math.abs(g - 0.8) < 0.02 and math.abs(b - 1) < 0.02,
	("%.2f %.2f %.2f"):format(r or -1, g or -1, b or -1))
local w1 = ring and ring.frame:GetWidth() or 0
opt("glowThick", 0.5)
local thick = scan()
local ring2 = thick.rings[#thick.rings]
local w2 = ring2 and ring2.frame:GetWidth() or 0
check("Glow Thickness redraws it, thicker", ring2 ~= ring and w2 > w1 + 10, ("%.1f -> %.1f"):format(w1, w2))
opt("readyEffect", "both")
local both = scan()
check("Glow + Pulse: the ring still there", #both.rings > #thick.rings and #both.squares == #thick.squares,
	("rings %d -> %d, squares %d -> %d"):format(#thick.rings, #both.rings, #thick.squares, #both.squares))
opt("glowShape", "default")   -- (Square: the IconAlert texture; Round paints its own ring file instead)
local sq = scan()
check("Square again: the square glow, no new ring", #sq.squares > #both.squares and #sq.rings == #both.rings,
	("rings %d -> %d, squares %d -> %d"):format(#both.rings, #sq.rings, #both.squares, #sq.squares))
checkEq("nothing the game refuses, nothing in the error handler", #errs, 0, errs[1])

geterrorhandler = geh
C_UnitAuras.GetPlayerAuraBySpellID = get
SPCompat.KnowsSpellID = KN
SP:ReadyReminderResetIcon("clearcasting")
SP:ReadyReminderSetSpell("clearcasting", false)
W.fireEvent("SPELLS_CHANGED")
finish()
