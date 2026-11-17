-- client: forever
-- (3.0.9.16) Dumb (Discord): "when i use my weapon imbue it only fills the progress bar half way". The Cooldown
-- Bar's imbue button draws one bar for one imbued hand (the button's width) and two half bars for two; the fill
-- was always worked out on half the button, so one hand's bar never got past half. Now the fill is as wide as its
-- own bar: one hand at 59 of 60 minutes fills almost all of it; two hands fill their own halves; up and down bars
-- (the button's height) as before.
local SP = ShamanPower
local W = __sim.W
if not (Enum and Enum.WeaponSlot and C_Item and C_Item.GetWeaponEnchantInfo) then skip("no list read here") end
local b
for _, x in ipairs(SP.cooldownButtons or {}) do if x.spellType == "weaponImbue" then b = x end end
if not b then skip("no weapon imbue button on the Cooldown Bar here") end

local real = C_Item.GetWeaponEnchantInfo
local hands = {}
C_Item.GetWeaponEnchantInfo = function(slot) return hands[slot] end
-- the imbues assigned to the button's hands (in this style a hand counts when it holds its assigned one)
local function enchantOf(idx)
	for id, i in pairs(SP.EnchantIDToImbue or {}) do if i == idx then return id end end
end
local MAIN = enchantOf(SP:DefaultImbueIndex())
local OFF = enchantOf(SP.AssignedOffImbue and SP:AssignedOffImbue(SP:DefaultImbueIndex()) or SP:DefaultImbueIndex()) or MAIN
if not MAIN then skip("no enchant for the assigned imbue here") end
local NONE = { hasEnchant = false, enchantID = 0 }
local function E(id, minutes) return { { hasEnchant = true, enchantID = id, timeLeft = minutes * 60000, charges = 0 } } end
local keepPos = SP.opt.cdbarProgressPosition
SP.opt.cdbarProgressPosition = "bottom"   -- (Dumb's: under the icon; the default, Left, is an up and down bar)
local function pass(main, off)
	hands[Enum.WeaponSlot.MainHand], hands[Enum.WeaponSlot.OffHand] = main or { NONE }, off or { NONE }
	W.fireEvent("WEAPON_ENCHANT_CHANGED")
	SP:UpdateCooldownBar()
	if SP.UpdateCooldownBarProgressBars then SP:UpdateCooldownBarProgressBars() end
	__sim.advance(1.1)
	SP:UpdateCooldownButtons()
end
local function share(bar, bg) return bar and bg and bg:GetWidth() > 0 and bar:GetWidth() / bg:GetWidth() or 0 end
local function f2(x) return ("%.2f"):format(x or -1) end

-- one hand: 59 of 60 minutes fills almost all of its bar (the report: half)
pass(E(MAIN, 59))
check("one hand: its bar shows", b.progressBarMain and b.progressBarMain:IsShown() and b.bgBarMain:IsShown())
local one = share(b.progressBarMain, b.bgBarMain)
check("one hand at 59 of 60 min: almost all of its bar", one > 0.95 and one <= 1.001,
	f2(one) .. " (" .. f2(b.progressBarMain:GetWidth()) .. " of " .. f2(b.bgBarMain:GetWidth()) .. ")")
pass(E(MAIN, 30))
one = share(b.progressBarMain, b.bgBarMain)
check("one hand at 30 of 60 min: half of its bar", math.abs(one - 0.5) < 0.03, f2(one))

-- two hands: each fills its own half bar (a dual-wielding shaman: the sim's can't, so it is said here)
local CDW, HOW = SP.CanDualWield, SP.HasOffHandWeapon
SP.CanDualWield = function() return true end
SP.HasOffHandWeapon = function() return true end
OFF = enchantOf(SP.AssignedOffImbue and SP:AssignedOffImbue(SP:DefaultImbueIndex()) or SP:DefaultImbueIndex()) or MAIN
do
	pass(E(MAIN, 59), E(OFF, 30))
	local m, o = share(b.progressBarMain, b.bgBarMain), share(b.progressBarOff, b.bgBarOff)
	check("two hands: main hand (59 min) almost all of its half", m > 0.95 and m <= 1.001, f2(m))
	check("two hands: off hand (30 min) half of its half", math.abs(o - 0.5) < 0.03, f2(o))
	check("two hands: each bar is half the button", math.abs(b.bgBarMain:GetWidth() - b:GetWidth() / 2) < 0.6,
		("%.1f of %.1f"):format(b.bgBarMain:GetWidth(), b:GetWidth()))
end
SP.CanDualWield, SP.HasOffHandWeapon = CDW, HOW

C_Item.GetWeaponEnchantInfo = real
SP.opt.cdbarProgressPosition = keepPos
pass({ NONE }, { NONE })
finish()
