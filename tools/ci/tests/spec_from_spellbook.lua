-- client: forever
-- (3.0.9.14) WoW: Forever has no talent-tab points (GetTalentTabInfo is gone, measured): the spec is read from
-- the spell book. Rage of the Farseer = Enhancement, Lightning Mastery = Elemental, Riptide = Restoration. An
-- Enhancement shaman with Restoration points (Riptide too) is still Enhancement.
local SP = ShamanPower
local KN = SPCompat.KnowsSpellID
local has = {}
local SPEC = { [425336] = true, [16166] = true, [408521] = true, [61295] = true }   -- (the sim knows every spell)
SPCompat.KnowsSpellID = function(id) if SPEC[id] then return has[id] == true end return KN(id) end
local function as(t) has = t; return SP.ShareSpecIndex() end
checkEq("Rage of the Farseer: Enhancement", as({ [425336] = true }), 2)
checkEq("Lightning Mastery: Elemental", as({ [16166] = true }), 3)
checkEq("Riptide: Restoration", as({ [408521] = true }), 1)
checkEq("Rage of the Farseer and Riptide: Enhancement", as({ [425336] = true, [408521] = true }), 2)
SPCompat.KnowsSpellID = KN
finish()
