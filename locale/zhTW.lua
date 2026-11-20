-- Traditional Chinese (zhTW) strings for ShamanPower.
-- Keys and line order follow locale/enUS.lua; values are the only difference.
local L = LibStub("AceLocale-3.0"):NewLocale("ShamanPower", "zhTW")
if not L then return end


-- General
L["SHAMANPOWER_NAME"] = "ShamanPower"

-- Minimap
L["MINIMAP_ICON_TOOLTIP"] = "|cffffffff左鍵點擊|r 切換分配視窗\n|cffffffff右鍵點擊|r 開啟快捷選單\n|cffffffffShift+右鍵點擊|r 開啟設定"

-- UI Elements
L["Auto-Drop"] = "自動插放"
L["Auto-Assign"] = "自動分配"
L["Clear"] = "清除"
L["Refresh"] = "重新整理"
L["Options"] = "選項"

-- Elements
L["Earth"] = "大地"
L["Fire"] = "火焰"
L["Water"] = "水"
L["Air"] = "空氣"
L["Weapon"] = "武器"

-- Buttons
L["Drag Handle"] = "拖曳把手"
L["Auto Drop Button"] = "自動插放按鈕"
L["Element Buttons"] = "元素按鈕"
L["Shaman Buttons"] = "薩滿按鈕"

-- Tooltips
L["DRAGHANDLE_TOOLTIP"] = "|cffffffff左鍵點擊|r 鎖定/解鎖 ShamanPower\n|cffffffff左鍵按住|r 移動 ShamanPower\n|cffffffff右鍵點擊|r 開啟圖騰分配\n|cffffffffShift+右鍵點擊|r 開啟設定"
L["AUTO_DROP_TOOLTIP"] = "自動插放已分配的圖騰"

-- Settings
L["Settings"] = "設定"
L["Buttons"] = "按鈕"
L["Totems"] = "圖騰"
L["Display"] = "顯示"

L["Enable ShamanPower"] = "啟用 ShamanPower"
L["Turn ShamanPower on or off."] = "開啟或關閉 ShamanPower。"
L["[Enable/Disable] ShamanPower in Party"] = "在小隊中[啟用/停用] ShamanPower"
L["[Enable/Disable] ShamanPower while Solo"] = "單人時[啟用/停用] ShamanPower"
L["Show the ShamanPower button on the minimap."] = "在小地圖上顯示 ShamanPower 按鈕。"
L["Show details when you point at ShamanPower buttons."] = "指向 ShamanPower 按鈕時顯示詳細資訊。"

L["Show in Party"] = "在小隊中顯示"
L["Show when Solo"] = "單人時顯示"
L["Show Tooltips"] = "顯示滑鼠提示"
L["Minimap Icon"] = "小地圖圖示"

L["Background Textures"] = "背景材質"
L["Borders"] = "邊框"
L["Buff Button Layout"] = "增益按鈕佈局"

-- Status colors
L["Fully Buffed"] = "完整增益"
L["Partially Buffed"] = "部分增益"
L["Needs Buffs"] = "需要增益"
L["None Buffed"] = "無增益"
L["Special Attention"] = "特別注意"
L["Change the status colors of the totem buttons"] = "變更圖騰按鈕的狀態顏色"

-- Totem names (these will be pulled from spell data)
L["Strength of Earth"] = "大地之力"
L["Stoneskin"] = "石膚"
L["Tremor"] = "顫慄"
L["Earthbind"] = "地縛"
L["Stoneclaw"] = "石爪"
L["Earth Elemental"] = "大地元素"

L["Totem of Wrath"] = "憤怒圖騰"
L["Searing"] = "灼熱"
L["Magma"] = "熔岩"
L["Fire Nova"] = "火焰新星"
L["Flametongue"] = "火舌"
L["Frost Resistance"] = "冰霜抗性"
L["Fire Elemental"] = "火焰元素"

L["Mana Spring"] = "法力之泉"
L["Healing Stream"] = "治療之泉"
L["Mana Tide"] = "法力之潮"
L["Poison Cleansing"] = "解毒"
L["Disease Cleansing"] = "祛病"
L["Fire Resistance"] = "火焰抗性"

L["Windfury"] = "風怒"
L["Grace of Air"] = "風之優雅"
L["Wrath of Air"] = "空氣之怒"
L["Tranquil Air"] = "寧靜之風"
L["Grounding"] = "根基"
L["Nature Resistance"] = "自然抗性"
L["Windwall"] = "風牆"
L["Sentry"] = "崗哨"

-- Weapon enchants
L["Windfury Weapon"] = "風怒武器"
L["Flametongue Weapon"] = "火舌武器"
L["Frostbrand Weapon"] = "冰封武器"
L["Rockbiter Weapon"] = "石化武器"
L["None"] = "無"

-- Earth Shield
L["Earth Shield"] = "大地之盾"
L["Earth Shield Target"] = "大地之盾目標"
L["Select Earth Shield Target"] = "選擇大地之盾目標"
L["No Earth Shield target assigned"] = "未指定大地之盾目標"
L["EARTH_SHIELD_TOOLTIP"] = "點擊選擇大地之盾目標\\n右鍵點擊清除"

-- Groups
L["Group 1"] = "小隊 1"
L["Group 2"] = "小隊 2"
L["Group 3"] = "小隊 3"
L["Group 4"] = "小隊 4"
L["Group 5"] = "小隊 5"
L["Group 6"] = "小隊 6"
L["Group 7"] = "小隊 7"
L["Group 8"] = "小隊 8"

-- Messages
L["Totem assignments have been cleared."] = "圖騰分配已清除。"
L["Totems have been auto-assigned."] = "圖騰已自動分配。"
L["Sync request sent."] = "已傳送同步請求。"

-- Free assignment
L["Free Assignment"] = "自由分配"
L["FREE_ASSIGN_TOOLTIP"] = "允許他人變更你的圖騰分配，\n即使不是隊長 /\n團隊助理。"

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
L["Totem Assignments Scale"] = "圖騰分配縮放"
L["Config Scale"] = "設定介面縮放"

-- Reports
L["Totem Report"] = "圖騰報告"
L["LAYOUT_TOOLTIP"] = "變更分配格線的排列方向"

-- Compatibility placeholders (for code that still references old strings)
L["Main ShamanPower Settings"] = "ShamanPower 主設定"
L["Change global settings"] = "變更全域設定"
L["Change the Button Background Textures"] = "變更按鈕背景材質"
L["Change the Button Borders"] = "變更按鈕邊框"
L["Change the button settings"] = "變更按鈕設定"
L["Change the status colors of the buff buttons"] = "變更圖騰按鈕的狀態顏色"
L["Totem Assignments Scale"] = "圖騰分配縮放"
L["This allows you to adjust the overall size of the Totem Assignments Panel"] = "可調整「圖騰分配」面板的整體大小"
L["ShamanPower Buttons Scale"] = "ShamanPower 按鈕縮放"
L["This allows you to adjust the overall size of the ShamanPower Buttons"] = "可調整 ShamanPower 按鈕的整體大小"
L["Change the way ShamanPower looks"] = "變更 ShamanPower 的外觀"

-- Options panel strings (adapted from ShamanPower)
L["Drag Handle Button"] = "拖曳把手按鈕"
L["[Enable/Disable] The Drag Handle Button"] = "[啟用/停用] 拖曳把手按鈕"
L["[Enable/Disable] The Drag Handle Button."] = "[啟用/停用] 拖曳把手按鈕。"
L["[|cffffd200Enable|r/|cffffd200Disable|r] The Drag Handle Button."] = "[|cffffd200啟用|r/|cffffd200停用|r] 拖曳把手按鈕。"
L["[Enable/Disable] The Drag Handle"] = "[啟用/停用] 拖曳把手"
L["ShamanPower Classic"] = "ShamanPower 經典版"
L["Reset all ShamanPower frames back to center"] = "將 ShamanPower 的所有框體重設回螢幕中央"
L["Reset Frames"] = "重設框體"
L["Show Minimap Icon"] = "顯示小地圖圖示"
L["Show Totem Bar in Groups"] = "在小隊中顯示圖騰條"
L["Show Totem Bar While Solo"] = "單人時顯示圖騰條"
