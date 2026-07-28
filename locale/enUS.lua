local silent = false
--[==[@debug@
silent = true
--@end-debug@]==]

local L = LibStub("AceLocale-3.0"):NewLocale("ShamanPower", "enUS", true, silent)
if not L then return end

-- General
L["SHAMANPOWER_NAME"] = "ShamanPower"
L["--- End of assignments ---"] = "--- End of assignments ---"
L["--- Shaman assignments ---"] = "--- Shaman assignments ---"

-- Minimap
L["MINIMAP_ICON_TOOLTIP"] = "|cffffffffLeft-Click|r to toggle the assignment window\n|cffffffffRight-Click|r to open options"

-- UI Elements
L["Auto-Drop"] = "Auto-Drop"
L["Auto-Assign"] = "Auto-Assign"
L["Clear"] = "Clear"
L["Refresh"] = "Refresh"
L["Options"] = "Options"
L["Report"] = "Report"

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
L["AUTO_ASSIGN_TOOLTIP"] = "Auto-Assign all totems based on\nthe number of available Shamans\nand their available Totems."
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
L["Weapon Enchant"] = "Weapon Enchant"
L["Select the Weapon Enchant you want to track"] = "Select the Weapon Enchant you want to track"
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
L["Buff Button Scale"] = "Buff Button Scale"
L["Config Scale"] = "Config Scale"

-- Reports
L["Totem Report"] = "Totem Report"
L["Totem Report Channel"] = "Totem Report Channel"
L["TOTEM_REPORT_TOOLTIP"] = "Report all Totem\nassignments to the\nRaid or Party channel."
L["LAYOUT_TOOLTIP"] = "Change the layout orientation of the assignment grid"
L["REPORT_CHANNEL_OPTION_TOOLTIP"] = "Select which channel to report totem assignments to"

-- Compatibility placeholders (for code that still references old strings)
L["Main ShamanPower Settings"] = "Main ShamanPower Settings"
L["Change global settings"] = "Change global settings"
L["Change the Button Background Textures"] = "Change the Button Background Textures"
L["Change the Button Borders"] = "Change the Button Borders"
L["Change the button settings"] = "Change the button settings"
L["Change the status colors of the buff buttons"] = "Change the status colors of the totem buttons"
L["Totems Report Channel"] = "Report Channel"
L["Buff Button | Player Button Layout"] = "Totem Button Layout"
L["Totem Assignments Scale"] = "Totem Assignments Scale"
L["This allows you to adjust the overall size of the Totem Assignments Panel"] = "This allows you to adjust the overall size of the Totem Assignments Panel"
L["ShamanPower Buttons Scale"] = "ShamanPower Buttons Scale"
L["This allows you to adjust the overall size of the ShamanPower Buttons"] = "This allows you to adjust the overall size of the ShamanPower Buttons"
L["Change the way ShamanPower looks"] = "Change the way ShamanPower looks"

-- Options panel strings (adapted from ShamanPower)
L["[|cffffd200Enable|r/|cffffd200Disable|r] The Seal Button, Enable/Disable Righteous Fury or select the Seal you want to track."] = "[|cffffd200Enable|r/|cffffd200Disable|r] The Weapon Enchant Button, or select the enchant you want to track."
L["Righteous Fury"] = "Lightning Shield"
L["[Enable/Disable] Righteous Fury"] = "[Enable/Disable] Lightning Shield"
L["Seal Tracker"] = "Weapon Enchant"
L["Select the Seal you want to track"] = "Select the Weapon Enchant you want to track"
L["Auto Buff Button"] = "Auto Drop Button"
L["[|cffffd200Enable|r/|cffffd200Disable|r] The Auto Buff Button or [|cffffd200Enable|r/|cffffd200Disable|r] Wait for Players."] = "[|cffffd200Enable|r/|cffffd200Disable|r] The Auto Drop Button or [|cffffd200Enable|r/|cffffd200Disable|r] Wait for Players."
L["[Enable/Disable] The Auto Buff Button"] = "[Enable/Disable] The Auto Drop Button"
L["[Enable/Disable] The Aura Button or select the Aura you want to track."] = "[Enable/Disable] The Earth Shield Button or select the Earth Shield target."
L["Aura Tracker"] = "Earth Shield"
L["[Enable/Disable] The Aura Button"] = "[Enable/Disable] The Earth Shield Button"
L["Wait for Players"] = "Wait for Players"
L["[Enable/Disable] Wait for Players"] = "[Enable/Disable] Wait for Players"
L["If this option is enabled then the Auto Buff Button and the Class Buff Button(s) will not auto buff a Greater Blessing if recipient(s) are not within the Paladins range (100yds). This range check excludes AFK, Dead and Offline players."] = "If enabled, the Auto Drop button will check if party members are in range before dropping totems."
L["Drag Handle Button"] = "Drag Handle Button"
L["[Enable/Disable] The Drag Handle Button"] = "[Enable/Disable] The Drag Handle Button"
L["[Enable/Disable] The Drag Handle Button."] = "[Enable/Disable] The Drag Handle Button."
L["[|cffffd200Enable|r/|cffffd200Disable|r] The Drag Handle Button."] = "[|cffffd200Enable|r/|cffffd200Disable|r] The Drag Handle Button."
L["[Enable/Disable] The Drag Handle"] = "[Enable/Disable] The Drag Handle"
L["Raid only options"] = "Raid only options"
L["Visibility Settings"] = "Visibility Settings"
L["ShamanPower Classic"] = "ShamanPower Classic"
L["Aura Button"] = "Earth Shield Button"
L["Auto-Buff Main Assistant"] = "Auto-Buff Main Assistant"
L["Auto-Buff Main Tank"] = "Auto-Buff Main Tank"
L["[|cffffd200Enable|r/|cffffd200Disable|r] The Aura Button or select the Aura you want to track."] = "[|cffffd200Enable|r/|cffffd200Disable|r] The Earth Shield Button or select the Earth Shield target."
L["Hide Bench (by Subgroup)"] = "Hide Bench (by Subgroup)"
L["If you enable this option ShamanPower will automatically over-write a Greater Blessing with a Normal Blessing on players marked with the |cffffd200Main Assistant|r role in the Blizzard Raid Panel. This is useful for spot buffing the |cffffd200Main Assistant|r role with Blessing of Sanctuary."] = "N/A for Shamans"
L["If you enable this option ShamanPower will automatically over-write a Greater Blessing with a Normal Blessing on players marked with the |cffffd200Main Assistant|r role in the Blizzard Raid Panel. This is useful to avoid blessing the |cffffd200Main Assistant|r role with a Greater Blessing of Salvation."] = "N/A for Shamans"
L["If you enable this option ShamanPower will automatically over-write a Greater Blessing with a Normal Blessing on players marked with the |cffffd200Main Tank|r role in the Blizzard Raid Panel. This is useful for spot buffing the |cffffd200Main Tank|r role with Blessing of Sanctuary."] = "N/A for Shamans"
L["If you enable this option ShamanPower will automatically over-write a Greater Blessing with a Normal Blessing on players marked with the |cffffd200Main Tank|r role in the Blizzard Raid Panel. This is useful to avoid blessing the |cffffd200Main Tank|r role with a Greater Blessing of Salvation."] = "N/A for Shamans"
L["MAIN_ROLES_DESCRIPTION"] = "Main Tank and Main Assist role options"
L["MAIN_ROLES_DESCRIPTION_WRATH"] = "Main Tank and Main Assist role options"
L["Main Tank / Main Assist Roles"] = "Main Tank / Main Assist Roles"
L["Override Druids / Paladins..."] = "Override Druids / Paladins..."
L["Override Warriors..."] = "Override Warriors..."
L["Override Warriors / Death Knights..."] = "Override Warriors / Death Knights..."
L["Reset all ShamanPower frames back to center"] = "Reset all ShamanPower frames back to center"
L["Reset Frames"] = "Reset Frames"
L["Select the Aura you want to track"] = "Select the Earth Shield target"
L["Select the Greater Blessing assignment you wish to over-write on Main Assist: Druids / Paladins."] = "N/A for Shamans"
L["Select the Greater Blessing assignment you wish to over-write on Main Assist: Warriors."] = "N/A for Shamans"
L["Select the Greater Blessing assignment you wish to over-write on Main Assist: Warriors / Death Knights."] = "N/A for Shamans"
L["Select the Greater Blessing assignment you wish to over-write on Main Tank: Druids / Paladins."] = "N/A for Shamans"
L["Select the Greater Blessing assignment you wish to over-write on Main Tank: Warriors."] = "N/A for Shamans"
L["Select the Greater Blessing assignment you wish to over-write on Main Tank: Warriors / Death Knights."] = "N/A for Shamans"
L["Select the Normal Blessing you wish to use to over-write the Main Assist: Druids / Paladins."] = "N/A for Shamans"
L["Select the Normal Blessing you wish to use to over-write the Main Assist: Warriors."] = "N/A for Shamans"
L["Select the Normal Blessing you wish to use to over-write the Main Assist: Warriors / Death Knights."] = "N/A for Shamans"
L["Select the Normal Blessing you wish to use to over-write the Main Tank: Druids / Paladins."] = "N/A for Shamans"
L["Select the Normal Blessing you wish to use to over-write the Main Tank: Warriors."] = "N/A for Shamans"
L["Select the Normal Blessing you wish to use to over-write the Main Tank: Warriors / Death Knights."] = "N/A for Shamans"
L["Show Minimap Icon"] = "Show Minimap Icon"
L["Use in Party"] = "Use in Party"
L["Use when Solo"] = "Use when Solo"
L["While you are in a Raid dungeon, hide any players outside of the usual subgroups for that dungeon. For example, if you are in a 10-player dungeon, any players in Group 3 or higher will be hidden."] = "While you are in a Raid dungeon, hide any players outside of the usual subgroups for that dungeon."
L["...with Normal..."] = "...with Normal..."

-- Right-click clears assignment option
L["Right-Click Clears Assignment"] = "Right-Click Clears Assignment"
L["RIGHTCLICK_CLEARS_ASSIGNMENT_DESC"] = "When enabled, right-clicking a totem button will clear (unassign) the totem for that slot instead of casting Totemic Call. Only works outside of combat."
L["Cannot clear assignment during combat"] = "Cannot clear assignment during combat"
