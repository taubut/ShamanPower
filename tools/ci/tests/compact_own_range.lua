-- client: forever
-- regime: secrets
-- (a player's report, 11-11) Compact style in a fight on WoW: Forever: the game-drawn picture of your own
-- totem (own_range_engine) sits over the button's icon spot, and on a Compact line that spot is the whole
-- line, so the totem's picture was stretched across the line. A Compact line never lights it; the icon bar
-- still does, and switching Compact on in a fight's aftermath leaves nothing lit.
local SP = ShamanPower
local W = __sim.W
local o = SP.opt
SP:RebuildOwnRangeEngine()
local btn = SP.totemButtons[3]
local e3 = SP.ownRangeEngine[3]
if not (btn and e3 and e3.main and e3.main.slots[2]) then skip("no water button or no game-drawn slots here") end

local realInfo, realUB, realUnread, realPos = SP.GetElementTotemInfo, SPCompat.UnitBuff, SPCompat.AurasUnreadable, UnitPosition
local keepCompact = o.compactStyle
local fight = false
SP.GetElementTotemInfo = function(self, e) if e == 3 then return true, GetSpellInfo(5394), GetTime() - 5, 300, nil, 3 end return false end
SPCompat.UnitBuff = function(unit, i) if not fight and i == 1 then return SPCompat.SpellName(5672) end return nil end
SPCompat.AurasUnreadable = function() return fight end
UnitPosition = function() return nil end
local function pass() SP.totemBuffCache[3] = nil; SP:InvalidateTotemInfo(); W.fireEvent("UNIT_AURA", "player", { isFullUpdate = true }); SP:UpdatePlayerTotemRange() end
local function lit() local c = e3.main.slots[2] return c and c:GetAlpha() == 1 end
local overlay = SP.activeTotemOverlays and SP.activeTotemOverlays[3]
if overlay then overlay.isActive = false end

-- the icon bar: as before, Healing Stream's picture lit in a fight
fight = true
pass()
check("icon bar in a fight: Healing Stream's picture lit over the icon", lit())
fight = false
pass()

-- Compact: never lit over the line
o.compactStyle = true
SP:ApplyCompactStyle()
SP:RebuildOwnRangeEngine()   -- (a fight's start does it: PLAYER_REGEN_DISABLED)
check("Compact is on for the water button", btn.compactLayoutOn == true)
fight = true
pass()
check("Compact in a fight: no totem picture over the line", not lit())
fight = false
pass()
check("Compact after the fight: still nothing over the line", not lit())

-- back to the icon bar: lit again in a fight
o.compactStyle = keepCompact
SP:ApplyCompactStyle()
SP:RebuildOwnRangeEngine()
if overlay then overlay.isActive = false end   -- (the button shows the totem, as at the start)
fight = true
pass()
check("back on the icon bar: lit again in a fight", lit())
fight = false

SP.GetElementTotemInfo, SPCompat.UnitBuff, SPCompat.AurasUnreadable, UnitPosition = realInfo, realUB, realUnread, realPos
SP.totemBuffCache[3] = nil
SP:InvalidateTotemInfo()
SP:UpdatePlayerTotemRange()
finish()
