--[[
    ShamanPower_TremorReminder
    Proactive Tremor Totem reminder when targeting fear-casting mobs

    Shows a Tremor Totem icon when you target a mob known to cast fears,
    even before anyone in your party gets feared.
]]

local SP = ShamanPower
if not SP then return end

-- Mark module as loaded
SP.TremorReminderLoaded = true

-- Localization
local L = LibStub("AceLocale-3.0"):GetLocale("ShamanPower")

-- Tremor Totem spell info
local TREMOR_TOTEM_NAME = GetSpellInfo(8143) or "Tremor Totem"
local TREMOR_TOTEM_ICON = select(3, GetSpellInfo(8143)) or 136108

-- Default known fear-casting mobs (from Sweb's WeakAura + additions)
local DEFAULT_FEAR_CASTERS = {
    -- TBC Dungeons
    ["Nexus Terror"] = true,
    ["Sethekk Prophet"] = true,
    ["Nazan"] = true,
    ["Coilfang Ray"] = true,
    ["Coilfang Siren"] = true,
    ["Durnholde Warden"] = true,
    ["Ambassador Hellmaw"] = true,
    ["Fel Overseer"] = true,
    ["Shadowmoon Darkcaster"] = true,
    ["Warbringer O'mrogg"] = true,
    ["Rift Keeper"] = true,
    ["Mutate Fear-Shrieker"] = true,
    ["Bloodwarder Physician"] = true,
    ["Harbinger Skyriss"] = true,
    ["Bleeding Hollow Scryer"] = true,

    -- Karazhan
    ["Nightbane"] = true,
    ["The Big Bad Wolf"] = true,
    ["Spectral Charger"] = true,
    ["Dorothee"] = true,
    ["Roar"] = true,
    ["Concubine"] = true,

    -- Magtheridon's Lair
    ["Hellfire Warder"] = true,
    ["Hellfire Channeler"] = true,

    -- Serpentshrine Cavern
    ["Coilfang Priestess"] = true,
    ["Greyheart Tidecaller"] = true,

    -- Tempest Keep
    ["Tempest-Smith"] = true,
    ["Astromancer"] = true,

    -- Black Temple
    ["Illidari Heartseeker"] = true,
    ["Bonechewer Taskmaster"] = true,
    ["Dragonmaw Wind Reaver"] = true,
    ["Ashtongue Mystic"] = true,

    -- Hyjal Summit
    ["Banshee"] = true,
    ["Crypt Fiend"] = true,

    -- Sunwell Plateau
    ["Sunblade Vindicator"] = true,

    -- Classic Dungeons
    ["Scarlet Monk"] = true,
    ["Scarlet Champion"] = true,
    ["Atal'ai Witch Doctor"] = true,
    ["Thuzadin Shadowcaster"] = true,

    -- Classic Raids
    ["Onyxia"] = true,
    ["Magmadar"] = true,
    ["Golemagg the Incinerator"] = true,
}

-- Default settings
local defaults = {
    enabled = true,
    displayMode = "icon",  -- "icon", "text", "both"
    iconSize = 64,
    textSize = 24,
    scale = 1.0,
    opacity = 100,
    showGlow = true,
    glowColor = { r = 1, g = 0.8, b = 0 },
    playSound = false,
    soundFile = "Sound\\Interface\\RaidWarning.ogg",
    soundVolume = 100,
    position = { point = "CENTER", x = 0, y = 150 },
    locked = true,
    hideWhenTremorActive = true,
    fearCasters = {},  -- User additions/removals
    useDefaultList = true,
}

-- Local state
local reminderFrame = nil
local isShowing = false
local lastTargetName = nil

-- Check if a mob name is in the fear-caster list
local function IsFearCaster(name)
    if not name then return false end

    local sv = ShamanPowerTremorReminderDB
    if not sv then return false end

    -- Check user's custom list first (can override defaults)
    if sv.fearCasters and sv.fearCasters[name] ~= nil then
        return sv.fearCasters[name]
    end

    -- Check default list if enabled
    if sv.useDefaultList and DEFAULT_FEAR_CASTERS[name] then
        return true
    end

    return false
end

-- Check if Tremor Totem is currently active
local function IsTremorTotemActive()
    for slot = 1, 4 do
        local haveTotem, totemName = GetTotemInfo(slot)
        if haveTotem and totemName and totemName:find("Tremor") then
            return true
        end
    end
    return false
end

-- Create the reminder frame
local function CreateReminderFrame()
    if reminderFrame then return reminderFrame end

    local sv = ShamanPowerTremorReminderDB

    local frame = CreateFrame("Frame", "ShamanPowerTremorReminderFrame", UIParent)
    frame:SetSize(sv.iconSize or 64, sv.iconSize or 64)
    frame:SetPoint(sv.position.point or "CENTER", UIParent, sv.position.point or "CENTER", sv.position.x or 0, sv.position.y or 150)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    -- Icon texture
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.icon:SetTexture(TREMOR_TOTEM_ICON)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Text label
    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetFont("Fonts\\FRIZQT__.TTF", sv.textSize or 24, "OUTLINE")
    frame.text:SetPoint("TOP", frame, "BOTTOM", 0, -5)
    frame.text:SetText("TREMOR!")
    frame.text:SetTextColor(1, 0.8, 0)
    frame.text:Hide()

    -- Glow (using ActionButton glow)
    frame.glow = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    frame.glow:SetPoint("TOPLEFT", -12, 12)
    frame.glow:SetPoint("BOTTOMRIGHT", 12, -12)
    frame.glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    frame.glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    frame.glow:SetVertexColor(sv.glowColor.r or 1, sv.glowColor.g or 0.8, sv.glowColor.b or 0)

    -- Glow animation - pulsing alpha and scale
    frame.glowAnim = frame.glow:CreateAnimationGroup()
    frame.glowAnim:SetLooping("REPEAT")

    -- Pulse in
    local pulseIn = frame.glowAnim:CreateAnimation("Alpha")
    pulseIn:SetFromAlpha(0.3)
    pulseIn:SetToAlpha(1.0)
    pulseIn:SetDuration(0.4)
    pulseIn:SetOrder(1)
    pulseIn:SetSmoothing("IN_OUT")

    local scaleIn = frame.glowAnim:CreateAnimation("Scale")
    scaleIn:SetScaleFrom(0.9, 0.9)
    scaleIn:SetScaleTo(1.1, 1.1)
    scaleIn:SetDuration(0.4)
    scaleIn:SetOrder(1)
    scaleIn:SetSmoothing("IN_OUT")

    -- Pulse out
    local pulseOut = frame.glowAnim:CreateAnimation("Alpha")
    pulseOut:SetFromAlpha(1.0)
    pulseOut:SetToAlpha(0.3)
    pulseOut:SetDuration(0.4)
    pulseOut:SetOrder(2)
    pulseOut:SetSmoothing("IN_OUT")

    local scaleOut = frame.glowAnim:CreateAnimation("Scale")
    scaleOut:SetScaleFrom(1.1, 1.1)
    scaleOut:SetScaleTo(0.9, 0.9)
    scaleOut:SetDuration(0.4)
    scaleOut:SetOrder(2)
    scaleOut:SetSmoothing("IN_OUT")

    -- Enable mouse for tooltip and dragging
    frame:EnableMouse(true)

    -- Tooltip
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Tremor Totem Reminder", 1, 0.82, 0)
        local targetName = UnitName("target")
        if targetName then
            GameTooltip:AddLine("Target: " .. targetName .. " (fear-caster)", 1, 0.5, 0.5)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("ALT+drag to move", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Dragging
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        local sv = ShamanPowerTremorReminderDB
        if IsAltKeyDown() and sv and not sv.locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        sv.position.point = point
        sv.position.x = x
        sv.position.y = y
    end)

    reminderFrame = frame
    return frame
end

-- Update frame appearance
local function UpdateAppearance()
    if not reminderFrame then return end

    local sv = ShamanPowerTremorReminderDB
    if not sv then return end

    local size = sv.iconSize or 64
    reminderFrame:SetSize(size, size)

    local scale = sv.scale or 1.0
    reminderFrame:SetScale(scale)

    local alpha = (sv.opacity or 100) / 100
    reminderFrame:SetAlpha(alpha)

    -- Display mode: icon, text, or both
    local mode = sv.displayMode or "icon"
    if mode == "icon" then
        reminderFrame.icon:Show()
        reminderFrame.text:Hide()
        reminderFrame.glow:ClearAllPoints()
        reminderFrame.glow:SetPoint("TOPLEFT", -12, 12)
        reminderFrame.glow:SetPoint("BOTTOMRIGHT", 12, -12)
    elseif mode == "text" then
        reminderFrame.icon:Hide()
        reminderFrame.text:Show()
        reminderFrame.text:ClearAllPoints()
        reminderFrame.text:SetPoint("CENTER", reminderFrame, "CENTER", 0, 0)
        reminderFrame.glow:Hide()
    elseif mode == "both" then
        reminderFrame.icon:Show()
        reminderFrame.text:Show()
        reminderFrame.text:ClearAllPoints()
        reminderFrame.text:SetPoint("TOP", reminderFrame, "BOTTOM", 0, -5)
        reminderFrame.glow:ClearAllPoints()
        reminderFrame.glow:SetPoint("TOPLEFT", -12, 12)
        reminderFrame.glow:SetPoint("BOTTOMRIGHT", 12, -12)
    end

    -- Update text size
    reminderFrame.text:SetFont("Fonts\\FRIZQT__.TTF", sv.textSize or 24, "OUTLINE")

    -- Glow (only show if not text-only mode)
    if sv.showGlow and mode ~= "text" then
        reminderFrame.glow:Show()
        reminderFrame.glow:SetVertexColor(sv.glowColor.r or 1, sv.glowColor.g or 0.8, sv.glowColor.b or 0)
        reminderFrame.glowAnim:Play()
    else
        reminderFrame.glow:Hide()
        reminderFrame.glowAnim:Stop()
    end
end

-- Show the reminder
local function ShowReminder()
    if isShowing then return end

    local sv = ShamanPowerTremorReminderDB
    if not sv or not sv.enabled then return end

    if not reminderFrame then
        CreateReminderFrame()
    end

    UpdateAppearance()
    reminderFrame:Show()
    isShowing = true

    if sv.showGlow then
        reminderFrame.glowAnim:Play()
    end

    -- Play sound
    if sv.playSound and sv.soundFile then
        ShamanPower:PlaySoundWithVolume(sv.soundFile, sv.soundVolume, true)
    end
end

-- Hide the reminder
local function HideReminder()
    if not isShowing then return end

    if reminderFrame then
        reminderFrame:Hide()
        reminderFrame.glowAnim:Stop()
    end
    isShowing = false
end

-- Check if we should show the reminder
local function CheckTarget()
    local sv = ShamanPowerTremorReminderDB
    if not sv or not sv.enabled then
        HideReminder()
        return
    end

    -- Check if we're targeting an attackable unit
    if not UnitExists("target") or not UnitCanAttack("player", "target") then
        HideReminder()
        lastTargetName = nil
        return
    end

    local targetName = UnitName("target")

    -- Check if target is a known fear-caster
    if not IsFearCaster(targetName) then
        HideReminder()
        lastTargetName = targetName
        return
    end

    -- Check if Tremor Totem is already active
    if sv.hideWhenTremorActive and IsTremorTotemActive() then
        HideReminder()
        lastTargetName = targetName
        return
    end

    -- Only play sound once per target
    local shouldSound = (targetName ~= lastTargetName)
    lastTargetName = targetName

    if not isShowing then
        if shouldSound and sv.playSound and sv.soundFile then
            ShamanPower:PlaySoundWithVolume(sv.soundFile, sv.soundVolume, true)
        end
    end

    ShowReminder()
end

-- Event handler frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "ShamanPower_TremorReminder" then
        -- Initialize saved variables
        if not ShamanPowerTremorReminderDB then
            ShamanPowerTremorReminderDB = {}
        end

        -- Apply defaults
        for k, v in pairs(defaults) do
            if ShamanPowerTremorReminderDB[k] == nil then
                if type(v) == "table" then
                    ShamanPowerTremorReminderDB[k] = {}
                    for k2, v2 in pairs(v) do
                        ShamanPowerTremorReminderDB[k][k2] = v2
                    end
                else
                    ShamanPowerTremorReminderDB[k] = v
                end
            end
        end

        -- Create frame (hidden)
        CreateReminderFrame()

    elseif event == "PLAYER_TARGET_CHANGED" then
        CheckTarget()

    elseif event == "PLAYER_TOTEM_UPDATE" then
        -- Re-check when totems change (might need to hide if Tremor placed)
        CheckTarget()

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Re-check on zone changes
        C_Timer.After(1, CheckTarget)
    end
end)

-- Slash commands
SLASH_SPTREMOR1 = "/sptremor"
SlashCmdList["SPTREMOR"] = function(msg)
    msg = msg:lower():trim()

    if msg == "show" then
        -- Show positioning frame
        if not reminderFrame then CreateReminderFrame() end
        reminderFrame:Show()
        reminderFrame.icon:SetDesaturated(true)
        print("|cff0070ddShamanPower|r [Tremor Reminder]: Frame shown. ALT+drag to position.")

    elseif msg == "hide" then
        if reminderFrame then
            reminderFrame:Hide()
            reminderFrame.icon:SetDesaturated(false)
        end
        isShowing = false
        print("|cff0070ddShamanPower|r [Tremor Reminder]: Frame hidden.")

    elseif msg == "test" then
        -- Force show for testing
        if not reminderFrame then CreateReminderFrame() end
        UpdateAppearance()
        reminderFrame:Show()
        reminderFrame.icon:SetDesaturated(false)
        if ShamanPowerTremorReminderDB.showGlow then
            reminderFrame.glowAnim:Play()
        end
        print("|cff0070ddShamanPower|r [Tremor Reminder]: Test alert shown.")

    elseif msg == "reset" then
        ShamanPowerTremorReminderDB.position = { point = "CENTER", x = 0, y = 150 }
        if reminderFrame then
            reminderFrame:ClearAllPoints()
            reminderFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
        end
        print("|cff0070ddShamanPower|r [Tremor Reminder]: Position reset to center.")

    elseif msg == "toggle" then
        ShamanPowerTremorReminderDB.enabled = not ShamanPowerTremorReminderDB.enabled
        local status = ShamanPowerTremorReminderDB.enabled and "enabled" or "disabled"
        print("|cff0070ddShamanPower|r [Tremor Reminder]: " .. status)
        if not ShamanPowerTremorReminderDB.enabled then
            HideReminder()
        end

    elseif msg:find("^add ") then
        local mobName = msg:sub(5):trim()
        if mobName ~= "" then
            ShamanPowerTremorReminderDB.fearCasters[mobName] = true
            print("|cff0070ddShamanPower|r [Tremor Reminder]: Added '" .. mobName .. "' to fear-caster list.")
        end

    elseif msg:find("^remove ") then
        local mobName = msg:sub(8):trim()
        if mobName ~= "" then
            ShamanPowerTremorReminderDB.fearCasters[mobName] = false
            print("|cff0070ddShamanPower|r [Tremor Reminder]: Removed '" .. mobName .. "' from fear-caster list.")
        end

    elseif msg == "list" then
        print("|cff0070ddShamanPower|r [Tremor Reminder]: Known fear-casters:")
        local count = 0
        if ShamanPowerTremorReminderDB.useDefaultList then
            for name in pairs(DEFAULT_FEAR_CASTERS) do
                if ShamanPowerTremorReminderDB.fearCasters[name] ~= false then
                    print("  - " .. name)
                    count = count + 1
                end
            end
        end
        for name, enabled in pairs(ShamanPowerTremorReminderDB.fearCasters) do
            if enabled and not DEFAULT_FEAR_CASTERS[name] then
                print("  - " .. name .. " (custom)")
                count = count + 1
            end
        end
        print("Total: " .. count .. " mobs")

    else
        -- Open options or show help
        print("|cff0070ddShamanPower|r [Tremor Reminder] Commands:")
        print("  /sptremor show - Show frame for positioning")
        print("  /sptremor hide - Hide positioning frame")
        print("  /sptremor test - Show test alert")
        print("  /sptremor reset - Reset position to center")
        print("  /sptremor toggle - Enable/disable module")
        print("  /sptremor add <mob name> - Add mob to fear-caster list")
        print("  /sptremor remove <mob name> - Remove mob from list")
        print("  /sptremor list - Show all known fear-casters")
    end
end

-- Bridge functions for main addon
function SP:TremorReminderShow()
    if not reminderFrame then CreateReminderFrame() end
    reminderFrame:Show()
    reminderFrame.icon:SetDesaturated(true)
end

function SP:TremorReminderHide()
    if reminderFrame then
        reminderFrame:Hide()
        reminderFrame.icon:SetDesaturated(false)
    end
    isShowing = false
end

function SP:TremorReminderTest()
    if not reminderFrame then CreateReminderFrame() end
    UpdateAppearance()
    reminderFrame:Show()
    reminderFrame.icon:SetDesaturated(false)
    if ShamanPowerTremorReminderDB.showGlow then
        reminderFrame.glowAnim:Play()
    end
end

function SP:TremorReminderReset()
    ShamanPowerTremorReminderDB.position = { point = "CENTER", x = 0, y = 150 }
    if reminderFrame then
        reminderFrame:ClearAllPoints()
        reminderFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end
end

function SP:UpdateTremorReminderAppearance()
    UpdateAppearance()
end

-- Get the list of default fear casters (for options UI)
function SP:GetDefaultFearCasters()
    return DEFAULT_FEAR_CASTERS
end

-- Get custom fear casters from saved vars
function SP:GetCustomFearCasters()
    if ShamanPowerTremorReminderDB then
        return ShamanPowerTremorReminderDB.fearCasters or {}
    end
    return {}
end

-- ============================================================================
-- Mob List Management Frame
-- ============================================================================

local MobListFrame = nil

local function BuildMobList()
    local sv = ShamanPowerTremorReminderDB
    if not sv then return {} end

    local mobs = {}

    -- Add defaults (if enabled and not removed)
    if sv.useDefaultList then
        for name in pairs(DEFAULT_FEAR_CASTERS) do
            if sv.fearCasters[name] ~= false then
                table.insert(mobs, { name = name, isCustom = false })
            end
        end
    end

    -- Add custom mobs
    for name, enabled in pairs(sv.fearCasters) do
        if enabled and not DEFAULT_FEAR_CASTERS[name] then
            table.insert(mobs, { name = name, isCustom = true })
        end
    end

    table.sort(mobs, function(a, b) return a.name < b.name end)
    return mobs
end

function SP:ShowMobList()
    if MobListFrame then
        MobListFrame:Show()
        SP:RefreshMobList()
        return
    end

    -- Create main window
    local f = CreateFrame("Frame", "SPTremorMobListFrame", UIParent, "BackdropTemplate")
    f:SetSize(320, 400)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Fear Caster Mob List")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Add mob section
    local addLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    addLabel:SetPoint("TOPLEFT", 20, -45)
    addLabel:SetText("Add Mob:")

    local editBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    editBox:SetSize(150, 20)
    editBox:SetPoint("LEFT", addLabel, "RIGHT", 10, 0)
    editBox:SetAutoFocus(false)
    f.editBox = editBox

    local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    addBtn:SetSize(50, 22)
    addBtn:SetPoint("LEFT", editBox, "RIGHT", 5, 0)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local name = editBox:GetText():trim()
        if name ~= "" then
            ShamanPowerTremorReminderDB.fearCasters[name] = true
            editBox:SetText("")
            SP:RefreshMobList()
        end
    end)

    editBox:SetScript("OnEnterPressed", function() addBtn:Click() end)

    -- Add target button
    local targetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    targetBtn:SetSize(90, 22)
    targetBtn:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", 0, -8)
    targetBtn:SetText("Add Target")
    targetBtn:SetScript("OnClick", function()
        local name = UnitName("target")
        if name and UnitCanAttack("player", "target") then
            ShamanPowerTremorReminderDB.fearCasters[name] = true
            SP:RefreshMobList()
        end
    end)

    -- List container with scroll
    local listBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    listBg:SetPoint("TOPLEFT", 15, -95)
    listBg:SetPoint("BOTTOMRIGHT", -15, 35)
    listBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    listBg:SetBackdropColor(0, 0, 0, 0.5)
    listBg:SetClipsChildren(true)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "SPTremorMobListScroll", listBg, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 5)

    -- Create row frames
    local ROW_HEIGHT = 20
    local rows = {}
    local numVisibleRows = math.floor(scrollFrame:GetHeight() / ROW_HEIGHT)

    for i = 1, 15 do
        local row = CreateFrame("Button", nil, listBg)
        row:SetSize(scrollFrame:GetWidth(), ROW_HEIGHT)
        row:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.1)
        bg:Hide()
        row.bg = bg

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", 5, 0)
        text:SetJustifyH("LEFT")
        row.text = text

        local customTag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        customTag:SetPoint("RIGHT", -25, 0)
        customTag:SetTextColor(0.3, 1, 0.3)
        row.customTag = customTag

        local delBtn = CreateFrame("Button", nil, row)
        delBtn:SetSize(16, 16)
        delBtn:SetPoint("RIGHT", -3, 0)
        delBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
        delBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
        row.delBtn = delBtn

        row:SetScript("OnEnter", function() bg:Show() end)
        row:SetScript("OnLeave", function() bg:Hide() end)

        rows[i] = row
    end

    f.scrollFrame = scrollFrame
    f.rows = rows

    -- Count label
    local countLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLabel:SetPoint("BOTTOMLEFT", 20, 12)
    countLabel:SetTextColor(0.7, 0.7, 0.7)
    f.countLabel = countLabel

    MobListFrame = f
    SP:RefreshMobList()
end

function SP:RefreshMobList()
    if not MobListFrame then return end

    local mobs = BuildMobList()
    local rows = MobListFrame.rows
    local scrollFrame = MobListFrame.scrollFrame
    local ROW_HEIGHT = 20

    FauxScrollFrame_Update(scrollFrame, #mobs, #rows, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(scrollFrame)

    for i, row in ipairs(rows) do
        local idx = i + offset
        if idx <= #mobs then
            local mob = mobs[idx]
            row.text:SetText(mob.name)
            row.customTag:SetText(mob.isCustom and "(custom)" or "")
            row.delBtn:SetScript("OnClick", function()
                if mob.isCustom then
                    ShamanPowerTremorReminderDB.fearCasters[mob.name] = nil
                else
                    ShamanPowerTremorReminderDB.fearCasters[mob.name] = false
                end
                SP:RefreshMobList()
            end)
            row:Show()
        else
            row:Hide()
        end
    end

    MobListFrame.countLabel:SetText(#mobs .. " mobs")

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function() SP:RefreshMobList() end)
    end)
end

function SP:HideMobList()
    if MobListFrame then MobListFrame:Hide() end
end

function SP:ToggleMobList()
    if MobListFrame and MobListFrame:IsShown() then
        SP:HideMobList()
    else
        SP:ShowMobList()
    end
end
