-- Identical code in both probes; only the TOC names/ownership differ.
local addonName = ...
local suffixes = {
    "DB", "_Assignments", "_EarthShieldAssignments", "_TwistAssignments",
    "_RaidCooldowns", "_RangeTracker", "_TotemLoadouts", "ErrorLog",
}
local names, before, refs = {}, {}, {}
for i, suffix in ipairs(suffixes) do names[i] = addonName .. suffix end
local initialized, restored, logoutMarkers = false, 0, 0

local function currentBoot(index)
    local t = rawget(_G, names[index])
    return type(t) == "table" and t.bootCount or nil
end

local function report()
    if not initialized then
        print(addonName .. ": waiting for its ADDON_LOADED event")
        return
    end
    local replaced = {}
    for i, name in ipairs(names) do
        if rawget(_G, name) ~= refs[i] then replaced[#replaced + 1] = tostring(i) end
    end
    local owners = ""
    if addonName == "SPSaveShare" then
        local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
        if isLoaded then
            local count = 0
            if isLoaded(addonName .. "_RaidCooldowns") then count = count + 1 end
            if isLoaded(addonName .. "_SPRange") then count = count + 1 end
            owners = " owners=" .. count .. "/2"
        else
            owners = " owners=unknown"
        end
    end
    print(string.format(
        "%s: loaded=%d/8 DB=%s->%s log=%s->%s logout=%d/8 replaced=%s%s",
        addonName, restored, tostring(before[1]), tostring(currentBoot(1)),
        tostring(before[8]), tostring(currentBoot(8)), logoutMarkers,
        #replaced > 0 and table.concat(replaced, ",") or "none", owners))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "ADDON_LOADED" then
        if loadedAddon ~= addonName or initialized then return end
        for i, name in ipairs(names) do
            local db = rawget(_G, name)
            if type(db) == "table" then
                restored = restored + 1
                before[i] = db.bootCount
                if db.loggedOut == true then logoutMarkers = logoutMarkers + 1 end
            else
                db = {}
                _G[name] = db
            end
            local count = type(before[i]) == "number" and before[i] or 0
            db.bootCount = count + 1
            db.previousSession = db.session
            db.session = date("%Y-%m-%d %H:%M:%S")
            db.loggedOut = false
            db.probeVersion = 1
            refs[i] = db
        end
        initialized = true
        self:UnregisterEvent("ADDON_LOADED")
        if IsLoggedIn() then report() end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        report()
    elseif event == "PLAYER_LOGOUT" then
        for _, name in ipairs(names) do
            local db = rawget(_G, name)
            if type(db) == "table" then db.loggedOut = true end
        end
    end
end)

local slashKey = addonName:upper()
_G["SLASH_" .. slashKey .. "1"] = "/" .. addonName:lower()
SlashCmdList[slashKey] = report
