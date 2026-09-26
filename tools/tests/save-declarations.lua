-- Lua 5.1/LuaJIT harness. This models normal load semantics, not the beta engine.
-- No live saved-variable files are read or written.
local suffixes = {
    "DB", "_Assignments", "_EarthShieldAssignments", "_TwistAssignments",
    "_RaidCooldowns", "_RangeTracker", "_TotemLoadouts", "ErrorLog",
}
local function read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end
local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and copy(v) or v end
    return out
end
local function declaration(toc)
    return assert(toc:match("## SavedVariables: ([^\r\n]+)"))
end
local original = declaration(read("ShamanPower_Mainline.toc"))
assert(#original == 205)
assert(read("tools/SPSaveMulti/Probe.lua") == read("tools/SPSaveShare/Probe.lua"))
for _, root in ipairs({ "SPSaveMulti", "SPSaveShare" }) do
    local toc = read("tools/" .. root .. "/" .. root .. ".toc")
    assert(declaration(toc) == original:gsub("ShamanPower", root),
        "Probe declaration must exactly mirror ShamanPower after prefix replacement")
    assert(toc:find("## Interface: 120100, 16001", 1, true))
    assert(toc:find("## Version: 2.1.1", 1, true))
    assert(not toc:find("LoadSavedVariablesFirst", 1, true))
end

local function session(root, saved, failRoot, enableOwners)
    local shared = root == "SPSaveShare"
    local frames, messages, loaded = {}, {}, {}
    local env = {
        rawget = rawget, type = type, ipairs = ipairs, tostring = tostring,
        string = string, table = table, SlashCmdList = {},
        date = function() return "2026-09-18 00:00:00" end,
        IsLoggedIn = function() return false end,
        print = function(s) messages[#messages + 1] = s end,
        C_AddOns = { IsAddOnLoaded = function(name) return loaded[name] == true end },
    }
    env._G = env
    env.CreateFrame = function(kind)
        assert(kind == "Frame")
        local f = { events = {} }
        function f:RegisterEvent(e) self.events[e] = true end
        function f:UnregisterEvent(e) self.events[e] = nil end
        function f:SetScript(kind, fn) assert(kind == "OnEvent"); self.fn = fn end
        frames[#frames + 1] = f
        return f
    end
    local function fire(event, arg)
        for _, f in ipairs(frames) do
            if f.events[event] then f.fn(f, event, arg) end
        end
    end
    local function runAddon(name)
        local f = assert(loadfile("tools/" .. name .. "/Probe.lua"))
        setfenv(f, env)
        f(name, {})
    end

    runAddon(root)
    for _, suffix in ipairs(suffixes) do assert(env[root .. suffix] == nil) end
    fire("ADDON_LOADED", "UnrelatedAddon")
    assert(env[root .. "DB"] == nil)
    if saved and not failRoot then
        for _, suffix in ipairs(suffixes) do env[root .. suffix] = copy(saved[root .. suffix]) end
    end
    loaded[root] = true
    fire("ADDON_LOADED", root)
    local initialCount = env[root .. "DB"].bootCount
    fire("ADDON_LOADED", root)
    assert(env[root .. "DB"].bootCount == initialCount)

    if shared and enableOwners then
        for _, owner in ipairs({
            { addon = root .. "_RaidCooldowns", variable = root .. "_RaidCooldowns" },
            { addon = root .. "_SPRange", variable = root .. "_RangeTracker" },
        }) do
            local toc = read("tools/" .. owner.addon .. "/" .. owner.addon .. ".toc")
            assert(toc:find("## Dependencies: " .. root, 1, true))
            assert(declaration(toc) == owner.variable)
            local before = env[owner.variable]
            runAddon(owner.addon)
            assert(env[owner.variable] == before, "Owner code must not write globals")
            -- A duplicate owner's saved table normally replaces this one.
            if saved then env[owner.variable] = copy(saved[owner.variable]) end
            loaded[owner.addon] = true
            fire("ADDON_LOADED", owner.addon)
        end
    end

    fire("PLAYER_LOGIN")
    assert(#messages == 1)
    local report = messages[1]
    env.SlashCmdList[root:upper()]()
    assert(messages[2] == report)
    assert(env[root .. "DB"].bootCount == initialCount)
    fire("PLAYER_LOGIN")
    assert(#messages == 2)
    fire("PLAYER_LOGOUT")
    local nextSaved = {}
    for _, suffix in ipairs(suffixes) do
        local name = root .. suffix
        assert(env[name].loggedOut == true)
        nextSaved[name] = copy(env[name])
    end
    return nextSaved, report
end

for _, root in ipairs({ "SPSaveMulti", "SPSaveShare" }) do
    local first, firstLine = session(root, nil, false, true)
    assert(firstLine:find("loaded=0/8 DB=nil->1 log=nil->1", 1, true))
    local second, secondLine = session(root, first, false, true)
    assert(secondLine:find("loaded=8/8 DB=1->2 log=1->2 logout=8/8", 1, true))
    assert(second[root .. "DB"].bootCount == 2)
    assert(second[root .. "ErrorLog"].bootCount == 2)
    if root == "SPSaveMulti" then
        assert(secondLine:find("replaced=none", 1, true))
        for _, suffix in ipairs(suffixes) do assert(second[root .. suffix].bootCount == 2) end
    else
        assert(secondLine:find("replaced=5,6 owners=2/2", 1, true))
        assert(second[root .. "_RaidCooldowns"].bootCount == 1)
        assert(second[root .. "_RangeTracker"].bootCount == 1)
        local _, disabledLine = session(root, first, false, false)
        assert(disabledLine:find("replaced=none owners=0/2", 1, true))
    end
    local failed, failedLine = session(root, first, true, true)
    assert(failed[root .. "DB"].bootCount == 1)
    assert(failedLine:find("loaded=0/8 DB=nil->1 log=nil->1", 1, true))
    print(root .. ": declaration shape, restore, duplicate owners, failure detection PASS")
end
print("All declaration-probe tests passed")
