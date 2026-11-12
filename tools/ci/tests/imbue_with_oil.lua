-- client: forever
-- (Endorian, 11-11) WoW: Forever lists each weapon's temporary enchants, and a weapon can hold an oil
-- or a stone AND a shaman imbue at once. With Wizard Oil listed first the Cooldown Bar showed the
-- oil's time (29m while his imbue had 36m), its enchant as Windfury (unknown IDs fall back to
-- Windfury), and recasting the imbue changed nothing. The read takes the shaman imbue wherever it sits;
-- with no imbue on the weapon, the first enchant, as before.
local SP = ShamanPower
local W = __sim.W
if not (Enum and Enum.WeaponSlot and C_Item and C_Item.GetWeaponEnchantInfo) then skip("no list read here") end
local OIL, ROCKBITER, FLAMETONGUE = 2627, 29, 5
checkEq("Rockbiter's enchant is Rockbiter", SP.EnchantIDToImbue[ROCKBITER], 4)
check("Wizard Oil's enchant is not an imbue", SP.EnchantIDToImbue[OIL] == nil)

local real = C_Item.GetWeaponEnchantInfo
local hands = {}
C_Item.GetWeaponEnchantInfo = function(slot) return hands[slot] end
local function E(id, minutes) return { hasEnchant = true, enchantID = id, timeLeft = minutes * 60000, charges = 0 } end
local NONE = { hasEnchant = false, enchantID = 0 }
local function read(main, off)
	hands[Enum.WeaponSlot.MainHand], hands[Enum.WeaponSlot.OffHand] = main, off
	W.fireEvent("WEAPON_ENCHANT_CHANGED")   -- (the next read re-reads)
	return SPCompat.GetWeaponEnchantInfo()
end
local function minutes(ms) return ms and math.floor(ms / 60000 + 0.5) end

local has, left, _, id = read({ E(OIL, 30), E(ROCKBITER, 36) }, { NONE })
check("oil listed first: the hand has an enchant", has == true)
checkEq("oil listed first: the enchant read is Rockbiter", id, ROCKBITER)
checkEq("oil listed first: its time is Rockbiter's (36 min), not the oil's", minutes(left), 36)

has, left, _, id = read({ E(ROCKBITER, 36), E(OIL, 30) }, { NONE })
checkEq("imbue listed first: Rockbiter", id, ROCKBITER)
checkEq("imbue listed first: Rockbiter's time", minutes(left), 36)

has, left, _, id = read({ E(OIL, 30), NONE }, { NONE })
check("oil alone: the hand still has an enchant, as before", has == true)
checkEq("oil alone: the oil, as before", id, OIL)
checkEq("oil alone: the oil's time, as before", minutes(left), 30)

has, left, _, id = read({ NONE, E(ROCKBITER, 50) }, { NONE })
checkEq("imbue alone (second in the list): Rockbiter", id, ROCKBITER)

local mh, _, _, mid, oh, oleft, _, oid = read({ E(ROCKBITER, 40) }, { E(OIL, 12), E(FLAMETONGUE, 44) })
check("off hand: both hands up", mh == true and oh == true)
checkEq("off hand, oil listed first: Flametongue", oid, FLAMETONGUE)
checkEq("off hand: Flametongue's time", minutes(oleft), 44)
checkEq("main hand untouched: Rockbiter", mid, ROCKBITER)

mh, _, _, _, oh = read({ NONE }, { NONE })
check("nothing on either weapon: no enchant", mh == false and oh == false)

C_Item.GetWeaponEnchantInfo = real
W.fireEvent("WEAPON_ENCHANT_CHANGED")
finish()
