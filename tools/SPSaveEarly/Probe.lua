-- Temporary saved-variable probe. The two addons intentionally use identical Lua.
-- Do not create the saved table at file scope: that would invalidate the test.
local addonName = ...
local dbName = addonName .. "DB"
local presentAtFile = type(rawget(_G, dbName)) == "table"
local db, previousBoot, previousLogout, presentAtLoad
local initialized = false

local function yesno(value)
    return value and "yes" or "no"
end

local function report()
    if not initialized then
        print(addonName .. ": still waiting for its ADDON_LOADED event")
        return
    end
    print(string.format(
        "%s: boot=%s->%s loaded=%s file=%s previousLogout=%s sameDB=%s",
        addonName, tostring(previousBoot), tostring(db.bootCount),
        yesno(presentAtLoad), yesno(presentAtFile), yesno(previousLogout),
        yesno(rawget(_G, dbName) == db)))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "ADDON_LOADED" then
        if loadedAddon ~= addonName or initialized then return end

        db = rawget(_G, dbName)
        presentAtLoad = type(db) == "table"
        previousBoot = presentAtLoad and db.bootCount or nil
        previousLogout = presentAtLoad and db.loggedOut == true or false
        if not presentAtLoad then
            db = {}
            _G[dbName] = db
        end

        -- Each addon owns only its own uniquely named diagnostic table.
        local count = type(previousBoot) == "number" and previousBoot or 0
        db.bootCount = count + 1
        db.previousSession = db.session
        db.session = date("%Y-%m-%d %H:%M:%S")
        db.loggedOut = false
        db.probeVersion = 1
        initialized = true
        self:UnregisterEvent("ADDON_LOADED")

        -- Also support enabling the probe after login via an addon manager.
        if IsLoggedIn() then report() end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        report()
    elseif event == "PLAYER_LOGOUT" then
        -- Never replace a table the client might have injected late.
        local current = rawget(_G, dbName)
        if type(current) == "table" then current.loggedOut = true end
    end
end)

-- Optional way to repeat either chat line: /spsavenormal or /spsaveearly.
local slashKey = addonName:upper()
_G["SLASH_" .. slashKey .. "1"] = "/" .. addonName:lower()
SlashCmdList[slashKey] = report
