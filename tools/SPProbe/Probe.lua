-- SPProbe: announces which per-flavor TOC the client chose to load.
local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	local flavor = getMeta and getMeta("SPProbe", "X-Flavor") or "?"
	print(string.format(
		"|cff3fa9f5SPProbe|r loaded TOC: |cffffd100%s|r  interface: %s  WOW_PROJECT_ID: %s",
		tostring(flavor), tostring(select(4, GetBuildInfo())), tostring(WOW_PROJECT_ID)))
end)
