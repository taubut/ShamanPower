-- Simplified Chinese (zhCN) strings for ShamanPower.
-- Keys and line order follow locale/enUS.lua; values are the only difference.
local L = LibStub("AceLocale-3.0"):NewLocale("ShamanPower", "zhCN")
if not L then return end


-- General
L["SHAMANPOWER_NAME"] = "ShamanPower"

-- Minimap
L["MINIMAP_ICON_TOOLTIP"] = "|cffffffff左键点击|r 开关分配窗口\n|cffffffff右键点击|r 打开快捷菜单\n|cffffffffShift+右键点击|r 打开设置"

-- UI Elements
L["Auto-Drop"] = "自动插放"
L["Auto-Assign"] = "自动分配"
L["Clear"] = "清除"
L["Refresh"] = "刷新"
L["Options"] = "选项"

-- Elements
L["Earth"] = "大地"
L["Fire"] = "火焰"
L["Water"] = "水"
L["Air"] = "空气"
L["Weapon"] = "武器"

-- Buttons
L["Drag Handle"] = "拖动把手"
L["Auto Drop Button"] = "自动插放按钮"
L["Element Buttons"] = "元素按钮"
L["Shaman Buttons"] = "萨满按钮"

-- Tooltips
L["DRAGHANDLE_TOOLTIP"] = "|cffffffff左键点击|r 锁定/解锁 ShamanPower\n|cffffffff左键按住|r 移动 ShamanPower\n|cffffffff右键点击|r 打开图腾分配\n|cffffffffShift+右键点击|r 打开设置"
L["AUTO_DROP_TOOLTIP"] = "自动插放已分配的图腾"

-- Settings
L["Settings"] = "设置"
L["Buttons"] = "按钮"
L["Totems"] = "图腾"
L["Display"] = "显示"

L["Enable ShamanPower"] = "启用 ShamanPower"
L["Turn ShamanPower on or off."] = "打开或关闭 ShamanPower。"
L["[Enable/Disable] ShamanPower in Party"] = "在小队中[启用/禁用] ShamanPower"
L["[Enable/Disable] ShamanPower while Solo"] = "单人时[启用/禁用] ShamanPower"
L["Show the ShamanPower button on the minimap."] = "在小地图上显示 ShamanPower 按钮。"
L["Show details when you point at ShamanPower buttons."] = "指向 ShamanPower 按钮时显示详细信息。"

L["Show in Party"] = "在小队中显示"
L["Show when Solo"] = "单人时显示"
L["Show Tooltips"] = "显示鼠标提示"
L["Minimap Icon"] = "小地图图标"

L["Background Textures"] = "背景材质"
L["Borders"] = "边框"
L["Buff Button Layout"] = "增益按钮布局"

-- Status colors
L["Fully Buffed"] = "完整增益"
L["Partially Buffed"] = "部分增益"
L["Needs Buffs"] = "需要增益"
L["None Buffed"] = "无增益"
L["Special Attention"] = "特别注意"
L["Change the status colors of the totem buttons"] = "更改图腾按钮的状态颜色"

-- Totem names (these will be pulled from spell data)
L["Strength of Earth"] = "大地之力"
L["Stoneskin"] = "石肤"
L["Tremor"] = "战栗"
L["Earthbind"] = "地缚"
L["Stoneclaw"] = "石爪"
L["Earth Elemental"] = "大地元素"

L["Totem of Wrath"] = "愤怒图腾"
L["Searing"] = "灼热"
L["Magma"] = "熔岩"
L["Fire Nova"] = "火焰新星"
L["Flametongue"] = "火舌"
L["Frost Resistance"] = "冰霜抗性"
L["Fire Elemental"] = "火焰元素"

L["Mana Spring"] = "法力之泉"
L["Healing Stream"] = "治疗之泉"
L["Mana Tide"] = "法力之潮"
L["Poison Cleansing"] = "清毒"
L["Disease Cleansing"] = "祛病"
L["Fire Resistance"] = "火焰抗性"

L["Windfury"] = "风怒"
L["Grace of Air"] = "风之优雅"
L["Wrath of Air"] = "空气之怒"
L["Tranquil Air"] = "宁静之风"
L["Grounding"] = "根基"
L["Nature Resistance"] = "自然抗性"
L["Windwall"] = "风墙"
L["Sentry"] = "哨兵"

-- Weapon enchants
L["Windfury Weapon"] = "风怒武器"
L["Flametongue Weapon"] = "火舌武器"
L["Frostbrand Weapon"] = "寒冰武器"
L["Rockbiter Weapon"] = "石化武器"
L["None"] = "无"

-- Earth Shield
L["Earth Shield"] = "大地之盾"
L["Earth Shield Target"] = "大地之盾目标"
L["Select Earth Shield Target"] = "选择大地之盾目标"
L["No Earth Shield target assigned"] = "未指定大地之盾目标"
L["EARTH_SHIELD_TOOLTIP"] = "点击选择大地之盾目标\\n右击清除"

-- Groups
L["Group 1"] = "小队 1"
L["Group 2"] = "小队 2"
L["Group 3"] = "小队 3"
L["Group 4"] = "小队 4"
L["Group 5"] = "小队 5"
L["Group 6"] = "小队 6"
L["Group 7"] = "小队 7"
L["Group 8"] = "小队 8"

-- Messages
L["Totem assignments have been cleared."] = "图腾分配已清除。"
L["Totems have been auto-assigned."] = "图腾已自动分配。"
L["Sync request sent."] = "已发送同步请求。"

-- Free assignment
L["Free Assignment"] = "自由分配"
L["FREE_ASSIGN_TOOLTIP"] = "允许他人更改你的图腾分配，\n即使不是队长 /\n团队助理。"

-- Layout options
L["Horizontal Left | Down"] = "水平 左 | 向下"
L["Horizontal Left | Up"] = "水平 左 | 向上"
L["Horizontal Right | Down"] = "水平 右 | 向下"
L["Horizontal Right | Up"] = "水平 右 | 向上"
L["Vertical Left | Down"] = "垂直 左 | 向下"
L["Vertical Left | Up"] = "垂直 左 | 向上"
L["Vertical Right | Down"] = "垂直 右 | 向下"
L["Vertical Right | Up"] = "垂直 右 | 向上"

-- Scale options
L["Totem Assignments Scale"] = "图腾分配缩放"
L["Config Scale"] = "设置界面缩放"

-- Reports
L["Totem Report"] = "图腾报告"
L["LAYOUT_TOOLTIP"] = "更改分配网格的排列方向"

-- Compatibility placeholders (for code that still references old strings)
L["Main ShamanPower Settings"] = "ShamanPower 主设置"
L["Change global settings"] = "更改全局设置"
L["Change the Button Background Textures"] = "更改按钮背景材质"
L["Change the Button Borders"] = "更改按钮边框"
L["Change the button settings"] = "更改按钮设置"
L["Change the status colors of the buff buttons"] = "更改图腾按钮的状态颜色"
L["Totem Assignments Scale"] = "图腾分配缩放"
L["This allows you to adjust the overall size of the Totem Assignments Panel"] = "可调整“图腾分配”面板的整体大小"
L["ShamanPower Buttons Scale"] = "ShamanPower 按钮缩放"
L["This allows you to adjust the overall size of the ShamanPower Buttons"] = "可调整 ShamanPower 按钮的整体大小"
L["Change the way ShamanPower looks"] = "更改 ShamanPower 的外观"

-- Options panel strings (adapted from ShamanPower)
L["Drag Handle Button"] = "拖动把手按钮"
L["[Enable/Disable] The Drag Handle Button"] = "[启用/禁用] 拖动把手按钮"
L["[Enable/Disable] The Drag Handle Button."] = "[启用/禁用] 拖动把手按钮。"
L["[|cffffd200Enable|r/|cffffd200Disable|r] The Drag Handle Button."] = "[|cffffd200启用|r/|cffffd200禁用|r] 拖动把手按钮。"
L["[Enable/Disable] The Drag Handle"] = "[启用/禁用] 拖动把手"
L["ShamanPower Classic"] = "ShamanPower 经典版"
L["Reset all ShamanPower frames back to center"] = "将 ShamanPower 的所有框体重置回屏幕中央"
L["Reset Frames"] = "重置框体"
L["Show Minimap Icon"] = "显示小地图图标"
L["Show Totem Bar in Groups"] = "在小队中显示图腾条"
L["Show Totem Bar While Solo"] = "单人时显示图腾条"
