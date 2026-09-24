-- ============================================================================
-- Fonts and sounds that ship with ShamanPower, registered with LibSharedMedia
-- so they appear in every font and sound list (ShamanPower's and any other
-- addon's that reads LibSharedMedia). Fonts: SIL Open Font License, see
-- Media/Fonts. Sounds: made for ShamanPower.
-- ============================================================================

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if not LSM then return end

local FONTS = "Interface\\AddOns\\ShamanPower\\Media\\Fonts\\"
local SOUNDS = "Interface\\AddOns\\ShamanPower\\Media\\Sounds\\"
-- Western (Latin-script) client languages only: LibSharedMedia leaves a font out
-- on koKR, ruRU, zhCN and zhTW clients unless it is flagged for them, and these
-- fonts are not flagged, so they are not offered there
local LATIN = LSM.LOCALE_BIT_western

for name, file in pairs({
	["Barlow Condensed"]     = "BarlowCondensed-SemiBold.ttf",
	["Bebas Neue"]           = "BebasNeue-Regular.ttf",
	["Black Ops One"]        = "BlackOpsOne-Regular.ttf",
	["Chakra Petch"]         = "ChakraPetch-SemiBold.ttf",
	["Fira Sans"]            = "FiraSans-SemiBold.ttf",
	["Oxanium"]              = "Oxanium-SemiBold.ttf",
	["Rajdhani"]             = "Rajdhani-SemiBold.ttf",
	["Russo One"]            = "RussoOne-Regular.ttf",
	["Saira Semi Condensed"] = "SairaSemiCondensed-SemiBold.ttf",
	["Teko"]                 = "Teko-Medium.ttf",
}) do
	LSM:Register("font", name, FONTS .. file, LATIN)
end

for name, file in pairs({
	["ShamanPower: Totem Chime"] = "ShamanPower-Totem-Chime.ogg",
	["ShamanPower: Shield Pop"]  = "ShamanPower-Shield-Pop.ogg",
	["ShamanPower: Ready Ping"]  = "ShamanPower-Ready-Ping.ogg",
	["ShamanPower: War Horn"]    = "ShamanPower-War-Horn.ogg",
	["ShamanPower: Water Drop"]  = "ShamanPower-Water-Drop.ogg",
	["ShamanPower: Earth Thud"]  = "ShamanPower-Earth-Thud.ogg",
	["ShamanPower: Thunder"]     = "ShamanPower-Thunder.ogg",
}) do
	LSM:Register("sound", name, SOUNDS .. file)
end
