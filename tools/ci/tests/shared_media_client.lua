-- client: both
-- LibSharedMedia-3.0 per client (the TOCs): the newest (12000005) on WoW: Forever; on Anniversary the one 3.0.9.3 shipped,
-- since 12000004 and newer report a file another addon registers that isn't there (WeakAuras 5.22.0 has one).
-- Either way every ShamanPower file registers.
local _, minor = LibStub("LibSharedMedia-3.0")
checkEq("LibSharedMedia version for this client", minor, SPCompat.FOREVER and 12000005 or 12000001)
local LSM = LibStub("LibSharedMedia-3.0")
check("our skins registered", LSM:IsValid("background", "Banto") and LSM:IsValid("background", "None"))
check("our bar textures registered", LSM:IsValid("statusbar", "Clean") and LSM:IsValid("statusbar", "ShamanPower Smooth"))
check("our sounds and fonts registered", LSM:IsValid("sound", "ShamanPower: Totem Chime") and LSM:IsValid("font", "Fira Sans"))
check("its widgets loaded", LibStub("AceGUISharedMediaWidgets-1.0", true) ~= nil)
finish()
