local silent = false
--[==[@debug@
silent = true
--@end-debug@]==]

local L = LibStub("AceLocale-3.0"):NewLocale("ShamanPower", "enUS", true, silent)
if not L then return end

-- General
L["SHAMANPOWER_NAME"] = "ShamanPower"

-- Minimap
L["MINIMAP_ICON_TOOLTIP"] = "|cffffffffLeft-Click|r to toggle the assignment window\n|cffffffffRight-Click|r to open options"

-- UI Elements
L["Auto-Drop"] = "Auto-Drop"
L["Auto-Assign"] = "Auto-Assign"
L["Clear"] = "Clear"
L["Refresh"] = "Refresh"
L["Options"] = "Options"

-- Elements
L["Earth"] = "Earth"
L["Fire"] = "Fire"
L["Water"] = "Water"
L["Air"] = "Air"
L["Weapon"] = "Weapon"

-- Buttons
L["Drag Handle"] = "Drag Handle"
L["Auto Drop Button"] = "Auto Drop Button"
L["Element Buttons"] = "Element Buttons"
L["Shaman Buttons"] = "Shaman Buttons"

-- Tooltips
L["DRAGHANDLE_TOOLTIP"] = "|cffffffffLeft-Click|r Lock/Unlock ShamanPower\n|cffffffffLeft-Click-Hold|r Move ShamanPower\n|cffffffffRight-Click|r Open Totem Assignments\n|cffffffffShift-Right-Click|r Open Options"
L["AUTO_DROP_TOOLTIP"] = "Automatically drop assigned totems"

-- Settings
L["Settings"] = "Settings"
L["Buttons"] = "Buttons"
L["Totems"] = "Totems"
L["Display"] = "Display"

L["Enable ShamanPower"] = "Enable ShamanPower"
L["[Enable/Disable] ShamanPower"] = "[Enable/Disable] ShamanPower"
L["[Enable/Disable] ShamanPower in Party"] = "[Enable/Disable] ShamanPower in Party"
L["[Enable/Disable] ShamanPower while Solo"] = "[Enable/Disable] ShamanPower while Solo"
L["[Show/Hide] Minimap Icon"] = "[Show/Hide] Minimap Icon"
L["[Show/Hide] The ShamanPower Tooltips"] = "[Show/Hide] The ShamanPower Tooltips"

L["Show in Party"] = "Show in Party"
L["Show when Solo"] = "Show when Solo"
L["Show Tooltips"] = "Show Tooltips"
L["Minimap Icon"] = "Minimap Icon"

L["Background Textures"] = "Background Textures"
L["Borders"] = "Borders"
L["Buff Button Layout"] = "Buff Button Layout"

-- Status colors
L["Fully Buffed"] = "All Totems"
L["Partially Buffed"] = "Some Totems"
L["Needs Buffs"] = "No Totems"
L["None Buffed"] = "No Totems"
L["Special Attention"] = "Special Attention"
L["Change the status colors of the totem buttons"] = "Change the status colors of the totem buttons"

-- Totem names (these will be pulled from spell data)
L["Strength of Earth"] = "Strength of Earth"
L["Stoneskin"] = "Stoneskin"
L["Tremor"] = "Tremor"
L["Earthbind"] = "Earthbind"
L["Stoneclaw"] = "Stoneclaw"
L["Earth Elemental"] = "Earth Elemental"

L["Totem of Wrath"] = "Totem of Wrath"
L["Searing"] = "Searing"
L["Magma"] = "Magma"
L["Fire Nova"] = "Fire Nova"
L["Flametongue"] = "Flametongue"
L["Frost Resistance"] = "Frost Resistance"
L["Fire Elemental"] = "Fire Elemental"

L["Mana Spring"] = "Mana Spring"
L["Healing Stream"] = "Healing Stream"
L["Mana Tide"] = "Mana Tide"
L["Poison Cleansing"] = "Poison Cleansing"
L["Disease Cleansing"] = "Disease Cleansing"
L["Fire Resistance"] = "Fire Resistance"

L["Windfury"] = "Windfury"
L["Grace of Air"] = "Grace of Air"
L["Wrath of Air"] = "Wrath of Air"
L["Tranquil Air"] = "Tranquil Air"
L["Grounding"] = "Grounding"
L["Nature Resistance"] = "Nature Resistance"
L["Windwall"] = "Windwall"
L["Sentry"] = "Sentry"

-- Weapon enchants
L["Windfury Weapon"] = "Windfury Weapon"
L["Flametongue Weapon"] = "Flametongue Weapon"
L["Frostbrand Weapon"] = "Frostbrand Weapon"
L["Rockbiter Weapon"] = "Rockbiter Weapon"
L["None"] = "None"

-- Earth Shield
L["Earth Shield"] = "Earth Shield"
L["Earth Shield Target"] = "Earth Shield Target"
L["Select Earth Shield Target"] = "Select Earth Shield Target"
L["No Earth Shield target assigned"] = "No Earth Shield target assigned"
L["EARTH_SHIELD_TOOLTIP"] = "Click to select Earth Shield target\\nRight-Click to clear"

-- Groups
L["Group 1"] = "Group 1"
L["Group 2"] = "Group 2"
L["Group 3"] = "Group 3"
L["Group 4"] = "Group 4"
L["Group 5"] = "Group 5"
L["Group 6"] = "Group 6"
L["Group 7"] = "Group 7"
L["Group 8"] = "Group 8"

-- Messages
L["Totem assignments have been cleared."] = "Totem assignments have been cleared."
L["Totems have been auto-assigned."] = "Totems have been auto-assigned."
L["Sync request sent."] = "Sync request sent."

-- Free assignment
L["Free Assignment"] = "Free Assignment"
L["FREE_ASSIGN_TOOLTIP"] = "Allow others to change your\ntotem assignments without being Party\nLeader / Raid Assistant."

-- Layout options
L["Horizontal Left | Down"] = "Horizontal Left | Down"
L["Horizontal Left | Up"] = "Horizontal Left | Up"
L["Horizontal Right | Down"] = "Horizontal Right | Down"
L["Horizontal Right | Up"] = "Horizontal Right | Up"
L["Vertical Left | Down"] = "Vertical Left | Down"
L["Vertical Left | Up"] = "Vertical Left | Up"
L["Vertical Right | Down"] = "Vertical Right | Down"
L["Vertical Right | Up"] = "Vertical Right | Up"

-- Scale options
L["Totem Assignments Scale"] = "Totem Assignments Scale"
L["Config Scale"] = "Config Scale"

-- Reports
L["Totem Report"] = "Totem Report"
L["LAYOUT_TOOLTIP"] = "Change the layout orientation of the assignment grid"

-- Compatibility placeholders (for code that still references old strings)
L["Main ShamanPower Settings"] = "Main ShamanPower Settings"
L["Change global settings"] = "Change global settings"
L["Change the Button Background Textures"] = "Change the Button Background Textures"
L["Change the Button Borders"] = "Change the Button Borders"
L["Change the button settings"] = "Change the button settings"
L["Change the status colors of the buff buttons"] = "Change the status colors of the totem buttons"
L["Totem Assignments Scale"] = "Totem Assignments Scale"
L["This allows you to adjust the overall size of the Totem Assignments Panel"] = "This allows you to adjust the overall size of the Totem Assignments Panel"
L["ShamanPower Buttons Scale"] = "ShamanPower Buttons Scale"
L["This allows you to adjust the overall size of the ShamanPower Buttons"] = "This allows you to adjust the overall size of the ShamanPower Buttons"
L["Change the way ShamanPower looks"] = "Change the way ShamanPower looks"

-- Options panel strings (adapted from ShamanPower)
L["Drag Handle Button"] = "Drag Handle Button"
L["[Enable/Disable] The Drag Handle Button"] = "[Enable/Disable] The Drag Handle Button"
L["[Enable/Disable] The Drag Handle Button."] = "[Enable/Disable] The Drag Handle Button."
L["[|cffffd200Enable|r/|cffffd200Disable|r] The Drag Handle Button."] = "[|cffffd200Enable|r/|cffffd200Disable|r] The Drag Handle Button."
L["[Enable/Disable] The Drag Handle"] = "[Enable/Disable] The Drag Handle"
L["Raid only options"] = "Raid only options"
L["Visibility Settings"] = "Visibility Settings"
L["ShamanPower Classic"] = "ShamanPower Classic"
L["Hide Bench (by Subgroup)"] = "Hide Bench (by Subgroup)"
L["Reset all ShamanPower frames back to center"] = "Reset all ShamanPower frames back to center"
L["Reset Frames"] = "Reset Frames"
L["Show Minimap Icon"] = "Show Minimap Icon"
L["Use in Party"] = "Use in Party"
L["Use when Solo"] = "Use when Solo"
L["While you are in a Raid dungeon, hide any players outside of the usual subgroups for that dungeon. For example, if you are in a 10-player dungeon, any players in Group 3 or higher will be hidden."] = "While you are in a Raid dungeon, hide any players outside of the usual subgroups for that dungeon."
