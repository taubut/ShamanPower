-- Lua 5.1/LuaJIT test harness; never touches live saved-variable files.
local base = "tools/"
local modes = { "Normal", "Early" }

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and copy(v) or v end
    return out
end

local function read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

assert(read(base .. "SPSaveNormal/Probe.lua") == read(base .. "SPSaveEarly/Probe.lua"),
    "The probe Lua must remain identical")

local function session(mode, saved, failRestore, lateRestore)
    local name = "SPSave" .. mode
    local key = name .. "DB"
    local frames, output = {}, {}
    local env = {
        type = type, rawget = rawget, tostring = tostring, string = string,
        SlashCmdList = {},
        date = function() return "2026-09-18 00:00:00" end,
        IsLoggedIn = function() return false end,
        print = function(s) output[#output + 1] = s end,
    }
    env._G = env
    env.CreateFrame = function(kind)
        assert(kind == "Frame")
        local f = { events = {} }
        function f:RegisterEvent(event) self.events[event] = true end
        function f:UnregisterEvent(event) self.events[event] = nil end
        function f:SetScript(script, fn)
            assert(script == "OnEvent")
            self.handler = fn
        end
        frames[#frames + 1] = f
        return f
    end
    local function fire(event, arg)
        for _, f in ipairs(frames) do
            if f.events[event] then f.handler(f, event, arg) end
        end
    end

    local toc = read(base .. name .. "/" .. name .. ".toc")
    assert(toc:find("## Interface: 120100, 16001", 1, true))
    assert(toc:find("## Version: 2.1.1", 1, true))
    assert(toc:find("## SavedVariables: " .. key .. "\n", 1, true))
    local early = toc:find("## LoadSavedVariablesFirst: 1", 1, true) ~= nil
    assert(early == (mode == "Early"))

    if saved and not failRestore and not lateRestore and early then
        env[key] = copy(saved)
    end
    local chunk = assert(loadfile(base .. name .. "/Probe.lua"))
    setfenv(chunk, env)
    chunk(name, {})
    if not early or not saved or failRestore or lateRestore then
        assert(env[key] == nil, "Probe allocated a DB at file scope")
    end
    fire("ADDON_LOADED", "UnrelatedAddon")
    if env[key] then assert(env[key].bootCount == saved.bootCount) end
    if saved and not failRestore and not lateRestore and not early then
        env[key] = copy(saved)
    end
    fire("ADDON_LOADED", name)
    local initializedDB = env[key]
    local firstCount = initializedDB.bootCount
    fire("ADDON_LOADED", name)
    assert(env[key].bootCount == firstCount, "Duplicate event incremented boot count")

    if lateRestore then env[key] = copy(assert(saved)) end
    fire("PLAYER_LOGIN")
    assert(#output == 1, "Expected one automatic report")
    local automatic = output[1]
    env.SlashCmdList[name:upper()]()
    assert(output[2] == automatic, "Repeating a report changed it")
    assert(initializedDB.bootCount == firstCount, "Report mutated counter")
    fire("PLAYER_LOGIN")
    assert(#output == 2, "Duplicate login printed again")

    fire("PLAYER_LOGOUT")
    assert(env[key].loggedOut == true)
    return copy(env[key]), automatic
end

for _, mode in ipairs(modes) do
    local first, firstLine = session(mode)
    assert(first.bootCount == 1)
    assert(firstLine:find("boot=nil->1 loaded=no file=no", 1, true))
    assert(firstLine:find("previousLogout=no sameDB=yes", 1, true))

    first.sentinel = "keep me"
    local second, line = session(mode, first)
    assert(second.bootCount == 2)
    assert(second.sentinel == "keep me")
    assert(line:find("boot=1->2 loaded=yes", 1, true))
    assert(line:find("file=" .. (mode == "Early" and "yes" or "no"), 1, true))
    assert(line:find("previousLogout=yes sameDB=yes", 1, true))

    local missing, missingLine = session(mode, first, true)
    assert(missing.bootCount == 1)
    assert(missing.sentinel == nil)
    assert(missingLine:find("loaded=no file=no", 1, true))

    local late, lateLine = session(mode, first, false, true)
    assert(late.bootCount == first.bootCount, "Late injected data was overwritten")
    assert(late.sentinel == "keep me")
    assert(lateLine:find("sameDB=no", 1, true))
    print(mode .. ": first load, successful restore, failed restore, late restore PASS")
end
print("All save-probe tests passed")
