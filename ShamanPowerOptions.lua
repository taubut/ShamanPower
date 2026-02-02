local L = LibStub("AceLocale-3.0"):GetLocale("ShamanPower")

local isShaman = select(2, UnitClass("player")) == "SHAMAN"

-------------------------------------------------------------------
-- AceConfig
-------------------------------------------------------------------
ShamanPower.options = {
	name = "  " .. L["ShamanPower Classic"],
	type = "group",
	childGroups = "tab",
	args = {
		settings = {
			order = 1,
			name = _G.SETTINGS,
			desc = L["Change global settings"],
			type = "group",
			cmdHidden = true,
			args = {
				settings_show = {
					order = 1,
					name = L["Main ShamanPower Settings"],
					type = "group",
					inline = true,
					args = {
						globally = {
							order = 1,
							name = L["Enable ShamanPower"],
							desc = L["[Enable/Disable] ShamanPower"],
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower.opt.enabled
							end,
							set = function(info, val)
								ShamanPower.opt.enabled = val
								if ShamanPower.opt.enabled then
									ShamanPower:OnEnable()
								else
									ShamanPower:OnDisable()
								end
							end
						},
						showparty = {
							order = 2,
							name = L["Use in Party"],
							desc = L["[Enable/Disable] ShamanPower in Party"],
							type = "toggle",
							width = 1.0,
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.ShowInParty
							end,
							set = function(info, val)
								ShamanPower.opt.ShowInParty = val
								ShamanPower:UpdateRoster()
							end
						},
						showminimapicon = {
							order = 3,
							name = L["Show Minimap Icon"],
							desc = L["[Show/Hide] Minimap Icon"],
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower.opt.minimap.show
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("minimap")
								ShamanPower.opt.minimap.show = val
								ShamanPowerMinimapIcon_Toggle()
							end
						},
						showsingle = {
							order = 4,
							name = L["Use when Solo"],
							desc = L["[Enable/Disable] ShamanPower while Solo"],
							type = "toggle",
							width = 1.0,
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.ShowWhenSolo
							end,
							set = function(info, val)
								ShamanPower.opt.ShowWhenSolo = val
								ShamanPower:UpdateRoster()
							end
						},
						showtooltips = {
							order = 5,
							name = L["Show Tooltips"],
							desc = L["[Show/Hide] The ShamanPower Tooltips"],
							type = "toggle",
							width = 1.0,
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.ShowTooltips
							end,
							set = function(info, val)
								ShamanPower.opt.ShowTooltips = val
								ShamanPower:UpdateRoster()
							end
						},
						synctotemtimers = {
							order = 6,
							name = "Sync to TotemTimers",
							desc = "When enabled, changing totem assignments will automatically update TotemTimers bar (requires TotemTimers addon)",
							type = "toggle",
							width = 1.0,
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.syncToTotemTimers
							end,
							set = function(info, val)
								ShamanPower.opt.syncToTotemTimers = val
							end
						},
						reportchannel = {
							order = 7,
							type = "select",
							name = L["Totems Report Channel"],
							desc = L["REPORT_CHANNEL_OPTION_TOOLTIP"],
							width = 1.0,
							values = function()
								return ShamanPower:ReportChannels()
							end,
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.ReportChannel
							end,
							set = function(info, val)
								ShamanPower.opt.ReportChannel = val
							end
						}
					}
				},
				-- settings_buffs removed - was PallyPower blessing options not applicable to Shamans
				settings_totemMode = {
					order = 2,
					name = "Totem Bar Mode",
					type = "group",
					inline = true,
					args = {
						dynamicMode = {
							order = 1,
							name = "Dynamic Mode (PVP)",
							desc = "When enabled, the totem bar automatically shows whatever totem is currently placed for each element. No need to right-click to assign totems first - just drop a totem and it becomes the active one on the bar. Great for PVP where you need quick, reactive totem management.",
							type = "toggle",
							width = "full",
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.dynamicTotemMode
							end,
							set = function(info, val)
								ShamanPower.opt.dynamicTotemMode = val
								ShamanPower:UpdateMiniTotemBar()
							end
						},
						dynamicModeDesc = {
							order = 2,
							name = "|cff888888Normal Mode: Right-click a totem in the flyout to assign it, then left-click to cast.\nDynamic Mode: Any totem you drop becomes the active button for that element.|r",
							type = "description",
							width = "full",
						},
						activeAsMainSpacer = {
							order = 3,
							type = "description",
							name = " ",
							width = "full",
						},
						activeTotemAsMain = {
							order = 4,
							name = "TotemTimers Style Display",
							desc = "When you drop a different totem than assigned, show the ACTIVE totem as the main icon with the ASSIGNED totem as a small indicator in the corner. (Default shows active totem in a separate frame above the button)",
							type = "toggle",
							width = "full",
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.activeTotemAsMain
							end,
							set = function(info, val)
								ShamanPower.opt.activeTotemAsMain = val
								ShamanPower:UpdateActiveTotemOverlays()
							end
						},
					}
				},
				settings_visibility = {
					order = 2.3,
					name = "Totem Bar Visibility",
					type = "group",
					inline = true,
					args = {
						hideOutOfCombat = {
							order = 1,
							name = "Hide Out of Combat",
							desc = "Hide the totem bar when not in combat",
							type = "toggle",
							width = 1.0,
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.hideOutOfCombat == true
							end,
							set = function(info, val)
								ShamanPower.opt.hideOutOfCombat = val
								ShamanPower:UpdateTotemBarVisibility()
							end
						},
						hideWhenNoTotems = {
							order = 2,
							name = "Hide When No Totems",
							desc = "Hide the totem bar when no totems are currently placed",
							type = "toggle",
							width = 1.0,
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.hideWhenNoTotems == true
							end,
							set = function(info, val)
								ShamanPower.opt.hideWhenNoTotems = val
								ShamanPower:UpdateTotemBarVisibility()
							end
						},
					}
				},
				settings_popout = {
					order = 2.5,
					name = "Pop-Out Trackers",
					type = "group",
					inline = true,
					args = {
						enablePopOut = {
							order = 1,
							name = "Enable Middle-Click Pop-Out",
							desc = "Allow middle-clicking buttons to pop them out as standalone, movable trackers. Disable this if you accidentally trigger pop-outs.",
							type = "toggle",
							width = "full",
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							get = function(info)
								return ShamanPower.opt.enableMiddleClickPopOut ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.enableMiddleClickPopOut = val
							end
						},
						popOutDesc = {
							order = 2,
							name = "|cff888888When enabled: Middle-click any totem button, cooldown bar item, Earth Shield, or Drop All to pop it out.\nSHIFT+Middle-click on popped-out frame for settings. ALT+drag to move.|r",
							type = "description",
							width = "full",
						}
					}
				},
				settings_frames = {
					order = 3,
					name = "Reset",
					type = "group",
					inline = true,
					args = {
						reset_center = {
							order = 1,
							name = "Reset Frames to Center",
							desc = "Reset totem bar and cooldown bar positions to center of screen",
							type = "execute",
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							func = function()
								SlashCmdList["SPCENTER"]("")
							end
						},
						reset_defaults = {
							order = 2,
							name = "Reset to Defaults",
							desc = "Reset all visual settings (scale, skin, border, layout) back to defaults",
							type = "execute",
							disabled = function(info)
								return ShamanPower.opt.enabled == false
							end,
							func = function()
								ShamanPower:Reset()
								ShamanPower:UpdateRoster()
							end
						}
					}
				}
			}
		},
		buttons = {
			order = 2,
			name = L["Buttons"],
			desc = L["Change the button settings"],
			type = "group",
			childGroups = "tree",
			cmdHidden = true,
			disabled = function(info)
				return ShamanPower.opt.enabled == false
			end,
			args = {
				aura_button = {
					order = 1,
					name = L["Aura Button"],
					type = "group",
					hidden = true,  -- Hidden - paladin auras not applicable to Shamans
					disabled = function(info)
						return ShamanPower.opt.enabled == false or not isShaman
					end,
					args = {
						aura_desc = {
							order = 0,
							type = "description",
							name = L["[|cffffd200Enable|r/|cffffd200Disable|r] The Aura Button or select the Aura you want to track."]
						},
						aura_enable = {
							order = 1,
							type = "toggle",
							name = L["Aura Button"],
							desc = L["[Enable/Disable] The Aura Button"],
							width = 1.1,
							get = function(info)
								return ShamanPower.opt.auras
							end,
							set = function(info, val)
								ShamanPower.opt.auras = val
								ShamanPower:RFAssign(ShamanPower.opt.auras)
								ShamanPower:UpdateRoster()
							end
						},
						aura = {
							order = 2,
							type = "select",
							name = L["Aura Tracker"],
							desc = L["Select the Aura you want to track"],
							get = function(info)
								return ShamanPower_AuraAssignments[ShamanPower.player]
							end,
							set = function(info, val)
								ShamanPower_AuraAssignments[ShamanPower.player] = val
							end,
							values = ShamanPower.isWrath and {
								[0] = L["None"],
								[1] = ShamanPower.Auras[1], -- Devotion Aura
								[2] = ShamanPower.Auras[2], -- Retribution Aura
								[3] = ShamanPower.Auras[3], -- Concentration Aura
								[4] = ShamanPower.Auras[4], -- Shadow Resistance Aura
								[5] = ShamanPower.Auras[5], -- Frost Resistance Aura
								[6] = ShamanPower.Auras[6], -- Fire Resistance Aura
								[7] = ShamanPower.Auras[8] -- Crusader Aura
							} or {
								[0] = L["None"],
								[1] = ShamanPower.Auras[1], -- Devotion Aura
								[2] = ShamanPower.Auras[2], -- Retribution Aura
								[3] = ShamanPower.Auras[3], -- Concentration Aura
								[4] = ShamanPower.Auras[4], -- Shadow Resistance Aura
								[5] = ShamanPower.Auras[5], -- Frost Resistance Aura
								[6] = ShamanPower.Auras[6], -- Fire Resistance Aura
								[7] = ShamanPower.Auras[7], -- Sanctity Aura
								[8] = ShamanPower.Auras[8] -- Crusader Aura
							}
						}
					}
				},
				seal_button = {
					order = 2,
					name = L["Weapon Enchant"],
					type = "group",
					hidden = true,  -- Hidden - weapon enchants are personal choice, not raid coordination
					disabled = function(info)
						return ShamanPower.opt.enabled == false or not isShaman
					end,
					args = {
						seal_desc = {
							order = 0,
							type = "description",
							name = "[|cffffd200Enable|r/|cffffd200Disable|r] The Weapon Enchant button or select the enchant you want to track."
						},
						seal_enable = {
							order = 1,
							type = "toggle",
							name = L["Weapon Enchant"],
							desc = "[Enable/Disable] The Weapon Enchant button",
							width = 1.1,
							get = function(info)
								return ShamanPower.opt.rfbuff
							end,
							set = function(info, val)
								ShamanPower.opt.rfbuff = val
								if not ShamanPower.opt.rfbuff then
									ShamanPower.opt.rf = false
								end
								ShamanPower:UpdateRoster()
							end
						},
						rfury = {
							order = 2,
							type = "toggle",
							name = L["Righteous Fury"],
							desc = L["[Enable/Disable] Righteous Fury"],
							width = 1.1,
							hidden = true,  -- Hidden - paladin Righteous Fury not applicable to Shamans
							disabled = function(info)
								return ShamanPower.opt.rfbuff == false or ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.rf
							end,
							set = function(info, val)
								ShamanPower.opt.rf = val
								ShamanPower:RFAssign(ShamanPower.opt.rf)
							end
						},
						seal = {
							order = 3,
							type = "select",
							name = L["Weapon Enchant"],
							desc = L["Select the Weapon Enchant you want to track"],
							width = .9,
							get = function(info)
								return ShamanPower.opt.seal
							end,
							set = function(info, val)
								ShamanPower.opt.seal = val
								ShamanPower:SealAssign(ShamanPower.opt.seal)
							end,
							values = {
								[0] = L["None"],
								[1] = ShamanPower.Seals[1], -- Windfury Weapon
								[2] = ShamanPower.Seals[2], -- Flametongue Weapon
								[3] = ShamanPower.Seals[3], -- Frostbrand Weapon
								[4] = ShamanPower.Seals[4], -- Rockbiter Weapon
							}
						}
					}
				},
				auto_button = {
					order = 3,
					name = "Mini Totem Bar",
					type = "group",
					disabled = function(info)
						return ShamanPower.opt.enabled == false or not isShaman
					end,
					args = {
						auto_desc = {
							order = 0,
							type = "description",
							name = "Configure the Mini Totem Bar - a compact bar of clickable totem buttons.",
						},
						auto_enable = {
							order = 1,
							type = "toggle",
							name = "Enable Mini Totem Bar",
							desc = "[Enable/Disable] The Mini Totem Bar",
							width = "full",
							get = function(info)
								return ShamanPower.opt.autobuff.autobutton
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("autobuff")
								ShamanPower.opt.autobuff.autobutton = val
								ShamanPower:UpdateRoster()
							end
						},
						show_dropall = {
							order = 2,
							type = "toggle",
							name = "Show Drop All Button",
							desc = "[Enable/Disable] The Drop All Totems button on the Mini Totem Bar",
							width = "full",
							get = function(info)
								return ShamanPower.opt.showDropAllButton
							end,
							set = function(info, val)
								ShamanPower.opt.showDropAllButton = val
								if not InCombatLockdown() then
									ShamanPower:UpdateMiniTotemBar()
								end
							end
						},
						show_cooldown_bar = {
							order = 2.05,
							type = "toggle",
							name = "Show Cooldown Bar",
							desc = "[Enable/Disable] Show the cooldown tracker bar (Shields, Ankh, NS, etc.)",
							width = "full",
							get = function(info)
								return ShamanPower.opt.showCooldownBar
							end,
							set = function(info, val)
								ShamanPower.opt.showCooldownBar = val
								ShamanPower:UpdateCooldownBar()
							end
						},
						show_totem_flyouts = {
							order = 2.25,
							type = "toggle",
							name = "Show Totem Flyouts",
							desc = "[Enable/Disable] Show flyout menus on mouseover for quick totem selection (TotemTimers style)",
							width = "full",
							get = function(info)
								return ShamanPower.opt.showTotemFlyouts
							end,
							set = function(info, val)
								ShamanPower.opt.showTotemFlyouts = val
								ShamanPower:UpdateTotemFlyoutEnabled()
							end
						},
						show_es_flyout = {
							order = 2.26,
							type = "toggle",
							name = "Show Earth Shield Flyout",
							desc = "[Enable/Disable] Show flyout menu on Earth Shield button for quick target selection",
							width = "full",
							hidden = function(info)
								return not ShamanPower:HasEarthShield()
							end,
							get = function(info)
								return ShamanPower.opt.enableESFlyout ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.enableESFlyout = val
								if not InCombatLockdown() then
									ShamanPower:UpdateEarthShieldButton()
								end
							end
						},
						drop_order_header = {
							order = 2.5,
							type = "header",
							name = "Drop Order",
						},
						drop_order_1 = {
							order = 2.6,
							type = "select",
							name = "1st Position",
							desc = "First totem to drop",
							width = 1.2,
							values = {
								[1] = "Earth",
								[2] = "Fire",
								[3] = "Water",
								[4] = "Air",
							},
							get = function(info)
								return ShamanPower.opt.dropOrder and ShamanPower.opt.dropOrder[1] or 1
							end,
							set = function(info, val)
								if not ShamanPower.opt.dropOrder then ShamanPower.opt.dropOrder = {1, 2, 3, 4} end
								-- Swap if duplicate
								for i = 2, 4 do
									if ShamanPower.opt.dropOrder[i] == val then
										ShamanPower.opt.dropOrder[i] = ShamanPower.opt.dropOrder[1]
										break
									end
								end
								ShamanPower.opt.dropOrder[1] = val
								ShamanPower:UpdateDropAllButton()
							end
						},
						drop_order_2 = {
							order = 2.7,
							type = "select",
							name = "2nd Position",
							desc = "Second totem to drop",
							width = 1.2,
							values = {
								[1] = "Earth",
								[2] = "Fire",
								[3] = "Water",
								[4] = "Air",
							},
							get = function(info)
								return ShamanPower.opt.dropOrder and ShamanPower.opt.dropOrder[2] or 2
							end,
							set = function(info, val)
								if not ShamanPower.opt.dropOrder then ShamanPower.opt.dropOrder = {1, 2, 3, 4} end
								-- Swap if duplicate
								for i = 1, 4 do
									if i ~= 2 and ShamanPower.opt.dropOrder[i] == val then
										ShamanPower.opt.dropOrder[i] = ShamanPower.opt.dropOrder[2]
										break
									end
								end
								ShamanPower.opt.dropOrder[2] = val
								ShamanPower:UpdateDropAllButton()
							end
						},
						drop_order_3 = {
							order = 2.8,
							type = "select",
							name = "3rd Position",
							desc = "Third totem to drop",
							width = 1.2,
							values = {
								[1] = "Earth",
								[2] = "Fire",
								[3] = "Water",
								[4] = "Air",
							},
							get = function(info)
								return ShamanPower.opt.dropOrder and ShamanPower.opt.dropOrder[3] or 3
							end,
							set = function(info, val)
								if not ShamanPower.opt.dropOrder then ShamanPower.opt.dropOrder = {1, 2, 3, 4} end
								-- Swap if duplicate
								for i = 1, 4 do
									if i ~= 3 and ShamanPower.opt.dropOrder[i] == val then
										ShamanPower.opt.dropOrder[i] = ShamanPower.opt.dropOrder[3]
										break
									end
								end
								ShamanPower.opt.dropOrder[3] = val
								ShamanPower:UpdateDropAllButton()
							end
						},
						drop_order_4 = {
							order = 2.9,
							type = "select",
							name = "4th Position",
							desc = "Fourth totem to drop",
							width = 1.2,
							values = {
								[1] = "Earth",
								[2] = "Fire",
								[3] = "Water",
								[4] = "Air",
							},
							get = function(info)
								return ShamanPower.opt.dropOrder and ShamanPower.opt.dropOrder[4] or 4
							end,
							set = function(info, val)
								if not ShamanPower.opt.dropOrder then ShamanPower.opt.dropOrder = {1, 2, 3, 4} end
								-- Swap if duplicate
								for i = 1, 3 do
									if ShamanPower.opt.dropOrder[i] == val then
										ShamanPower.opt.dropOrder[i] = ShamanPower.opt.dropOrder[4]
										break
									end
								end
								ShamanPower.opt.dropOrder[4] = val
								ShamanPower:UpdateDropAllButton()
							end
						},
						exclude_from_drop_all_header = {
							order = 2.901,
							type = "header",
							name = "Exclude from Drop All",
						},
						exclude_earth = {
							order = 2.902,
							type = "toggle",
							name = "Exclude Earth",
							desc = "Exclude Earth totem from the Drop All button",
							width = "full",
							get = function(info)
								return ShamanPower.opt.excludeEarthFromDropAll
							end,
							set = function(info, val)
								ShamanPower.opt.excludeEarthFromDropAll = val
								ShamanPower:UpdateDropAllButton()
								ShamanPower:UpdateSPMacros()
							end
						},
						exclude_fire = {
							order = 2.903,
							type = "toggle",
							name = "Exclude Fire",
							desc = "Exclude Fire totem from the Drop All button",
							width = "full",
							get = function(info)
								return ShamanPower.opt.excludeFireFromDropAll
							end,
							set = function(info, val)
								ShamanPower.opt.excludeFireFromDropAll = val
								ShamanPower:UpdateDropAllButton()
								ShamanPower:UpdateSPMacros()
							end
						},
						exclude_water = {
							order = 2.904,
							type = "toggle",
							name = "Exclude Water",
							desc = "Exclude Water totem from the Drop All button",
							width = "full",
							get = function(info)
								return ShamanPower.opt.excludeWaterFromDropAll
							end,
							set = function(info, val)
								ShamanPower.opt.excludeWaterFromDropAll = val
								ShamanPower:UpdateDropAllButton()
								ShamanPower:UpdateSPMacros()
							end
						},
						exclude_air = {
							order = 2.905,
							type = "toggle",
							name = "Exclude Air",
							desc = "Exclude Air totem from the Drop All button",
							width = "full",
							get = function(info)
								return ShamanPower.opt.excludeAirFromDropAll
							end,
							set = function(info, val)
								ShamanPower.opt.excludeAirFromDropAll = val
								ShamanPower:UpdateDropAllButton()
								ShamanPower:UpdateSPMacros()
							end
						},
						auto_wait = {
							order = 3,
							type = "toggle",
							name = L["Wait for Players"],
							desc = L["If this option is enabled then the Auto Buff Button and the Class Buff Button(s) will not auto buff a Greater Blessing if recipient(s) are not within the Paladins range (100yds). This range check excludes AFK, Dead and Offline players."],
							hidden = true,  -- Hidden - paladin range check not applicable to Shamans (totems are ground-based)
							get = function(info)
								return ShamanPower.opt.autobuff.waitforpeople
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("autobuff")
								ShamanPower.opt.autobuff.waitforpeople = val
								ShamanPower:UpdateRoster()
							end
						}
					}
				},
				macros_section = {
					order = 3.5,
					name = "Macros",
					type = "group",
					disabled = function(info)
						return ShamanPower.opt.enabled == false or not isShaman
					end,
					args = {
						macros_desc = {
							order = 0,
							type = "description",
							name = "Create macros for your assigned totems. Drag them to your action bar - they auto-update when you change assignments."
						},
						create_macros = {
							order = 1,
							type = "execute",
							name = "Create/Update Macros",
							desc = "Creates or updates the following macros:\nSP_Earth, SP_Fire, SP_Water, SP_Air - Cast assigned totem\nSP_DropAll - Cast all totems in sequence\nSP_Recall - Totemic Call",
							width = 1.3,
							func = function()
								if InCombatLockdown() then
									print("ShamanPower: Cannot update macros in combat")
									return
								end
								ShamanPower:UpdateSPMacros()
								print("ShamanPower: Macros created! Check your macro panel (Esc -> Macros)")
							end
						}
					}
				},
				cp_button = {
					order = 4,
					name = "Element Buttons",
					type = "group",
					hidden = true,  -- Hidden - not functional in current shaman implementation
					disabled = function(info)
						return ShamanPower.opt.enabled == false or not isShaman
					end,
					args = {
						cp_desc = {
							order = 0,
							type = "description",
							name = "[|cffffd200Enable|r/|cffffd200Disable|r] The Element buttons (Earth, Fire, Water, Air)."
						},
						class_enable = {
							order = 1,
							type = "toggle",
							name = "Element Buttons",
							desc = "[Enable/Disable] Element Buttons",
							width = 1.1,
							get = function(info)
								return ShamanPower.opt.display.showClassButtons
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("display")
								ShamanPower.opt.display.showClassButtons = val
								ShamanPower:UpdateRoster()
							end
						},
						player_enable = {
							order = 2,
							type = "toggle",
							name = "Shaman Buttons",
							desc = "Show buttons for individual shamans in the raid.",
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.display.showPlayerButtons
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("display")
								ShamanPower.opt.display.showPlayerButtons = val
								ShamanPower:UpdateRoster()
							end
						},
						buff_Duration = {
							order = 3,
							type = "toggle",
							name = "Totem Duration",
							desc = "If disabled, element buttons will ignore totem duration, allowing totems to be recast at will.",
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.display.buffDuration
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("display")
								ShamanPower.opt.display.buffDuration = val
								ShamanPower:UpdateRoster()
							end
						}
					}
				}
			}
		},
		fluffy = {
			order = 3,
			name = "Look & Feel",
			desc = "UI customization options (requested by FluffyKable)",
			type = "group",
			childGroups = "tree",
			cmdHidden = true,
			disabled = function(info)
				return ShamanPower.opt.enabled == false
			end,
			args = {
				fluffy_header = {
					order = 0,
					type = "description",
					name = "    |cffffd200Fluffy Settings|r\n    UI customization options - dedicated to |cff0070deFluffyKable|r from the Shaman Discord.",
					fontSize = "medium",
				},
				layout_section = {
					order = 1,
					name = "Layout",
					type = "group",
					args = {
						layout_desc = {
							order = 0,
							type = "description",
							name = "Control the orientation of your bars and how flyout menus appear.",
						},
						layout = {
							order = 1,
							type = "select",
							width = 1.4,
							name = "Totem Bar Layout",
							desc = "Change the layout orientation of the totem bar",
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.layout
							end,
							set = function(info, val)
								-- Don't change layout in combat
								if InCombatLockdown() then return end

								-- Initialize cdbarLayout if not set, so changing totem bar doesn't affect CD bar
								if ShamanPower.opt.cdbarLayout == nil then
									ShamanPower.opt.cdbarLayout = ShamanPower.opt.layout
								end

								-- Save current autoButton screen position before layout change
								local oldLayout = ShamanPower.opt.layout
								local autoBtn = ShamanPower.autoButton
								local header = ShamanPower.Header
								local oldCenterX, oldCenterY
								if autoBtn and autoBtn:IsShown() then
									oldCenterX, oldCenterY = autoBtn:GetCenter()
								end

								-- Change the layout
								ShamanPower.opt.layout = val
								ShamanPower:UpdateLayout()
								ShamanPower:UpdateRoster()

								-- Restore position so autoButton stays in same screen location
								if oldCenterX and oldCenterY and autoBtn and header then
									local newCenterX, newCenterY = autoBtn:GetCenter()
									if newCenterX and newCenterY then
										-- Calculate the offset needed
										local deltaX = oldCenterX - newCenterX
										local deltaY = oldCenterY - newCenterY

										-- Move the main frame to compensate
										local frame = _G["ShamanPowerFrame"]
										if frame and not InCombatLockdown() then
											local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint()
											if point and xOfs and yOfs then
												frame:ClearAllPoints()
												frame:SetPoint(point, relativeTo, relativePoint, xOfs + deltaX, yOfs + deltaY)
											end
										end
									end
								end

								-- Update cooldown bar position for new layout
								ShamanPower:UpdateCooldownBar()
							end,
							values = {
								["Horizontal"] = "Horizontal",
								["Vertical"] = "Vertical (Right)",
								["VerticalLeft"] = "Vertical (Left)",
							}
						},
						totem_flyout_direction = {
							order = 1.2,
							type = "select",
							name = "Totem Flyout Direction",
							desc = "Direction totem flyouts appear when totem bar is horizontal",
							width = 1.0,
							hidden = function(info)
								return not ShamanPower.opt.showTotemFlyouts or ShamanPower.opt.layout ~= "Horizontal"
							end,
							values = {
								["auto"] = "Auto",
								["above"] = "Above",
								["below"] = "Below",
							},
							get = function(info)
								return ShamanPower.opt.totemFlyoutDirection or "auto"
							end,
							set = function(info, val)
								ShamanPower.opt.totemFlyoutDirection = val
								-- Update all totem flyouts (UpdateFlyoutVisibility handles positioning)
								for element = 1, 4 do
									if ShamanPower.totemFlyouts[element] then
										ShamanPower:UpdateFlyoutVisibility(element)
									end
								end
								-- Update ES flyout if it exists
								if ShamanPower.CreateEarthShieldFlyout then
									ShamanPower:CreateEarthShieldFlyout()
								end
							end,
						},
						cdbarLayout = {
							order = 1.5,
							type = "select",
							width = 1.4,
							name = "Cooldown Bar Layout",
							desc = "Change the layout orientation of the cooldown bar independently from the totem bar",
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showCooldownBar
							end,
							get = function(info)
								return ShamanPower.opt.cdbarLayout or ShamanPower.opt.layout
							end,
							set = function(info, val)
								-- Don't change layout in combat
								if InCombatLockdown() then return end
								ShamanPower.opt.cdbarLayout = val
								ShamanPower:UpdateCooldownBarLayout()
								ShamanPower:UpdateCooldownBar()
								-- Re-layout the shield and weapon imbue flyouts for new direction
								if ShamanPower.LayoutShieldFlyout then
									ShamanPower:LayoutShieldFlyout()
								end
								if ShamanPower.LayoutWeaponImbueFlyout then
									ShamanPower:LayoutWeaponImbueFlyout()
								end
							end,
							values = {
								["Horizontal"] = "Horizontal",
								["Vertical"] = "Vertical (Right)",
								["VerticalLeft"] = "Vertical (Left)",
							}
						},
						cdbar_flyout_direction = {
							order = 1.7,
							type = "select",
							name = "Cooldown Flyout Direction",
							desc = "Direction cooldown bar flyouts appear when cooldown bar is horizontal",
							width = 1.0,
							hidden = function(info)
								local cdLayout = ShamanPower.opt.cdbarLayout or ShamanPower.opt.layout
								return cdLayout ~= "Horizontal"
							end,
							values = {
								["auto"] = "Auto",
								["above"] = "Above",
								["below"] = "Below",
							},
							get = function(info)
								return ShamanPower.opt.cdbarFlyoutDirection or "auto"
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarFlyoutDirection = val
								-- Re-layout the shield and weapon imbue flyouts for new direction
								if ShamanPower.LayoutShieldFlyout then
									ShamanPower:LayoutShieldFlyout()
								end
								if ShamanPower.LayoutWeaponImbueFlyout then
									ShamanPower:LayoutWeaponImbueFlyout()
								end
							end,
						},
						swap_flyout_clicks = {
							order = 2,
							type = "toggle",
							name = "Swap Flyout Click Buttons",
							desc = "Swap mouse buttons on totem flyout menus: Left-click assigns totem, Right-click casts (default is Left=cast, Right=assign)",
							width = "full",
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.swapFlyoutClickButtons
							end,
							set = function(info, val)
								ShamanPower.opt.swapFlyoutClickButtons = val
								-- Just update click attributes on existing buttons
								ShamanPower:UpdateFlyoutClickBehavior()
							end
						},
						flyout_requires_click = {
							order = 3,
							type = "toggle",
							name = "Flyout Requires Right-Click",
							desc = "Flyouts only appear when you right-click the totem button instead of on mouseover. Right-click the flyout totem to assign it. Note: Disables right-click to destroy totems.",
							width = "full",
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showTotemFlyouts
							end,
							get = function(info)
								return ShamanPower.opt.flyoutRequiresClick
							end,
							set = function(info, val)
								ShamanPower.opt.flyoutRequiresClick = val
								ShamanPower:UpdateTotemFlyoutEnabled()
							end
						},
					}
				},
				scale_section = {
					order = 2,
					name = "Scale",
					type = "group",
					args = {
						scale_desc = {
							order = 0,
							type = "description",
							name = "Adjust the overall size of your bars and buttons.",
						},
						buffscale = {
							order = 1,
							name = "Totem Bar Scale",
							desc = "Adjust the size of the totem bar and main ShamanPower buttons",
							type = "range",
							width = 1.5,
							min = 0.4,
							max = 3.0,
							step = 0.05,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.buffscale
							end,
							set = function(info, val)
								ShamanPower.opt.buffscale = val
								ShamanPower:UpdateLayout()
								ShamanPower:UpdateCooldownBarScale()
								ShamanPower:UpdateRoster()
							end
						},
						cooldownBarScale = {
							order = 2,
							name = "Cooldown Bar Scale",
							desc = "Adjust the size of the cooldown tracker bar independently",
							type = "range",
							width = 1.5,
							min = 0.4,
							max = 3.0,
							step = 0.05,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showCooldownBar
							end,
							get = function(info)
								return ShamanPower.opt.cooldownBarScale or 0.9
							end,
							set = function(info, val)
								ShamanPower.opt.cooldownBarScale = val
								ShamanPower:UpdateCooldownBarScale()
							end
						},
						assignmentsscale = {
							order = 3,
							name = L["Totem Assignments Scale"],
							desc = L["This allows you to adjust the overall size of the Totem Assignments Panel"],
							type = "range",
							width = 1.5,
							min = 0.4,
							max = 3.0,
							step = 0.05,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.configscale
							end,
							set = function(info, val)
								ShamanPower.opt.configscale = val
								ShamanPower:UpdateLayout()
								ShamanPower:UpdateRoster()
							end
						},
					}
				},
				opacity_section = {
					order = 3,
					name = "Opacity",
					type = "group",
					args = {
						opacity_desc = {
							order = 0,
							type = "description",
							name = "Control transparency of your bars. Use 'Full Opacity When Active' to highlight active totems/cooldowns.",
						},
						totemBarOpacity = {
							order = 1,
							name = "Totem Bar",
							desc = "Adjust the opacity/transparency of the totem bar",
							type = "range",
							width = 1.2,
							min = 0.1,
							max = 1.0,
							step = 0.05,
							isPercent = true,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.totemBarOpacity or 1.0
							end,
							set = function(info, val)
								ShamanPower.opt.totemBarOpacity = val
								ShamanPower:UpdateTotemBarOpacity()
							end
						},
						totemBarFullOpacityWhenActive = {
							order = 1.5,
							name = "Full Opacity When Totem Placed",
							desc = "Show totem buttons at full opacity when that element's totem is active (overrides the opacity setting above)",
							type = "toggle",
							width = "full",
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.totemBarFullOpacityWhenActive
							end,
							set = function(info, val)
								ShamanPower.opt.totemBarFullOpacityWhenActive = val
								ShamanPower:UpdateTotemBarOpacity()
							end
						},
						cooldownBarOpacity = {
							order = 2,
							name = "Cooldown Bar",
							desc = "Adjust the opacity/transparency of the cooldown bar",
							type = "range",
							width = 1.2,
							min = 0.1,
							max = 1.0,
							step = 0.05,
							isPercent = true,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showCooldownBar
							end,
							get = function(info)
								return ShamanPower.opt.cooldownBarOpacity or 1.0
							end,
							set = function(info, val)
								ShamanPower.opt.cooldownBarOpacity = val
								ShamanPower:UpdateCooldownBarOpacity()
							end
						},
						cooldownBarFullOpacityWhenActive = {
							order = 2.5,
							name = "Full Opacity When Active",
							desc = "Show cooldown buttons at full opacity when the buff is active or the ability is on cooldown",
							type = "toggle",
							width = "full",
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showCooldownBar
							end,
							get = function(info)
								return ShamanPower.opt.cooldownBarFullOpacityWhenActive
							end,
							set = function(info, val)
								ShamanPower.opt.cooldownBarFullOpacityWhenActive = val
								ShamanPower:UpdateCooldownBarOpacity()
							end
						},
						totemFlyoutOpacity = {
							order = 3,
							name = "Totem Flyouts",
							desc = "Adjust the opacity/transparency of the totem bar flyout menus",
							type = "range",
							width = 1.2,
							min = 0.1,
							max = 1.0,
							step = 0.05,
							isPercent = true,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showTotemFlyouts
							end,
							get = function(info)
								return ShamanPower.opt.totemFlyoutOpacity or 1.0
							end,
							set = function(info, val)
								ShamanPower.opt.totemFlyoutOpacity = val
								ShamanPower:UpdateTotemFlyoutOpacity()
							end
						},
						cooldownFlyoutOpacity = {
							order = 4,
							name = "CD Flyouts",
							desc = "Adjust the opacity/transparency of the cooldown bar flyout menus",
							type = "range",
							width = 1.2,
							min = 0.1,
							max = 1.0,
							step = 0.05,
							isPercent = true,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showCooldownBar
							end,
							get = function(info)
								return ShamanPower.opt.cooldownFlyoutOpacity or 1.0
							end,
							set = function(info, val)
								ShamanPower.opt.cooldownFlyoutOpacity = val
								ShamanPower:UpdateCooldownFlyoutOpacity()
							end
						},
					}
				},
				padding_section = {
					order = 4,
					name = "Button Padding",
					type = "group",
					args = {
						padding_desc = {
							order = 0,
							type = "description",
							name = "Adjust the spacing between buttons on your bars.",
						},
						totemBarPadding = {
							order = 1,
							name = "Totem Bar Padding",
							desc = "Adjust the spacing between totem bar buttons (in pixels)",
							type = "range",
							width = 1.5,
							min = 0,
							max = 20,
							step = 1,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.totemBarPadding or 2
							end,
							set = function(info, val)
								ShamanPower.opt.totemBarPadding = val
								ShamanPower:UpdateRoster()
							end
						},
						cooldownBarPadding = {
							order = 2,
							name = "Cooldown Bar Padding",
							desc = "Adjust the spacing between cooldown bar buttons (in pixels)",
							type = "range",
							width = 1.5,
							min = 0,
							max = 20,
							step = 1,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman or not ShamanPower.opt.showCooldownBar
							end,
							get = function(info)
								return ShamanPower.opt.cooldownBarPadding or 2
							end,
							set = function(info, val)
								ShamanPower.opt.cooldownBarPadding = val
								ShamanPower:UpdateCooldownBar()
							end
						},
					}
				},
				visibility_section = {
					order = 5,
					name = "Frame Visibility",
					type = "group",
					args = {
						visibility_desc = {
							order = 0,
							type = "description",
							name = "Show or hide various UI elements like frames, text, keybinds, and drag handles.",
						},
						hide_totem_bar_frame = {
							order = 1,
							type = "toggle",
							name = "Hide Totem Bar Frame",
							desc = "Hide the background and border around the totem bar (show icons only)",
							width = 1.5,
							get = function(info)
								return ShamanPower.opt.hideTotemBarFrame
							end,
							set = function(info, val)
								ShamanPower.opt.hideTotemBarFrame = val
								ShamanPower:UpdateTotemBarFrame()
							end
						},
						hide_cooldown_bar_frame = {
							order = 2,
							type = "toggle",
							name = "Hide Cooldown Bar Frame",
							desc = "Hide the background and border around the cooldown bar (show icons only)",
							width = 1.5,
							disabled = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
							get = function(info)
								return ShamanPower.opt.hideCooldownBarFrame
							end,
							set = function(info, val)
								ShamanPower.opt.hideCooldownBarFrame = val
								ShamanPower:UpdateCooldownBarFrame()
							end
						},
						hide_earth_shield_text = {
							order = 3,
							type = "toggle",
							name = "Hide Earth Shield Text",
							desc = "Hide the Earth Shield target name text below the button on the totem bar",
							width = 1.5,
							get = function(info)
								return ShamanPower.opt.hideEarthShieldText
							end,
							set = function(info, val)
								ShamanPower.opt.hideEarthShieldText = val
								ShamanPower:UpdateEarthShieldButton()
							end
						},
						show_button_keybinds = {
							order = 4,
							type = "toggle",
							name = "Show Keybinds on Buttons",
							desc = "Display keybind text on buttons (top-right corner)",
							width = 1.5,
							get = function(info)
								return ShamanPower.opt.showButtonKeybinds
							end,
							set = function(info, val)
								ShamanPower.opt.showButtonKeybinds = val
								ShamanPower:UpdateButtonKeybindText()
							end
						},
						unlock_cooldown_bar = {
							order = 5,
							type = "toggle",
							name = "Unlock Cooldown Bar",
							desc = "Allow the cooldown bar to be moved independently from the totem bar (ALT+drag or use drag handle)",
							width = 1.5,
							disabled = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
							get = function(info)
								return not ShamanPower.opt.cooldownBarLocked
							end,
							set = function(info, val)
								ShamanPower.opt.cooldownBarLocked = not val
								ShamanPower:UpdateCooldownBarPosition()
							end
						},
						drag_enable = {
							order = 6,
							type = "toggle",
							name = L["Drag Handle"],
							desc = L["[Enable/Disable] The Drag Handle"],
							width = 1.5,
							get = function(info)
								return ShamanPower.opt.display.enableDragHandle
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("display")
								ShamanPower.opt.display.enableDragHandle = val
								ShamanPower:UpdateRoster()
								ShamanPower:UpdateCooldownBarPosition()
							end
						},
					}
				},
				texture_section = {
					order = 6,
					name = "Textures",
					type = "group",
					args = {
						texture_desc = {
							order = 0,
							type = "description",
							name = "Customize the background and border textures for your bars.",
						},
						skin = {
							order = 1,
							name = L["Background Textures"],
							desc = L["Change the Button Background Textures"],
							type = "select",
							width = 1.5,
							dialogControl = "LSM30_Background",
							values = AceGUIWidgetLSMlists.background,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.skin
							end,
							set = function(info, val)
								ShamanPower.opt.skin = val
								ShamanPower:ApplySkin()
								ShamanPower:UpdateRoster()
							end
						},
						edges = {
							order = 2,
							name = L["Borders"],
							desc = L["Change the Button Borders"],
							type = "select",
							width = 1.5,
							dialogControl = "LSM30_Border",
							values = AceGUIWidgetLSMlists.border,
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.border
							end,
							set = function(info, val)
								ShamanPower.opt.border = val
								ShamanPower:ApplySkin()
								ShamanPower:UpdateRoster()
							end
						},
					}
				},
				cooldown_display_section = {
					order = 11,
					name = "Cooldown Display",
					type = "group",
					hidden = function(info)
						return not ShamanPower.opt.showCooldownBar
					end,
					args = {
						cdbar_display_desc = {
							order = 0,
							type = "description",
							name = "Customize how cooldowns and durations are displayed on the cooldown bar.",
						},
						cdbar_show_progress_bars = {
							order = 1,
							type = "toggle",
							name = "Show Progress Bars",
							desc = "Show colored progress bars on the edges of cooldown buttons",
							width = "full",
							get = function(info)
								return ShamanPower.opt.cdbarShowProgressBars ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowProgressBars = val
							end
						},
						cdbar_show_color_sweep = {
							order = 2,
							type = "toggle",
							name = "Show Color Sweep Overlay",
							desc = "Show greyed-out sweep overlay as time depletes",
							width = "full",
							get = function(info)
								return ShamanPower.opt.cdbarShowColorSweep ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowColorSweep = val
							end
						},
						cdbar_show_cd_text = {
							order = 3,
							type = "toggle",
							name = "Show Cooldown Text",
							desc = "Show cooldown time remaining as text",
							width = "full",
							get = function(info)
								return ShamanPower.opt.cdbarShowCDText ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowCDText = val
							end
						},
						shield_charge_colors = {
							order = 4,
							type = "toggle",
							name = "Color Shield Charges by Count",
							desc = "Color shield charge count based on remaining charges (Green=full, Yellow=half, Red=low). Disable for plain white text.",
							width = "full",
							get = function(info)
								return ShamanPower.opt.shieldChargeColors ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.shieldChargeColors = val
							end
						},
						show_ankh_count = {
							order = 4.5,
							type = "toggle",
							name = "Show Ankh Count on Reincarnation",
							desc = "Display the number of Ankhs in your inventory on the Reincarnation icon",
							width = "full",
							get = function(info)
								return ShamanPower.opt.showAnkhCount
							end,
							set = function(info, val)
								ShamanPower.opt.showAnkhCount = val
							end
						},
						spacer1 = {
							order = 5,
							type = "description",
							name = "\n",
							width = "full",
						},
						cdbar_progress_position = {
							order = 6,
							type = "select",
							name = "Progress Bar Position",
							desc = "Position of the progress bar relative to icons",
							width = "full",
							values = {
								["left"] = "Left",
								["right"] = "Right",
								["top"] = "Top (Horizontal)",
								["top_vert"] = "Top (Vertical)",
								["bottom"] = "Bottom (Horizontal)",
								["bottom_vert"] = "Bottom (Vertical)",
							},
							get = function(info)
								return ShamanPower.opt.cdbarProgressPosition or "left"
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarProgressPosition = val
								ShamanPower:RecreateCooldownBar()
							end
						},
						cdbar_progress_height = {
							order = 7,
							type = "range",
							name = "Progress Bar Size",
							desc = "Size of the duration bar (height for horizontal bars, width for vertical bars)",
							width = "full",
							min = 3,
							max = 16,
							step = 1,
							get = function(info)
								return ShamanPower.opt.cdbarProgressBarHeight or 3
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarProgressBarHeight = val
								ShamanPower:UpdateCooldownBarProgressBars()
								ShamanPower:UpdateCooldownBarLayout()
							end
						},
						cdbar_duration_text = {
							order = 8,
							type = "select",
							name = "Duration Text Location",
							desc = "Where to show the remaining duration time",
							width = "full",
							values = {
								["none"] = "None",
								["inside"] = "Inside Bar",
								["outside"] = "Outside Bar",
								["icon"] = "On Icon",
							},
							get = function(info)
								return ShamanPower.opt.cdbarDurationTextLocation or "none"
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarDurationTextLocation = val
							end
						},
					}
				},
				color_section = {
					order = 19,
					name = "Status Colors",
					type = "group",
					disabled = function(info)
						return ShamanPower.opt.enabled == false or not isShaman
					end,
					args = {
						color_desc = {
							order = 0,
							type = "description",
							name = "Customize the colors used to indicate buff status in the assignment panel.",
						},
						color_good = {
							order = 1,
							name = L["Fully Buffed"],
							type = "color",
							get = function()
								return ShamanPower.opt.cBuffGood.r, ShamanPower.opt.cBuffGood.g, ShamanPower.opt.cBuffGood.b, ShamanPower.opt.cBuffGood.t
							end,
							set = function(info, r, g, b, t)
								ShamanPower:EnsureProfileTable("cBuffGood")
								ShamanPower.opt.cBuffGood.r = r
								ShamanPower.opt.cBuffGood.g = g
								ShamanPower.opt.cBuffGood.b = b
								ShamanPower.opt.cBuffGood.t = t
							end,
							hasAlpha = true
						},
						color_partial = {
							order = 2,
							name = L["Partially Buffed"],
							type = "color",
							width = 1.1,
							get = function()
								return ShamanPower.opt.cBuffNeedSome.r, ShamanPower.opt.cBuffNeedSome.g, ShamanPower.opt.cBuffNeedSome.b, ShamanPower.opt.cBuffNeedSome.t
							end,
							set = function(info, r, g, b, t)
								ShamanPower:EnsureProfileTable("cBuffNeedSome")
								ShamanPower.opt.cBuffNeedSome.r = r
								ShamanPower.opt.cBuffNeedSome.g = g
								ShamanPower.opt.cBuffNeedSome.b = b
								ShamanPower.opt.cBuffNeedSome.t = t
							end,
							hasAlpha = true
						},
						color_missing = {
							order = 3,
							name = L["None Buffed"],
							type = "color",
							get = function()
								return ShamanPower.opt.cBuffNeedAll.r, ShamanPower.opt.cBuffNeedAll.g, ShamanPower.opt.cBuffNeedAll.b, ShamanPower.opt.cBuffNeedAll.t
							end,
							set = function(info, r, g, b, t)
								ShamanPower:EnsureProfileTable("cBuffNeedAll")
								ShamanPower.opt.cBuffNeedAll.r = r
								ShamanPower.opt.cBuffNeedAll.g = g
								ShamanPower.opt.cBuffNeedAll.b = b
								ShamanPower.opt.cBuffNeedAll.t = t
							end,
							hasAlpha = true
						}
					}
				},
				raid_cd_section = {
					order = 18,
					name = "|cff0070ddRaid Cooldowns|r",
					type = "group",
					args = {
						raid_cd_desc = {
							order = 0,
							type = "description",
							name = "Manage Bloodlust/Heroism and Mana Tide calling for your raid.\n\n|cffff8800Note:|r Requires the |cff00ff00ShamanPower [Raid Cooldowns]|r module to be enabled in your AddOns list.\n",
						},
						raidCDButtonScale = {
							order = 1,
							name = "Caller Button Scale",
							desc = "Adjust the size of the raid cooldown caller buttons",
							type = "range",
							width = 1.5,
							min = 0.5,
							max = 2.0,
							step = 0.05,
							get = function(info)
								return ShamanPower.opt.raidCDButtonScale or 1.0
							end,
							set = function(info, val)
								ShamanPower.opt.raidCDButtonScale = val
								ShamanPower:UpdateCallerButtonScale()
							end
						},
						raidCDButtonOpacity = {
							order = 2,
							name = "Caller Button Opacity",
							desc = "Adjust the opacity of the raid cooldown caller buttons",
							type = "range",
							width = 1.5,
							min = 0.1,
							max = 1.0,
							step = 0.05,
							get = function(info)
								return ShamanPower.opt.raidCDButtonOpacity or 1.0
							end,
							set = function(info, val)
								ShamanPower.opt.raidCDButtonOpacity = val
								ShamanPower:UpdateCallerButtonOpacity()
							end
						},
						raidCDShowWarningIcon = {
							order = 3,
							name = "Show Warning Icon",
							desc = "Show raid warning icon when calling cooldowns",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower.opt.raidCDShowWarningIcon ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.raidCDShowWarningIcon = val
							end
						},
						raidCDShowWarningText = {
							order = 4,
							name = "Show Warning Text",
							desc = "Show raid warning text when calling cooldowns",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower.opt.raidCDShowWarningText ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.raidCDShowWarningText = val
							end
						},
						raidCDPlaySound = {
							order = 5,
							name = "Play Sound",
							desc = "Play sound when calling cooldowns",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower.opt.raidCDPlaySound ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.raidCDPlaySound = val
							end
						},
						raidCDShowButtonAnimation = {
							order = 6,
							name = "Show Button Animation",
							desc = "Show cooldown animation on caller buttons",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower.opt.raidCDShowButtonAnimation ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.raidCDShowButtonAnimation = val
							end
						},
					}
				},
				sprange_section = {
					order = 15,
					name = "|cff0070ddTotem Range Tracker|r",
					type = "group",
					args = {
						sprange_desc = {
							order = 0,
							type = "description",
							name = "For non-shamans: Shows when you're in/out of range of party totem buffs from OTHER shamans.\n\n|cffff8800Note:|r Requires the |cff00ff00ShamanPower [Totem Range]|r module to be enabled in your AddOns list.\n",
						},
						sprange_opacity = {
							order = 1,
							name = "Opacity",
							desc = "Adjust the opacity of the totem range overlay",
							type = "range",
							width = 1.5,
							min = 0.2,
							max = 1.0,
							step = 0.1,
							get = function(info)
								return ShamanPower.opt.rangeTracker and ShamanPower.opt.rangeTracker.opacity or 1.0
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("rangeTracker")
								ShamanPower.opt.rangeTracker.opacity = val
								ShamanPower:UpdateSPRangeOpacity()
							end
						},
						sprange_icon_size = {
							order = 2,
							name = "Icon Size",
							desc = "Adjust the size of the totem range overlay icons",
							type = "range",
							width = 1.5,
							min = 20,
							max = 60,
							step = 4,
							get = function(info)
								return ShamanPower.opt.rangeTracker and ShamanPower.opt.rangeTracker.iconSize or 36
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("rangeTracker")
								ShamanPower.opt.rangeTracker.iconSize = val
								ShamanPower:UpdateSPRangeFrame()
							end
						},
						sprange_vertical = {
							order = 3,
							name = "Vertical Layout",
							desc = "Stack totem icons vertically instead of horizontally",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower.opt.rangeTracker and ShamanPower.opt.rangeTracker.vertical or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("rangeTracker")
								ShamanPower.opt.rangeTracker.vertical = val
								ShamanPower:UpdateSPRangeFrame()
								ShamanPower:UpdateSPRangeBorder()
							end
						},
						sprange_hide_names = {
							order = 4,
							name = "Hide Names",
							desc = "Hide totem names below the icons",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower.opt.rangeTracker and ShamanPower.opt.rangeTracker.hideNames or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("rangeTracker")
								ShamanPower.opt.rangeTracker.hideNames = val
								ShamanPower:UpdateSPRangeFrame()
							end
						},
						sprange_hide_border = {
							order = 5,
							name = "Hide Border",
							desc = "Hide the frame border and title on the totem range overlay",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower.opt.rangeTracker and ShamanPower.opt.rangeTracker.hideBorder or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("rangeTracker")
								ShamanPower.opt.rangeTracker.hideBorder = val
								ShamanPower:UpdateSPRangeBorder()
							end
						},
					}
				},
				partybuff_section = {
					order = 14,
					name = "|cff0070ddParty Buff Tracker|r",
					type = "group",
					args = {
						partybuff_desc = {
							order = 0,
							type = "description",
							name = "Shows which party members are in range of YOUR totems. Different from Totem Range Tracker which shows OTHER shamans' totems affecting you.\n\n|cffff8800Note:|r Requires the |cff00ff00ShamanPower [Party Totem Range]|r module to be enabled in your AddOns list.\n",
						},
						partybuff_display_mode = {
							order = 1,
							type = "select",
							name = "Display Mode",
							desc = "Choose how to display party member range information",
							width = 1.5,
							values = {
								["dots"] = "Dots Only",
								["numbers"] = "Numbers Only",
								["both"] = "Both Dots and Numbers",
								["none"] = "Disabled",
							},
							get = function(info)
								local showDots = ShamanPower.opt.showPartyRangeDots
								local showNumbers = ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled
								if showDots and showNumbers then return "both"
								elseif showDots then return "dots"
								elseif showNumbers then return "numbers"
								else return "none" end
							end,
							set = function(info, val)
								if not ShamanPower.opt.rangeCounter then
									ShamanPower.opt.rangeCounter = {}
								end
								if val == "dots" then
									ShamanPower.opt.showPartyRangeDots = true
									ShamanPower.opt.rangeCounter.enabled = false
								elseif val == "numbers" then
									ShamanPower.opt.showPartyRangeDots = false
									ShamanPower.opt.rangeCounter.enabled = true
								elseif val == "both" then
									ShamanPower.opt.showPartyRangeDots = true
									ShamanPower.opt.rangeCounter.enabled = true
								else
									ShamanPower.opt.showPartyRangeDots = false
									ShamanPower.opt.rangeCounter.enabled = false
								end
								ShamanPower:UpdatePartyRangeDots()
								ShamanPower:UpdateRangeCounters()
							end
						},
						partybuff_header_numbers = {
							order = 2,
							type = "header",
							name = "Number Counter Settings",
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
							end,
						},
						partybuff_location = {
							order = 3,
							type = "select",
							name = "Counter Location",
							desc = "Where to display the range counter numbers",
							width = 1.5,
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
							end,
							values = {
								["icon"] = "On Totem Icon",
								["unlocked"] = "Separate Movable Frame",
							},
							get = function(info)
								return (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.location) or "icon"
							end,
							set = function(info, val)
								if not ShamanPower.opt.rangeCounter then
									ShamanPower.opt.rangeCounter = {}
								end
								ShamanPower.opt.rangeCounter.location = val
								ShamanPower:UpdateRangeCounters()
							end
						},
						partybuff_colors = {
							order = 4,
							type = "toggle",
							name = "Use Element Colors",
							desc = "Color the numbers by element (Green=Earth, Red=Fire, Blue=Water, White=Air)",
							width = 1.5,
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
							end,
							get = function(info)
								return ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.useElementColors ~= false
							end,
							set = function(info, val)
								if not ShamanPower.opt.rangeCounter then
									ShamanPower.opt.rangeCounter = {}
								end
								ShamanPower.opt.rangeCounter.useElementColors = val
								ShamanPower:UpdateRangeCounters()
							end
						},
						partybuff_fontsize = {
							order = 5,
							type = "range",
							name = "Font Size",
							desc = "Size of the counter number",
							min = 8, max = 32, step = 1,
							width = 1.5,
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
							end,
							get = function(info)
								return (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.fontSize) or 14
							end,
							set = function(info, val)
								if not ShamanPower.opt.rangeCounter then
									ShamanPower.opt.rangeCounter = {}
								end
								ShamanPower.opt.rangeCounter.fontSize = val
								ShamanPower:UpdateRangeCounters()
							end
						},
						partybuff_header_frame = {
							order = 6,
							type = "header",
							name = "Unlocked Frame Settings",
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
									or (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.location ~= "unlocked")
							end,
						},
						partybuff_locked = {
							order = 6.5,
							type = "toggle",
							name = "Lock Frames (Click-through)",
							desc = "Lock the frames so they can't be moved and won't block mouse clicks",
							width = 1.5,
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
									or (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.location ~= "unlocked")
							end,
							get = function(info)
								return ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.locked
							end,
							set = function(info, val)
								if not ShamanPower.opt.rangeCounter then
									ShamanPower.opt.rangeCounter = {}
								end
								ShamanPower.opt.rangeCounter.locked = val
								ShamanPower:UpdateRangeCounterLock()
							end
						},
						partybuff_hide_frame = {
							order = 7,
							type = "toggle",
							name = "Hide Frame Background",
							desc = "Hide the frame border/background, showing only the number",
							width = 1.5,
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
									or (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.location ~= "unlocked")
							end,
							get = function(info)
								return ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.hideFrame
							end,
							set = function(info, val)
								if not ShamanPower.opt.rangeCounter then
									ShamanPower.opt.rangeCounter = {}
								end
								ShamanPower.opt.rangeCounter.hideFrame = val
								ShamanPower:UpdateRangeCounterFrameStyle()
							end
						},
						partybuff_hide_label = {
							order = 8,
							type = "toggle",
							name = "Hide Element Label",
							desc = "Hide the element name below the counter (Earth, Fire, Water, Air)",
							width = 1.5,
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
									or (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.location ~= "unlocked")
							end,
							get = function(info)
								return ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.hideLabel
							end,
							set = function(info, val)
								if not ShamanPower.opt.rangeCounter then
									ShamanPower.opt.rangeCounter = {}
								end
								ShamanPower.opt.rangeCounter.hideLabel = val
								ShamanPower:UpdateRangeCounterFrameStyle()
							end
						},
						partybuff_scale = {
							order = 9,
							type = "range",
							name = "Frame Scale",
							desc = "Scale of the unlocked counter frames",
							min = 0.5, max = 3.0, step = 0.1,
							width = 1.5,
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
									or (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.location ~= "unlocked")
							end,
							get = function(info)
								return (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.scale) or 1.0
							end,
							set = function(info, val)
								if not ShamanPower.opt.rangeCounter then
									ShamanPower.opt.rangeCounter = {}
								end
								ShamanPower.opt.rangeCounter.scale = val
								for element = 1, 4 do
									if ShamanPower.rangeCounterFrames[element] then
										ShamanPower.rangeCounterFrames[element]:SetScale(val)
									end
								end
							end
						},
						partybuff_opacity = {
							order = 10,
							type = "range",
							name = "Frame Opacity",
							desc = "Opacity of the unlocked counter frames",
							min = 10, max = 100, step = 5,
							width = 1.5,
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
									or (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.location ~= "unlocked")
							end,
							get = function(info)
								local val = (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.opacity) or 1.0
								return val * 100
							end,
							set = function(info, val)
								if not ShamanPower.opt.rangeCounter then
									ShamanPower.opt.rangeCounter = {}
								end
								ShamanPower.opt.rangeCounter.opacity = val / 100
								for element = 1, 4 do
									if ShamanPower.rangeCounterFrames[element] then
										ShamanPower.rangeCounterFrames[element]:SetAlpha(val / 100)
									end
								end
							end
						},
						partybuff_reset = {
							order = 11,
							type = "execute",
							name = "Reset Frame Positions",
							desc = "Reset unlocked counter frames to center of screen",
							hidden = function()
								return not (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.enabled)
									or (ShamanPower.opt.rangeCounter and ShamanPower.opt.rangeCounter.location ~= "unlocked")
							end,
							func = function()
								-- Clear saved positions
								if ShamanPower.opt.rangeCounter then
									ShamanPower.opt.rangeCounter.positions = {}
								end
								-- Reposition existing frames to center of screen
								for element = 1, 4 do
									local frame = ShamanPower.rangeCounterFrames[element]
									if frame then
										local xOffset = (element - 2.5) * 55  -- Spread horizontally
										frame:ClearAllPoints()
										frame:SetPoint("CENTER", UIParent, "CENTER", xOffset, 0)
									end
								end
							end
						},
					}
				},
				estrack_section = {
					order = 16,
					name = "|cff0070ddEarth Shield Tracker|r",
					type = "group",
					args = {
						estrack_desc = {
							order = 0,
							type = "description",
							name = "Track all Earth Shields cast by OTHER shamans in your party/raid. ALT+drag to move the frame.\n\n|cffff8800Note:|r Requires the |cff00ff00ShamanPower [Raid ES Tracker]|r module to be enabled in your AddOns list.\n",
						},
						estrack_enabled = {
							order = 1,
							name = "Enable Earth Shield Tracker",
							desc = "Enable the Earth Shield tracker to show all Earth Shields in your party/raid",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.esTracker and ShamanPower.opt.esTracker.enabled or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("esTracker")
								ShamanPower.opt.esTracker.enabled = val
								ShamanPower:ToggleESTracker()
							end
						},
						estrack_opacity = {
							order = 2,
							name = "Opacity",
							desc = "Adjust the opacity of the Earth Shield tracker",
							type = "range",
							width = "full",
							min = 0.2,
							max = 1.0,
							step = 0.1,
							get = function(info)
								return ShamanPower.opt.esTracker and ShamanPower.opt.esTracker.opacity or 1.0
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("esTracker")
								ShamanPower.opt.esTracker.opacity = val
								ShamanPower:UpdateESTrackerOpacity()
							end
						},
						estrack_icon_size = {
							order = 3,
							name = "Icon Size",
							desc = "Adjust the size of the Earth Shield tracker icons",
							type = "range",
							width = "full",
							min = 20,
							max = 60,
							step = 4,
							get = function(info)
								return ShamanPower.opt.esTracker and ShamanPower.opt.esTracker.iconSize or 40
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("esTracker")
								ShamanPower.opt.esTracker.iconSize = val
								ShamanPower:UpdateESTrackerFrame()
							end
						},
						estrack_options_header = {
							order = 4,
							type = "header",
							name = "Display Options",
						},
						estrack_vertical = {
							order = 5,
							name = "Vertical Layout",
							desc = "Stack Earth Shield icons vertically instead of horizontally",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.esTracker and ShamanPower.opt.esTracker.vertical or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("esTracker")
								ShamanPower.opt.esTracker.vertical = val
								ShamanPower:UpdateESTrackerFrame()
								ShamanPower:UpdateESTrackerBorder()
							end
						},
						estrack_hide_names = {
							order = 6,
							name = "Hide Names",
							desc = "Hide player names on the Earth Shield tracker",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.esTracker and ShamanPower.opt.esTracker.hideNames or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("esTracker")
								ShamanPower.opt.esTracker.hideNames = val
								ShamanPower:UpdateESTrackerFrame()
							end
						},
						estrack_hide_border = {
							order = 7,
							name = "Hide Border",
							desc = "Hide the frame border and title (use ALT+drag to move when hidden)",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.esTracker and ShamanPower.opt.esTracker.hideBorder or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("esTracker")
								ShamanPower.opt.esTracker.hideBorder = val
								ShamanPower:UpdateESTrackerBorder()
							end
						},
						estrack_hide_charges = {
							order = 8,
							name = "Hide Charges",
							desc = "Hide the charge count on Earth Shield icons",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.esTracker and ShamanPower.opt.esTracker.hideCharges or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("esTracker")
								ShamanPower.opt.esTracker.hideCharges = val
								ShamanPower:UpdateESTrackerFrame()
							end
						},
					}
				},
				shieldcharges_section = {
					order = 17,
					name = "|cff0070ddShield Charge Display|r",
					type = "group",
					args = {
						shieldcharges_desc = {
							order = 0,
							type = "description",
							name = "Large on-screen numbers showing your shield charges and Earth Shield charges on your target. ALT+drag to move when unlocked.\n\n|cffff8800Note:|r Requires the |cff00ff00ShamanPower [Shield Charge Display]|r module to be enabled in your AddOns list.\n",
						},
						shieldcharges_player = {
							order = 1,
							name = "Show Player Shield Charges",
							desc = "Show Lightning Shield or Water Shield charge count",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.shieldChargeDisplay and ShamanPower.opt.shieldChargeDisplay.showPlayerShield
							end,
							set = function(info, val)
								if ShamanPower.opt.shieldChargeDisplay then
									ShamanPower.opt.shieldChargeDisplay.showPlayerShield = val
									ShamanPower:UpdateShieldChargeDisplays()
								end
							end
						},
						shieldcharges_earth = {
							order = 2,
							name = "Show Earth Shield Charges",
							desc = "Show Earth Shield charge count on your current target",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.shieldChargeDisplay and ShamanPower.opt.shieldChargeDisplay.showEarthShield
							end,
							set = function(info, val)
								if ShamanPower.opt.shieldChargeDisplay then
									ShamanPower.opt.shieldChargeDisplay.showEarthShield = val
									ShamanPower:UpdateShieldChargeDisplays()
								end
							end
						},
						shieldcharges_scale = {
							order = 3,
							name = "Scale",
							desc = "Adjust the size of the shield charge numbers",
							type = "range",
							width = "full",
							min = 0.5,
							max = 3.0,
							step = 0.1,
							get = function(info)
								return ShamanPower.opt.shieldChargeDisplay and ShamanPower.opt.shieldChargeDisplay.scale or 1.0
							end,
							set = function(info, val)
								if ShamanPower.opt.shieldChargeDisplay then
									ShamanPower.opt.shieldChargeDisplay.scale = val
									ShamanPower:UpdateShieldChargeDisplays()
								end
							end
						},
						shieldcharges_opacity = {
							order = 4,
							name = "Opacity",
							desc = "Adjust the opacity of the shield charge display",
							type = "range",
							width = "full",
							min = 0.1,
							max = 1.0,
							step = 0.1,
							get = function(info)
								return ShamanPower.opt.shieldChargeDisplay and ShamanPower.opt.shieldChargeDisplay.opacity or 1.0
							end,
							set = function(info, val)
								if ShamanPower.opt.shieldChargeDisplay then
									ShamanPower.opt.shieldChargeDisplay.opacity = val
									ShamanPower:UpdateShieldChargeDisplays()
								end
							end
						},
						shieldcharges_locked = {
							order = 5,
							name = "Lock Position",
							desc = "Lock the shield charge displays in place (click-through)",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.shieldChargeDisplay and ShamanPower.opt.shieldChargeDisplay.locked
							end,
							set = function(info, val)
								if ShamanPower.opt.shieldChargeDisplay then
									ShamanPower.opt.shieldChargeDisplay.locked = val
									ShamanPower:UpdateShieldChargeDisplays()
								end
							end
						},
						shieldcharges_hide_ooc = {
							order = 6,
							name = "Hide Out of Combat",
							desc = "Hide the shield charge display when not in combat",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.shieldChargeDisplay and ShamanPower.opt.shieldChargeDisplay.hideOutOfCombat
							end,
							set = function(info, val)
								if ShamanPower.opt.shieldChargeDisplay then
									ShamanPower.opt.shieldChargeDisplay.hideOutOfCombat = val
									ShamanPower:UpdateShieldChargeDisplays()
								end
							end
						},
						shieldcharges_hide_none = {
							order = 7,
							name = "Hide When No Shields",
							desc = "Hide the display when no shields are active",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.shieldChargeDisplay and ShamanPower.opt.shieldChargeDisplay.hideNoShields
							end,
							set = function(info, val)
								if ShamanPower.opt.shieldChargeDisplay then
									ShamanPower.opt.shieldChargeDisplay.hideNoShields = val
									ShamanPower:UpdateShieldChargeDisplays()
								end
							end
						},
					}
				},
				reactivetotems_section = {
					order = 18,
					name = "|cff0070ddReactive Totems|r",
					type = "group",
					args = {
						reactive_desc = {
							order = 0,
							type = "description",
							name = "Shows large totem icons when you have fear, disease, or poison debuffs. Click to cast the appropriate cleansing totem.\n\n|cffff8800Note:|r Requires the |cff00ff00ShamanPower [Reactive Totems]|r module to be enabled in your AddOns list.\n",
						},
						reactive_enabled = {
							order = 1,
							name = "Enable Reactive Totems",
							desc = "Enable the reactive totem display when you have cleansable debuffs",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.enabled ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.enabled = val
									if ShamanPower.UpdateReactiveTotems then
										ShamanPower:UpdateReactiveTotems()
									end
								end
							end
						},
						reactive_locked = {
							order = 1.5,
							name = "Lock Positions",
							desc = "Lock the frame positions so they can't be dragged",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.locked or false
								end
								return false
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.locked = val
								end
							end
						},
						reactive_header_tracking = {
							order = 2,
							type = "header",
							name = "Debuff Tracking",
						},
						reactive_track_fear = {
							order = 3,
							name = "Track Fear/Charm",
							desc = "Show Tremor Totem icon when feared, charmed, or horrified",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.trackFear ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.trackFear = val
									if ShamanPower.UpdateReactiveTotems then
										ShamanPower:UpdateReactiveTotems()
									end
								end
							end
						},
						reactive_track_poison = {
							order = 4,
							name = "Track Poison",
							desc = "Show Poison Cleansing Totem icon when poisoned",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.trackPoison ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.trackPoison = val
									if ShamanPower.UpdateReactiveTotems then
										ShamanPower:UpdateReactiveTotems()
									end
								end
							end
						},
						reactive_track_disease = {
							order = 5,
							name = "Track Disease",
							desc = "Show Disease Cleansing Totem icon when diseased",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.trackDisease ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.trackDisease = val
									if ShamanPower.UpdateReactiveTotems then
										ShamanPower:UpdateReactiveTotems()
									end
								end
							end
						},
						reactive_header_appearance = {
							order = 6,
							type = "header",
							name = "Appearance",
						},
						reactive_icon_size = {
							order = 6.5,
							name = "Icon Size",
							desc = "Base size of the reactive totem icons in pixels",
							type = "range",
							width = 1.5,
							min = 32,
							max = 128,
							step = 4,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.iconSize or 64
								end
								return 64
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.iconSize = val
									if ShamanPower.UpdateReactiveTotemAppearance then
										ShamanPower:UpdateReactiveTotemAppearance()
									end
								end
							end
						},
						reactive_scale = {
							order = 7,
							name = "Scale",
							desc = "Additional scale multiplier for the icons",
							type = "range",
							width = 1.5,
							min = 0.5,
							max = 2.0,
							step = 0.1,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.scale or 1.0
								end
								return 1.0
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.scale = val
									if ShamanPower.UpdateReactiveTotemAppearance then
										ShamanPower:UpdateReactiveTotemAppearance()
									end
								end
							end
						},
						reactive_opacity = {
							order = 8,
							name = "Opacity",
							desc = "Adjust the opacity of the reactive totem icons",
							type = "range",
							width = 1.5,
							min = 0.2,
							max = 1.0,
							step = 0.1,
							get = function(info)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.opacity or 1.0
								end
								return 1.0
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.opacity = val
									if ShamanPower.UpdateReactiveTotemAppearance then
										ShamanPower:UpdateReactiveTotemAppearance()
									end
								end
							end
						},
						reactive_hide_border = {
							order = 9,
							name = "Hide Border",
							desc = "Hide the border around the reactive totem icons",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.hideBorder or false
								end
								return false
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.hideBorder = val
									if ShamanPower.UpdateReactiveTotemAppearance then
										ShamanPower:UpdateReactiveTotemAppearance()
									end
								end
							end
						},
						reactive_hide_background = {
							order = 10,
							name = "Hide Background",
							desc = "Hide the background behind the reactive totem icons",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.hideBackground or false
								end
								return false
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.hideBackground = val
									if ShamanPower.UpdateReactiveTotemAppearance then
										ShamanPower:UpdateReactiveTotemAppearance()
									end
								end
							end
						},
						reactive_font_size = {
							order = 11,
							name = "Font Size",
							desc = "Size of the totem name text",
							type = "range",
							width = 1.5,
							min = 8,
							max = 24,
							step = 1,
							get = function(info)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.fontSize or 12
								end
								return 12
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems and ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.fontSize = val
									if ShamanPower.UpdateReactiveTotemAppearance then
										ShamanPower:UpdateReactiveTotemAppearance()
									end
								end
							end
						},
						reactive_hide_debuff_text = {
							order = 11.1,
							name = "Hide Debuff Text",
							desc = "Hide the debuff name/type text (e.g. 'PlayerName: Fear')",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return not ShamanPower_ReactiveTotems.showDebuffName
								end
								return false
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.showDebuffName = not val
									if ShamanPower.UpdateReactiveTotemAppearance then
										ShamanPower:UpdateReactiveTotemAppearance()
									end
								end
							end
						},
						reactive_hide_totem_text = {
							order = 11.2,
							name = "Hide Totem Name",
							desc = "Hide the totem name text (e.g. 'Tremor Totem')",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return not ShamanPower_ReactiveTotems.showTotemName
								end
								return false
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.showTotemName = not val
									if ShamanPower.UpdateReactiveTotemAppearance then
										ShamanPower:UpdateReactiveTotemAppearance()
									end
								end
							end
						},
						reactive_header_effects = {
							order = 12,
							type = "header",
							name = "Effects",
						},
						reactive_glow = {
							order = 13,
							name = "Show Glow Effect",
							desc = "Show a pulsing glow around the reactive totem icons",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.showGlow ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.showGlow = val
									if ShamanPower.UpdateReactiveTotemAppearance then
										ShamanPower:UpdateReactiveTotemAppearance()
									end
								end
							end
						},
						reactive_glow_intensity = {
							order = 13.5,
							name = "Glow Intensity",
							desc = "Intensity of the pulsing glow effect",
							type = "range",
							width = 1.5,
							min = 0.2,
							max = 1.0,
							step = 0.1,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.glowIntensity or 0.8
								end
								return 0.8
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.glowIntensity = val
								end
							end
						},
						reactive_sound = {
							order = 14,
							name = "Play Alert Sound",
							desc = "Play a sound when a reactive totem icon appears",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.playSound or false
								end
								return false
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.playSound = val
								end
							end
						},
						reactive_font_outline = {
							order = 14.6,
							name = "Font Outline",
							desc = "Add outline to the text for better visibility",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPower_ReactiveTotems then
									return ShamanPower_ReactiveTotems.fontOutline ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPower_ReactiveTotems then
									ShamanPower_ReactiveTotems.fontOutline = val
									if ShamanPower.UpdateReactiveTotemAppearance then
										ShamanPower:UpdateReactiveTotemAppearance()
									end
								end
							end
						},
						reactive_header_buttons = {
							order = 15,
							type = "header",
							name = "Testing",
						},
						reactive_test = {
							order = 16,
							type = "execute",
							name = "Test All Frames",
							desc = "Show all reactive totem frames for 3 seconds with glow effect",
							func = function()
								if ShamanPower.TestReactiveTotems then
									ShamanPower:TestReactiveTotems()
								end
							end
						},
						reactive_show = {
							order = 17,
							type = "execute",
							name = "Show All (Position)",
							desc = "Show all frames for positioning - click-to-cast is disabled so you can drag freely",
							func = function()
								if ShamanPower.ShowAllReactiveFrames then
									ShamanPower:ShowAllReactiveFrames()
								end
							end
						},
						reactive_hide = {
							order = 18,
							type = "execute",
							name = "Hide All",
							desc = "Hide all frames and restore click-to-cast",
							func = function()
								if ShamanPower.HideAllReactiveFrames then
									ShamanPower:HideAllReactiveFrames()
								end
							end
						},
						reactive_reset = {
							order = 19,
							type = "execute",
							name = "Reset Positions",
							desc = "Reset all reactive totem frames to their default positions",
							func = function()
								if ShamanPower.ResetReactiveTotemPositions then
									ShamanPower:ResetReactiveTotemPositions()
								end
							end
						},
					}
				},
				expiringalerts_section = {
					order = 19,
					name = "|cff0070ddExpiring Alerts|r",
					type = "group",
					args = {
						alerts_desc = {
							order = 0,
							type = "description",
							name = "Scrolling combat text style alerts when shields expire, totems are destroyed/expire, and weapon imbues fade.\n\n|cffff8800Note:|r Requires the |cff00ff00ShamanPower [Expiring Alerts]|r module to be enabled in your AddOns list.\n",
						},
						alerts_enabled = {
							order = 1,
							name = "Enable Expiring Alerts",
							desc = "Enable scrolling text alerts for expiring buffs",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB then
									return ShamanPowerExpiringAlertsDB.enabled ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									ShamanPowerExpiringAlertsDB.enabled = val
								end
							end
						},
						alerts_header_display = {
							order = 2,
							type = "header",
							name = "Display Settings",
						},
						alerts_display_mode = {
							order = 3,
							name = "Display Mode",
							desc = "How to display alerts",
							type = "select",
							width = 1.0,
							values = {
								["text"] = "Text Only",
								["icon"] = "Icon Only",
								["both"] = "Icon + Text",
							},
							get = function(info)
								if ShamanPowerExpiringAlertsDB then
									return ShamanPowerExpiringAlertsDB.displayMode or "both"
								end
								return "both"
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									ShamanPowerExpiringAlertsDB.displayMode = val
								end
							end
						},
						alerts_animation = {
							order = 4,
							name = "Animation Style",
							desc = "How alerts animate on screen",
							type = "select",
							width = 1.0,
							values = {
								["scrollUp"] = "Scroll Up",
								["scrollDown"] = "Scroll Down",
								["staticFade"] = "Static Fade",
								["bounce"] = "Bounce",
							},
							get = function(info)
								if ShamanPowerExpiringAlertsDB then
									return ShamanPowerExpiringAlertsDB.animationStyle or "scrollUp"
								end
								return "scrollUp"
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									ShamanPowerExpiringAlertsDB.animationStyle = val
								end
							end
						},
						alerts_text_size = {
							order = 5,
							name = "Text Size",
							desc = "Size of alert text",
							type = "range",
							width = 1.5,
							min = 12,
							max = 36,
							step = 1,
							get = function(info)
								if ShamanPowerExpiringAlertsDB then
									return ShamanPowerExpiringAlertsDB.textSize or 24
								end
								return 24
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									ShamanPowerExpiringAlertsDB.textSize = val
									if ShamanPower.UpdateExpiringAlertsAppearance then
										ShamanPower:UpdateExpiringAlertsAppearance()
									end
								end
							end
						},
						alerts_icon_size = {
							order = 6,
							name = "Icon Size",
							desc = "Size of alert icons",
							type = "range",
							width = 1.5,
							min = 24,
							max = 64,
							step = 2,
							get = function(info)
								if ShamanPowerExpiringAlertsDB then
									return ShamanPowerExpiringAlertsDB.iconSize or 32
								end
								return 32
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									ShamanPowerExpiringAlertsDB.iconSize = val
									if ShamanPower.UpdateExpiringAlertsAppearance then
										ShamanPower:UpdateExpiringAlertsAppearance()
									end
								end
							end
						},
						alerts_duration = {
							order = 7,
							name = "Duration",
							desc = "How long alerts stay on screen (seconds)",
							type = "range",
							width = 1.5,
							min = 1,
							max = 5,
							step = 0.5,
							get = function(info)
								if ShamanPowerExpiringAlertsDB then
									return ShamanPowerExpiringAlertsDB.duration or 2.5
								end
								return 2.5
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									ShamanPowerExpiringAlertsDB.duration = val
								end
							end
						},
						alerts_opacity = {
							order = 8,
							name = "Opacity",
							desc = "Opacity of alerts (0-100%)",
							type = "range",
							width = 1.5,
							min = 50,
							max = 100,
							step = 5,
							get = function(info)
								if ShamanPowerExpiringAlertsDB then
									return ShamanPowerExpiringAlertsDB.opacity or 100
								end
								return 100
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									ShamanPowerExpiringAlertsDB.opacity = val
								end
							end
						},
						alerts_font_outline = {
							order = 9,
							name = "Font Outline",
							desc = "Add outline to text for better visibility",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB then
									return ShamanPowerExpiringAlertsDB.fontOutline ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									ShamanPowerExpiringAlertsDB.fontOutline = val
									if ShamanPower.UpdateExpiringAlertsAppearance then
										ShamanPower:UpdateExpiringAlertsAppearance()
									end
								end
							end
						},
						alerts_header_shields = {
							order = 10,
							type = "header",
							name = "Shield Alerts",
						},
						alerts_shields_enabled = {
							order = 11,
							name = "Enable Shield Alerts",
							desc = "Show alerts when shields fade",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.shields then
									return ShamanPowerExpiringAlertsDB.shields.enabled ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.shields then ShamanPowerExpiringAlertsDB.shields = {} end
									ShamanPowerExpiringAlertsDB.shields.enabled = val
								end
							end
						},
						alerts_shields_lightning = {
							order = 12,
							name = "Lightning Shield",
							desc = "Alert when Lightning Shield fades",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.shields then
									return ShamanPowerExpiringAlertsDB.shields.lightning ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.shields then ShamanPowerExpiringAlertsDB.shields = {} end
									ShamanPowerExpiringAlertsDB.shields.lightning = val
								end
							end
						},
						alerts_shields_water = {
							order = 13,
							name = "Water Shield",
							desc = "Alert when Water Shield fades",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.shields then
									return ShamanPowerExpiringAlertsDB.shields.water ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.shields then ShamanPowerExpiringAlertsDB.shields = {} end
									ShamanPowerExpiringAlertsDB.shields.water = val
								end
							end
						},
						alerts_shields_earth = {
							order = 14,
							name = "Earth Shield (on target)",
							desc = "Alert when Earth Shield fades on your assigned target",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.shields then
									return ShamanPowerExpiringAlertsDB.shields.earthShield ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.shields then ShamanPowerExpiringAlertsDB.shields = {} end
									ShamanPowerExpiringAlertsDB.shields.earthShield = val
								end
							end
						},
						alerts_shields_sound = {
							order = 15,
							name = "Play Sound",
							desc = "Play a sound when shield alerts appear",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.shields then
									return ShamanPowerExpiringAlertsDB.shields.sound or false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.shields then ShamanPowerExpiringAlertsDB.shields = {} end
									ShamanPowerExpiringAlertsDB.shields.sound = val
								end
							end
						},
						alerts_header_totems = {
							order = 20,
							type = "header",
							name = "Totem Alerts",
						},
						alerts_totems_enabled = {
							order = 21,
							name = "Enable Totem Alerts",
							desc = "Show alerts when totems are destroyed or expire",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems then
									return ShamanPowerExpiringAlertsDB.totems.enabled ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.totems then ShamanPowerExpiringAlertsDB.totems = {} end
									ShamanPowerExpiringAlertsDB.totems.enabled = val
								end
							end
						},
						alerts_totems_destroyed = {
							order = 22,
							name = "Totem Destroyed",
							desc = "Alert when a totem is destroyed by enemies",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems then
									return ShamanPowerExpiringAlertsDB.totems.destroyed ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.totems then ShamanPowerExpiringAlertsDB.totems = {} end
									ShamanPowerExpiringAlertsDB.totems.destroyed = val
								end
							end
						},
						alerts_totems_expired = {
							order = 23,
							name = "Totem Expired",
							desc = "Alert when a totem expires naturally (can be spammy)",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems then
									return ShamanPowerExpiringAlertsDB.totems.expired or false
								end
								return false
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.totems then ShamanPowerExpiringAlertsDB.totems = {} end
									ShamanPowerExpiringAlertsDB.totems.expired = val
								end
							end
						},
						alerts_totems_earth = {
							order = 24,
							name = "Earth Totems",
							desc = "Track Earth element totems",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems then
									return ShamanPowerExpiringAlertsDB.totems.earth ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.totems then ShamanPowerExpiringAlertsDB.totems = {} end
									ShamanPowerExpiringAlertsDB.totems.earth = val
								end
							end
						},
						alerts_totems_fire = {
							order = 25,
							name = "Fire Totems",
							desc = "Track Fire element totems",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems then
									return ShamanPowerExpiringAlertsDB.totems.fire ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.totems then ShamanPowerExpiringAlertsDB.totems = {} end
									ShamanPowerExpiringAlertsDB.totems.fire = val
								end
							end
						},
						alerts_totems_water = {
							order = 26,
							name = "Water Totems",
							desc = "Track Water element totems",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems then
									return ShamanPowerExpiringAlertsDB.totems.water ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.totems then ShamanPowerExpiringAlertsDB.totems = {} end
									ShamanPowerExpiringAlertsDB.totems.water = val
								end
							end
						},
						alerts_totems_air = {
							order = 27,
							name = "Air Totems",
							desc = "Track Air element totems",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems then
									return ShamanPowerExpiringAlertsDB.totems.air ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.totems then ShamanPowerExpiringAlertsDB.totems = {} end
									ShamanPowerExpiringAlertsDB.totems.air = val
								end
							end
						},
						alerts_totems_sound = {
							order = 28,
							name = "Play Sound",
							desc = "Play a sound when totem alerts appear",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.totems then
									return ShamanPowerExpiringAlertsDB.totems.sound or false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.totems then ShamanPowerExpiringAlertsDB.totems = {} end
									ShamanPowerExpiringAlertsDB.totems.sound = val
								end
							end
						},
						alerts_header_imbues = {
							order = 30,
							type = "header",
							name = "Weapon Imbue Alerts",
						},
						alerts_imbues_enabled = {
							order = 31,
							name = "Enable Imbue Alerts",
							desc = "Show alerts when weapon imbues fade",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.weaponImbues then
									return ShamanPowerExpiringAlertsDB.weaponImbues.enabled ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.weaponImbues then ShamanPowerExpiringAlertsDB.weaponImbues = {} end
									ShamanPowerExpiringAlertsDB.weaponImbues.enabled = val
								end
							end
						},
						alerts_imbues_mainhand = {
							order = 32,
							name = "Main Hand",
							desc = "Alert when main hand weapon imbue fades",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.weaponImbues then
									return ShamanPowerExpiringAlertsDB.weaponImbues.mainHand ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.weaponImbues then ShamanPowerExpiringAlertsDB.weaponImbues = {} end
									ShamanPowerExpiringAlertsDB.weaponImbues.mainHand = val
								end
							end
						},
						alerts_imbues_offhand = {
							order = 33,
							name = "Off Hand",
							desc = "Alert when off hand weapon imbue fades",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.weaponImbues then
									return ShamanPowerExpiringAlertsDB.weaponImbues.offHand ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.weaponImbues then ShamanPowerExpiringAlertsDB.weaponImbues = {} end
									ShamanPowerExpiringAlertsDB.weaponImbues.offHand = val
								end
							end
						},
						alerts_imbues_sound = {
							order = 34,
							name = "Play Sound",
							desc = "Play a sound when weapon imbue alerts appear",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerExpiringAlertsDB and ShamanPowerExpiringAlertsDB.weaponImbues then
									return ShamanPowerExpiringAlertsDB.weaponImbues.sound or false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerExpiringAlertsDB then
									if not ShamanPowerExpiringAlertsDB.weaponImbues then ShamanPowerExpiringAlertsDB.weaponImbues = {} end
									ShamanPowerExpiringAlertsDB.weaponImbues.sound = val
								end
							end
						},
						alerts_header_testing = {
							order = 40,
							type = "header",
							name = "Testing & Position",
						},
						alerts_test = {
							order = 41,
							type = "execute",
							name = "Test Alerts",
							desc = "Show test alerts for each type",
							func = function()
								if ShamanPower.ExpiringAlertsTest then
									ShamanPower:ExpiringAlertsTest()
								end
							end
						},
						alerts_show_pos = {
							order = 42,
							type = "execute",
							name = "Show Position Frame",
							desc = "Show the positioning frame to drag alerts to a new location",
							func = function()
								if ShamanPower.ExpiringAlertsShow then
									ShamanPower:ExpiringAlertsShow()
								end
							end
						},
						alerts_hide_pos = {
							order = 43,
							type = "execute",
							name = "Hide Position Frame",
							desc = "Hide the positioning frame",
							func = function()
								if ShamanPower.ExpiringAlertsHide then
									ShamanPower:ExpiringAlertsHide()
								end
							end
						},
						alerts_reset_pos = {
							order = 44,
							type = "execute",
							name = "Reset Position",
							desc = "Reset alert position to default (center of screen)",
							func = function()
								if ShamanPower.ExpiringAlertsReset then
									ShamanPower:ExpiringAlertsReset()
								end
							end
						},
					}
				},
				tremorreminder_section = {
					order = 19.5,
					name = "|cff0070ddTremor Reminder|r",
					type = "group",
					args = {
						tremor_desc = {
							order = 0,
							type = "description",
							name = "Proactive Tremor Totem reminder when targeting fear-casting mobs. Shows a reminder icon before anyone in your party gets feared.\n\n|cffff8800Note:|r Requires the |cff00ff00ShamanPower [Tremor Reminder]|r module to be enabled in your AddOns list.\n",
						},
						tremor_enabled = {
							order = 1,
							name = "Enable Tremor Reminder",
							desc = "Show reminder when targeting known fear-casting mobs",
							type = "toggle",
							width = "full",
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.enabled ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.enabled = val
								end
							end
						},
						tremor_hide_when_active = {
							order = 2,
							name = "Hide When Tremor Active",
							desc = "Hide the reminder when Tremor Totem is already placed",
							type = "toggle",
							width = "full",
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.hideWhenTremorActive ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.hideWhenTremorActive = val
								end
							end
						},
						tremor_use_defaults = {
							order = 3,
							name = "Use Default Mob List",
							desc = "Include the built-in list of TBC fear-casting mobs",
							type = "toggle",
							width = "full",
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.useDefaultList ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.useDefaultList = val
								end
							end
						},
						tremor_display_mode = {
							order = 4,
							name = "Display Mode",
							desc = "How to display the reminder",
							type = "select",
							width = 1.5,
							values = {
								icon = "Icon Only",
								text = "Text Only",
								both = "Icon + Text",
							},
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.displayMode or "icon"
								end
								return "icon"
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.displayMode = val
									if ShamanPower.UpdateTremorReminderAppearance then
										ShamanPower:UpdateTremorReminderAppearance()
									end
								end
							end
						},
						tremor_manage_mobs = {
							order = 5,
							type = "execute",
							name = "Manage Mob List",
							desc = "Open the fear-caster mob list manager to add or remove mobs",
							func = function()
								if ShamanPower.ShowMobList then
									ShamanPower:ShowMobList()
								else
									print("|cffff8800ShamanPower:|r Tremor Reminder module not loaded.")
								end
							end
						},
						tremor_header_appearance = {
							order = 10,
							type = "header",
							name = "Appearance",
						},
						tremor_icon_size = {
							order = 11,
							name = "Icon Size",
							desc = "Size of the reminder icon",
							type = "range",
							min = 32,
							max = 128,
							step = 1,
							width = 1.5,
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.iconSize or 64
								end
								return 64
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.iconSize = val
									if ShamanPower.UpdateTremorReminderAppearance then
										ShamanPower:UpdateTremorReminderAppearance()
									end
								end
							end
						},
						tremor_scale = {
							order = 12,
							name = "Scale",
							desc = "Scale multiplier for the reminder frame",
							type = "range",
							min = 0.5,
							max = 2.0,
							step = 0.1,
							width = 1.5,
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.scale or 1.0
								end
								return 1.0
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.scale = val
									if ShamanPower.UpdateTremorReminderAppearance then
										ShamanPower:UpdateTremorReminderAppearance()
									end
								end
							end
						},
						tremor_opacity = {
							order = 13,
							name = "Opacity",
							desc = "Opacity of the reminder icon (50-100%)",
							type = "range",
							min = 50,
							max = 100,
							step = 5,
							width = 1.5,
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.opacity or 100
								end
								return 100
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.opacity = val
									if ShamanPower.UpdateTremorReminderAppearance then
										ShamanPower:UpdateTremorReminderAppearance()
									end
								end
							end
						},
						tremor_text_size = {
							order = 14,
							name = "Text Size",
							desc = "Size of the reminder text (for Text or Icon+Text modes)",
							type = "range",
							min = 12,
							max = 48,
							step = 1,
							width = 1.5,
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.textSize or 24
								end
								return 24
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.textSize = val
									if ShamanPower.UpdateTremorReminderAppearance then
										ShamanPower:UpdateTremorReminderAppearance()
									end
								end
							end
						},
						tremor_header_glow = {
							order = 20,
							type = "header",
							name = "Glow Effect",
						},
						tremor_show_glow = {
							order = 21,
							name = "Show Glow",
							desc = "Show a pulsing glow effect around the icon",
							type = "toggle",
							width = 1.0,
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.showGlow ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.showGlow = val
									if ShamanPower.UpdateTremorReminderAppearance then
										ShamanPower:UpdateTremorReminderAppearance()
									end
								end
							end
						},
						tremor_glow_color = {
							order = 22,
							name = "Glow Color",
							desc = "Color of the glow effect",
							type = "color",
							width = 1.0,
							get = function(info)
								if ShamanPowerTremorReminderDB and ShamanPowerTremorReminderDB.glowColor then
									return ShamanPowerTremorReminderDB.glowColor.r or 1,
									       ShamanPowerTremorReminderDB.glowColor.g or 0.8,
									       ShamanPowerTremorReminderDB.glowColor.b or 0
								end
								return 1, 0.8, 0
							end,
							set = function(info, r, g, b)
								if ShamanPowerTremorReminderDB then
									if not ShamanPowerTremorReminderDB.glowColor then
										ShamanPowerTremorReminderDB.glowColor = {}
									end
									ShamanPowerTremorReminderDB.glowColor.r = r
									ShamanPowerTremorReminderDB.glowColor.g = g
									ShamanPowerTremorReminderDB.glowColor.b = b
									if ShamanPower.UpdateTremorReminderAppearance then
										ShamanPower:UpdateTremorReminderAppearance()
									end
								end
							end
						},
						tremor_header_sound = {
							order = 30,
							type = "header",
							name = "Sound",
						},
						tremor_play_sound = {
							order = 31,
							name = "Play Sound",
							desc = "Play a warning sound when targeting a fear-caster",
							type = "toggle",
							width = "full",
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.playSound ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.playSound = val
								end
							end
						},
						tremor_header_commands = {
							order = 40,
							type = "header",
							name = "Commands",
						},
						tremor_commands_desc = {
							order = 41,
							type = "description",
							name = "|cff888888Slash Commands:|r\n" ..
							       "  /sptremor show - Show frame for positioning\n" ..
							       "  /sptremor test - Show test alert\n" ..
							       "  /sptremor reset - Reset position\n" ..
							       "  /sptremor add <mob> - Add mob to list\n" ..
							       "  /sptremor remove <mob> - Remove mob\n" ..
							       "  /sptremor list - Show all fear-casters\n",
						},
						tremor_test = {
							order = 42,
							type = "execute",
							name = "Test Alert",
							desc = "Show a test alert",
							func = function()
								if ShamanPower.TremorReminderTest then
									ShamanPower:TremorReminderTest()
								end
							end
						},
						tremor_hide_test = {
							order = 42.5,
							type = "execute",
							name = "Hide Alert",
							desc = "Hide the test alert",
							func = function()
								if ShamanPower.TremorReminderHide then
									ShamanPower:TremorReminderHide()
								end
							end
						},
						tremor_show_pos = {
							order = 43,
							type = "execute",
							name = "Show Position Frame",
							desc = "Show the positioning frame to drag to a new location",
							func = function()
								if ShamanPower.TremorReminderShow then
									ShamanPower:TremorReminderShow()
								end
							end
						},
						tremor_reset_pos = {
							order = 44,
							type = "execute",
							name = "Reset Position",
							desc = "Reset position to default (center of screen)",
							func = function()
								if ShamanPower.TremorReminderReset then
									ShamanPower:TremorReminderReset()
								end
							end
						},
						tremor_lock_pos = {
							order = 45,
							name = "Lock Position",
							desc = "Prevent moving the frame with ALT+drag",
							type = "toggle",
							width = "full",
							get = function(info)
								if ShamanPowerTremorReminderDB then
									return ShamanPowerTremorReminderDB.locked ~= false
								end
								return true
							end,
							set = function(info, val)
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.locked = val
								end
							end
						},
						tremor_reset_moblist = {
							order = 46,
							type = "execute",
							width = "full",
							name = "Reset Mob List to Defaults",
							desc = "Remove all custom mobs and restore all removed default mobs",
							confirm = true,
							confirmText = "Are you sure you want to reset the mob list to defaults? This will remove all custom mobs you added and restore any default mobs you removed.",
							func = function()
								if ShamanPowerTremorReminderDB then
									ShamanPowerTremorReminderDB.fearCasters = {}
									if ShamanPower.RefreshMobList then
										ShamanPower:RefreshMobList()
									end
									print("|cff0070ddShamanPower|r [Tremor Reminder]: Mob list reset to defaults.")
								end
							end
						},
					}
				},
				totembar_items_section = {
					order = 7,
					name = "Totem Bar Items",
					type = "group",
					args = {
						totembar_desc = {
							order = 0,
							type = "description",
							name = "Choose which buttons appear on the mini totem bar.",
						},
						totembar_show_earth = {
							order = 1,
							type = "toggle",
							name = "Show Earth Totem",
							desc = "Show Earth totem button on the mini totem bar",
							width = "full",
							get = function(info)
								return ShamanPower.opt.totemBarShowEarth ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.totemBarShowEarth = val
								ShamanPower:UpdateMiniTotemBar()
							end
						},
						totembar_show_fire = {
							order = 2,
							type = "toggle",
							name = "Show Fire Totem",
							desc = "Show Fire totem button on the mini totem bar",
							width = "full",
							get = function(info)
								return ShamanPower.opt.totemBarShowFire ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.totemBarShowFire = val
								ShamanPower:UpdateMiniTotemBar()
							end
						},
						totembar_show_water = {
							order = 3,
							type = "toggle",
							name = "Show Water Totem",
							desc = "Show Water totem button on the mini totem bar",
							width = "full",
							get = function(info)
								return ShamanPower.opt.totemBarShowWater ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.totemBarShowWater = val
								ShamanPower:UpdateMiniTotemBar()
							end
						},
						totembar_show_air = {
							order = 4,
							type = "toggle",
							name = "Show Air Totem",
							desc = "Show Air totem button on the mini totem bar",
							width = "full",
							get = function(info)
								return ShamanPower.opt.totemBarShowAir ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.totemBarShowAir = val
								ShamanPower:UpdateMiniTotemBar()
							end
						},
						totembar_show_earthshield = {
							order = 5,
							type = "toggle",
							name = "Show Earth Shield",
							desc = "Show Earth Shield button on the mini totem bar (if you have the talent)",
							width = "full",
							get = function(info)
								return ShamanPower.opt.totemBarShowEarthShield ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.totemBarShowEarthShield = val
								ShamanPower:UpdateEarthShieldButton()
							end
						},
					}
				},
				totembar_order_section = {
					order = 8,
					name = "Totem Bar Order",
					type = "group",
					args = {
						totembar_order_desc = {
							order = 0,
							type = "description",
							name = "Choose the order of totem buttons on the mini totem bar.",
						},
						totem_bar_order_1 = {
							order = 1,
							type = "select",
							name = "1st Position",
							desc = "First totem button position",
							width = 1.2,
							values = {
								[1] = "Earth",
								[2] = "Fire",
								[3] = "Water",
								[4] = "Air",
							},
							get = function(info)
								return ShamanPower.opt.totemBarOrder and ShamanPower.opt.totemBarOrder[1] or 1
							end,
							set = function(info, val)
								if not ShamanPower.opt.totemBarOrder then ShamanPower.opt.totemBarOrder = {1, 2, 3, 4} end
								for i = 2, 4 do
									if ShamanPower.opt.totemBarOrder[i] == val then
										ShamanPower.opt.totemBarOrder[i] = ShamanPower.opt.totemBarOrder[1]
										break
									end
								end
								ShamanPower.opt.totemBarOrder[1] = val
								ShamanPower:UpdateMiniTotemBar()
							end
						},
						totem_bar_order_2 = {
							order = 2,
							type = "select",
							name = "2nd Position",
							desc = "Second totem button position",
							width = 1.2,
							values = {
								[1] = "Earth",
								[2] = "Fire",
								[3] = "Water",
								[4] = "Air",
							},
							get = function(info)
								return ShamanPower.opt.totemBarOrder and ShamanPower.opt.totemBarOrder[2] or 2
							end,
							set = function(info, val)
								if not ShamanPower.opt.totemBarOrder then ShamanPower.opt.totemBarOrder = {1, 2, 3, 4} end
								for i = 1, 4 do
									if i ~= 2 and ShamanPower.opt.totemBarOrder[i] == val then
										ShamanPower.opt.totemBarOrder[i] = ShamanPower.opt.totemBarOrder[2]
										break
									end
								end
								ShamanPower.opt.totemBarOrder[2] = val
								ShamanPower:UpdateMiniTotemBar()
							end
						},
						totem_bar_order_3 = {
							order = 3,
							type = "select",
							name = "3rd Position",
							desc = "Third totem button position",
							width = 1.2,
							values = {
								[1] = "Earth",
								[2] = "Fire",
								[3] = "Water",
								[4] = "Air",
							},
							get = function(info)
								return ShamanPower.opt.totemBarOrder and ShamanPower.opt.totemBarOrder[3] or 3
							end,
							set = function(info, val)
								if not ShamanPower.opt.totemBarOrder then ShamanPower.opt.totemBarOrder = {1, 2, 3, 4} end
								for i = 1, 4 do
									if i ~= 3 and ShamanPower.opt.totemBarOrder[i] == val then
										ShamanPower.opt.totemBarOrder[i] = ShamanPower.opt.totemBarOrder[3]
										break
									end
								end
								ShamanPower.opt.totemBarOrder[3] = val
								ShamanPower:UpdateMiniTotemBar()
							end
						},
						totem_bar_order_4 = {
							order = 4,
							type = "select",
							name = "4th Position",
							desc = "Fourth totem button position",
							width = 1.2,
							values = {
								[1] = "Earth",
								[2] = "Fire",
								[3] = "Water",
								[4] = "Air",
							},
							get = function(info)
								return ShamanPower.opt.totemBarOrder and ShamanPower.opt.totemBarOrder[4] or 4
							end,
							set = function(info, val)
								if not ShamanPower.opt.totemBarOrder then ShamanPower.opt.totemBarOrder = {1, 2, 3, 4} end
								for i = 1, 3 do
									if ShamanPower.opt.totemBarOrder[i] == val then
										ShamanPower.opt.totemBarOrder[i] = ShamanPower.opt.totemBarOrder[4]
										break
									end
								end
								ShamanPower.opt.totemBarOrder[4] = val
								ShamanPower:UpdateMiniTotemBar()
							end
						},
					}
				},
				totembar_duration_section = {
					order = 9,
					name = "Totem Duration Bars",
					type = "group",
					args = {
						duration_desc = {
							order = 0,
							type = "description",
							name = "Show progress bars on totem buttons indicating remaining duration.",
						},
						duration_bar_position = {
							order = 1,
							type = "select",
							name = "Bar Position",
							desc = "Position of the duration bar relative to totem icons (or None to disable)",
							width = 1.1,
							values = {
								["none"] = "None (Disabled)",
								["bottom"] = "Bottom (Horizontal)",
								["bottom_vert"] = "Bottom (Vertical)",
								["top"] = "Top (Horizontal)",
								["top_vert"] = "Top (Vertical)",
								["left"] = "Left",
								["right"] = "Right",
							},
							get = function(info)
								return ShamanPower.opt.durationBarPosition or "bottom"
							end,
							set = function(info, val)
								ShamanPower.opt.durationBarPosition = val
								ShamanPower:UpdateTotemProgressBarPositions()
								ShamanPower:UpdateMiniTotemBar()
							end
						},
						duration_bar_height = {
							order = 2,
							type = "range",
							name = "Bar Size",
							desc = "Size of the duration bar (height for horizontal bars, width for vertical bars)",
							width = 0.8,
							min = 2,
							max = 26,
							step = 1,
							hidden = function()
								return ShamanPower.opt.durationBarPosition == "none"
							end,
							get = function(info)
								return ShamanPower.opt.durationBarHeight or 3
							end,
							set = function(info, val)
								ShamanPower.opt.durationBarHeight = val
								ShamanPower:UpdateTotemProgressBarHeight()
							end
						},
						show_duration_text = {
							order = 3,
							type = "select",
							name = "Show Duration",
							desc = "Where to show the remaining totem duration time",
							width = 1.1,
							values = {
								["none"] = "None",
								["inside_top"] = "Inside Bar (Top)",
								["inside_bottom"] = "Inside Bar (Bottom)",
								["above"] = "Above Bar",
								["below"] = "Below Bar",
								["icon"] = "On Icon",
							},
							get = function(info)
								return ShamanPower.opt.durationTextLocation or "none"
							end,
							set = function(info, val)
								ShamanPower.opt.durationTextLocation = val
								ShamanPower:UpdateTotemProgressBarPositions()
								ShamanPower:UpdateTotemProgressBars()
							end
						},
						duration_text_size = {
							order = 3.5,
							type = "range",
							name = "Duration Text Size",
							desc = "Font size for the duration time text",
							width = 1.0,
							min = 6,
							max = 20,
							step = 1,
							hidden = function()
								return ShamanPower.opt.durationTextLocation == "none" or ShamanPower.opt.durationTextLocation == nil
							end,
							get = function(info)
								return ShamanPower.opt.durationTextSize or 8
							end,
							set = function(info, val)
								ShamanPower.opt.durationTextSize = val
								ShamanPower:UpdateTotemProgressBarPositions()
								ShamanPower:UpdateTotemProgressBars()
							end
						},
						pulse_bar_position = {
							order = 4,
							type = "select",
							name = "Pulse Bar Position",
							desc = "Position of the white pulse countdown bar for pulsing totems (Tremor, Healing Stream, etc)",
							width = 1.2,
							values = {
								["none"] = "None (Disabled)",
								["on_icon"] = "On Icon",
								["above"] = "Above (Horizontal)",
								["above_vert"] = "Above (Vertical)",
								["below"] = "Below (Horizontal)",
								["below_vert"] = "Below (Vertical)",
								["left"] = "Left",
								["right"] = "Right",
							},
							get = function(info)
								return ShamanPower.opt.pulseBarPosition or "on_icon"
							end,
							set = function(info, val)
								ShamanPower.opt.pulseBarPosition = val
								ShamanPower:UpdatePulseBarPositions()
							end
						},
						pulse_bar_size = {
							order = 4.5,
							type = "range",
							name = "Pulse Bar Size",
							desc = "Size of the pulse bar (height for horizontal bars, width for vertical bars)",
							width = 0.8,
							min = 2,
							max = 26,
							step = 1,
							hidden = function()
								return ShamanPower.opt.pulseBarPosition == "none" or ShamanPower.opt.pulseBarPosition == "on_icon"
							end,
							get = function(info)
								return ShamanPower.opt.pulseBarSize or 4
							end,
							set = function(info, val)
								ShamanPower.opt.pulseBarSize = val
								ShamanPower:UpdatePulseBarPositions()
							end
						},
						pulse_time_display = {
							order = 5,
							type = "select",
							name = "Show Pulse Time",
							desc = "Where to show the time until next pulse",
							width = 1.1,
							values = {
								["none"] = "None",
								["inside_top"] = "Inside Bar (Top)",
								["inside_bottom"] = "Inside Bar (Bottom)",
								["above"] = "Above Bar",
								["below"] = "Below Bar",
								["on_icon"] = "On Icon",
							},
							get = function(info)
								return ShamanPower.opt.pulseTimeDisplay or "none"
							end,
							set = function(info, val)
								ShamanPower.opt.pulseTimeDisplay = val
								ShamanPower:UpdatePulseBarPositions()
							end
						},
						pulse_text_size = {
							order = 5.5,
							type = "range",
							name = "Pulse Text Size",
							desc = "Font size for the pulse time text",
							width = 1.0,
							min = 6,
							max = 20,
							step = 1,
							hidden = function()
								return ShamanPower.opt.pulseTimeDisplay == "none" or ShamanPower.opt.pulseTimeDisplay == nil
							end,
							get = function(info)
								return ShamanPower.opt.pulseTextSize or 8
							end,
							set = function(info, val)
								ShamanPower.opt.pulseTextSize = val
								ShamanPower:UpdatePulseBarPositions()
							end
						},
					}
				},
				cdbar_items_section = {
					order = 12,
					name = "Cooldown Bar Items",
					type = "group",
					args = {
						cdbar_items_desc = {
							order = 0,
							type = "description",
							name = "Choose which buttons appear on the cooldown bar.\n",
						},
						show_cooldown_bar = {
							order = 1,
							type = "toggle",
							name = "Enable Cooldown Bar",
							desc = "Show a cooldown tracker bar with shields, ankh, nature's swiftness, etc.",
							width = "full",
							get = function(info)
								return ShamanPower.opt.showCooldownBar
							end,
							set = function(info, val)
								ShamanPower.opt.showCooldownBar = val
								ShamanPower:UpdateCooldownBar()
							end
						},
						cdbar_spacer1 = {
							order = 1.5,
							type = "description",
							name = " ",
							hidden = function() return not ShamanPower.opt.showCooldownBar end,
						},
						cdbar_show_shields = {
							order = 2,
							type = "toggle",
							name = "Shields (Lightning/Water Shield)",
							desc = "Show Lightning/Water Shield button on cooldown bar",
							width = "full",
							hidden = function() return not ShamanPower.opt.showCooldownBar end,
							get = function(info)
								return ShamanPower.opt.cdbarShowShields ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowShields = val
								if not InCombatLockdown() then
									ShamanPower:RecreateCooldownBar()
								end
							end
						},
						cdbar_show_recall = {
							order = 3,
							type = "toggle",
							name = "Totemic Call (Recall Totems)",
							desc = "Show Totemic Call button",
							width = "full",
							hidden = function() return not ShamanPower.opt.showCooldownBar end,
							get = function(info)
								return ShamanPower.opt.cdbarShowRecall ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowRecall = val
								if not InCombatLockdown() then
									ShamanPower:RecreateCooldownBar()
									ShamanPower:UpdateMiniTotemBar()
								end
							end
						},
						cdbar_recall_on_totembar = {
							order = 3.5,
							type = "toggle",
							name = "    |cff888888-> Show on Totem Bar instead|r",
							desc = "Move Totemic Call button to the totem bar instead of cooldown bar",
							width = "full",
							hidden = function()
								return not ShamanPower.opt.showCooldownBar or ShamanPower.opt.cdbarShowRecall == false
							end,
							get = function(info)
								return ShamanPower.opt.totemicCallOnTotemBar
							end,
							set = function(info, val)
								ShamanPower.opt.totemicCallOnTotemBar = val
								if not InCombatLockdown() then
									ShamanPower:RecreateCooldownBar()
									ShamanPower:UpdateMiniTotemBar()
								end
							end
						},
						cdbar_show_reincarnation = {
							order = 4,
							type = "toggle",
							name = "Reincarnation (Ankh)",
							desc = "Show Reincarnation cooldown on cooldown bar",
							width = "full",
							hidden = function() return not ShamanPower.opt.showCooldownBar end,
							get = function(info)
								return ShamanPower.opt.cdbarShowReincarnation ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowReincarnation = val
								if not InCombatLockdown() then
									ShamanPower:RecreateCooldownBar()
								end
							end
						},
						cdbar_show_ns = {
							order = 5,
							type = "toggle",
							name = "Nature's Swiftness",
							desc = "Show Nature's Swiftness cooldown on cooldown bar",
							width = "full",
							hidden = function() return not ShamanPower.opt.showCooldownBar end,
							get = function(info)
								return ShamanPower.opt.cdbarShowNS ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowNS = val
								if not InCombatLockdown() then
									ShamanPower:RecreateCooldownBar()
								end
							end
						},
						cdbar_show_manatide = {
							order = 6,
							type = "toggle",
							name = "Mana Tide Totem",
							desc = "Show Mana Tide Totem cooldown on cooldown bar",
							width = "full",
							hidden = function() return not ShamanPower.opt.showCooldownBar end,
							get = function(info)
								return ShamanPower.opt.cdbarShowManaTide ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowManaTide = val
								if not InCombatLockdown() then
									ShamanPower:RecreateCooldownBar()
								end
							end
						},
						cdbar_show_shamanistic_rage = {
							order = 7,
							type = "toggle",
							name = "Shamanistic Rage",
							desc = "Show Shamanistic Rage cooldown on cooldown bar (Enhancement talent)",
							width = "full",
							hidden = function() return not ShamanPower.opt.showCooldownBar end,
							get = function(info)
								return ShamanPower.opt.cdbarShowShamanisticRage ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowShamanisticRage = val
								if not InCombatLockdown() then
									ShamanPower:RecreateCooldownBar()
								end
							end
						},
						cdbar_show_bloodlust = {
							order = 8,
							type = "toggle",
							name = "Bloodlust / Heroism",
							desc = "Show Bloodlust/Heroism cooldown on cooldown bar",
							width = "full",
							hidden = function() return not ShamanPower.opt.showCooldownBar end,
							get = function(info)
								return ShamanPower.opt.cdbarShowBloodlust ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowBloodlust = val
								if not InCombatLockdown() then
									ShamanPower:RecreateCooldownBar()
								end
							end
						},
						cdbar_show_imbues = {
							order = 9,
							type = "toggle",
							name = "Weapon Imbues",
							desc = "Show Weapon Imbue button on cooldown bar",
							width = "full",
							hidden = function() return not ShamanPower.opt.showCooldownBar end,
							get = function(info)
								return ShamanPower.opt.cdbarShowImbues ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowImbues = val
								if not InCombatLockdown() then
									ShamanPower:RecreateCooldownBar()
								end
							end
						},
					}
				},
				cdbar_order_section = {
					order = 13,
					name = "Cooldown Bar Order",
					type = "group",
					hidden = function(info)
						return not ShamanPower.opt.showCooldownBar
					end,
					args = {
						cdbar_order_desc = {
							order = 0,
							type = "description",
							name = "Choose the order of buttons on the cooldown bar.",
						},
						cooldown_bar_order_1 = {
							order = 1,
							type = "select",
							name = "1st Position",
							desc = "First cooldown button position",
							width = 1.5,
							values = {
								[1] = "Shield",
								[2] = "Totemic Call",
								[3] = "Reincarnation",
								[4] = "Nature's Swiftness",
								[5] = "Mana Tide Totem",
								[6] = "Shamanistic Rage",
								[7] = "Bloodlust/Heroism",
								[8] = "Weapon Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[1] or 1
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7, 8} end
								for i = 2, 8 do
									if ShamanPower.opt.cooldownBarOrder[i] == val then
										ShamanPower.opt.cooldownBarOrder[i] = ShamanPower.opt.cooldownBarOrder[1]
										break
									end
								end
								ShamanPower.opt.cooldownBarOrder[1] = val
								if not InCombatLockdown() then ShamanPower:RecreateCooldownBar() end
							end
						},
						cooldown_bar_order_2 = {
							order = 2,
							type = "select",
							name = "2nd Position",
							desc = "Second cooldown button position",
							width = 1.5,
							values = {
								[1] = "Shield",
								[2] = "Totemic Call",
								[3] = "Reincarnation",
								[4] = "Nature's Swiftness",
								[5] = "Mana Tide Totem",
								[6] = "Shamanistic Rage",
								[7] = "Bloodlust/Heroism",
								[8] = "Weapon Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[2] or 2
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7, 8} end
								for i = 1, 8 do
									if i ~= 2 and ShamanPower.opt.cooldownBarOrder[i] == val then
										ShamanPower.opt.cooldownBarOrder[i] = ShamanPower.opt.cooldownBarOrder[2]
										break
									end
								end
								ShamanPower.opt.cooldownBarOrder[2] = val
								if not InCombatLockdown() then ShamanPower:RecreateCooldownBar() end
							end
						},
						cooldown_bar_order_3 = {
							order = 3,
							type = "select",
							name = "3rd Position",
							desc = "Third cooldown button position",
							width = 1.5,
							values = {
								[1] = "Shield",
								[2] = "Totemic Call",
								[3] = "Reincarnation",
								[4] = "Nature's Swiftness",
								[5] = "Mana Tide Totem",
								[6] = "Shamanistic Rage",
								[7] = "Bloodlust/Heroism",
								[8] = "Weapon Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[3] or 3
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7, 8} end
								for i = 1, 8 do
									if i ~= 3 and ShamanPower.opt.cooldownBarOrder[i] == val then
										ShamanPower.opt.cooldownBarOrder[i] = ShamanPower.opt.cooldownBarOrder[3]
										break
									end
								end
								ShamanPower.opt.cooldownBarOrder[3] = val
								if not InCombatLockdown() then ShamanPower:RecreateCooldownBar() end
							end
						},
						cooldown_bar_order_4 = {
							order = 4,
							type = "select",
							name = "4th Position",
							desc = "Fourth cooldown button position",
							width = 1.5,
							values = {
								[1] = "Shield",
								[2] = "Totemic Call",
								[3] = "Reincarnation",
								[4] = "Nature's Swiftness",
								[5] = "Mana Tide Totem",
								[6] = "Shamanistic Rage",
								[7] = "Bloodlust/Heroism",
								[8] = "Weapon Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[4] or 4
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7, 8} end
								for i = 1, 8 do
									if i ~= 4 and ShamanPower.opt.cooldownBarOrder[i] == val then
										ShamanPower.opt.cooldownBarOrder[i] = ShamanPower.opt.cooldownBarOrder[4]
										break
									end
								end
								ShamanPower.opt.cooldownBarOrder[4] = val
								if not InCombatLockdown() then ShamanPower:RecreateCooldownBar() end
							end
						},
						cooldown_bar_order_5 = {
							order = 5,
							type = "select",
							name = "5th Position",
							desc = "Fifth cooldown button position",
							width = 1.5,
							values = {
								[1] = "Shield",
								[2] = "Totemic Call",
								[3] = "Reincarnation",
								[4] = "Nature's Swiftness",
								[5] = "Mana Tide Totem",
								[6] = "Shamanistic Rage",
								[7] = "Bloodlust/Heroism",
								[8] = "Weapon Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[5] or 5
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7, 8} end
								for i = 1, 8 do
									if i ~= 5 and ShamanPower.opt.cooldownBarOrder[i] == val then
										ShamanPower.opt.cooldownBarOrder[i] = ShamanPower.opt.cooldownBarOrder[5]
										break
									end
								end
								ShamanPower.opt.cooldownBarOrder[5] = val
								if not InCombatLockdown() then ShamanPower:RecreateCooldownBar() end
							end
						},
						cooldown_bar_order_6 = {
							order = 6,
							type = "select",
							name = "6th Position",
							desc = "Sixth cooldown button position",
							width = 1.5,
							values = {
								[1] = "Shield",
								[2] = "Totemic Call",
								[3] = "Reincarnation",
								[4] = "Nature's Swiftness",
								[5] = "Mana Tide Totem",
								[6] = "Shamanistic Rage",
								[7] = "Bloodlust/Heroism",
								[8] = "Weapon Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[6] or 6
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7, 8} end
								for i = 1, 8 do
									if i ~= 6 and ShamanPower.opt.cooldownBarOrder[i] == val then
										ShamanPower.opt.cooldownBarOrder[i] = ShamanPower.opt.cooldownBarOrder[6]
										break
									end
								end
								ShamanPower.opt.cooldownBarOrder[6] = val
								if not InCombatLockdown() then ShamanPower:RecreateCooldownBar() end
							end
						},
						cooldown_bar_order_7 = {
							order = 7,
							type = "select",
							name = "7th Position",
							desc = "Seventh cooldown button position",
							width = 1.5,
							values = {
								[1] = "Shield",
								[2] = "Totemic Call",
								[3] = "Reincarnation",
								[4] = "Nature's Swiftness",
								[5] = "Mana Tide Totem",
								[6] = "Shamanistic Rage",
								[7] = "Bloodlust/Heroism",
								[8] = "Weapon Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[7] or 7
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7, 8} end
								for i = 1, 8 do
									if i ~= 7 and ShamanPower.opt.cooldownBarOrder[i] == val then
										ShamanPower.opt.cooldownBarOrder[i] = ShamanPower.opt.cooldownBarOrder[7]
										break
									end
								end
								ShamanPower.opt.cooldownBarOrder[7] = val
								if not InCombatLockdown() then ShamanPower:RecreateCooldownBar() end
							end
						},
						cooldown_bar_order_8 = {
							order = 8,
							type = "select",
							name = "8th Position",
							desc = "Eighth cooldown button position",
							width = 1.5,
							values = {
								[1] = "Shield",
								[2] = "Totemic Call",
								[3] = "Reincarnation",
								[4] = "Nature's Swiftness",
								[5] = "Mana Tide Totem",
								[6] = "Shamanistic Rage",
								[7] = "Bloodlust/Heroism",
								[8] = "Weapon Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[8] or 8
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7, 8} end
								for i = 1, 8 do
									if i ~= 8 and ShamanPower.opt.cooldownBarOrder[i] == val then
										ShamanPower.opt.cooldownBarOrder[i] = ShamanPower.opt.cooldownBarOrder[8]
										break
									end
								end
								ShamanPower.opt.cooldownBarOrder[8] = val
								if not InCombatLockdown() then ShamanPower:RecreateCooldownBar() end
							end
						},
					}
				},
				popout_section = {
					order = 20,
					name = "Pop-Out Trackers",
					type = "group",
					args = {
						popout_desc = {
							order = 0,
							type = "description",
							name = "Middle-click any totem or cooldown button to pop it out into a standalone, movable tracker. Use the cog wheel on each pop-out for individual settings (scale, opacity, hide frame). Middle-click or use the cog menu to return to bar. ALT+drag to move when frame is hidden.",
						},
						popout_return_all = {
							order = 1,
							type = "execute",
							name = "Return All to Bars",
							desc = "Return all popped-out trackers back to their original bars",
							width = 1.2,
							func = function()
								if InCombatLockdown() then
									print("|cffff0000ShamanPower:|r Cannot modify pop-outs during combat")
									return
								end
								ShamanPower:ReturnAllPopOutsToBar()
							end,
						},
						popout_hide_all_frames = {
							order = 2,
							type = "toggle",
							name = "Hide All Frames",
							desc = "Hide the frame/border around all popped-out trackers (show only icons). You can still use ALT+drag to move them.",
							width = 1.2,
							get = function(info)
								return ShamanPower.opt.poppedOutHideAllFrames or false
							end,
							set = function(info, val)
								ShamanPower.opt.poppedOutHideAllFrames = val
								-- Apply to all existing pop-outs
								for key, frame in pairs(ShamanPower.poppedOutFrames) do
									ShamanPower.opt.poppedOutSettings = ShamanPower.opt.poppedOutSettings or {}
									ShamanPower.opt.poppedOutSettings[key] = ShamanPower.opt.poppedOutSettings[key] or {}
									local wasHidden = ShamanPower.opt.poppedOutSettings[key].hideFrame
									if val ~= wasHidden then
										ShamanPower:TogglePopOutFrame(key)
									end
								end
							end,
						},
					}
				},
				totemplates_section = {
					order = 10,
					name = "Totem Plates",
					type = "group",
					args = {
						totemplates_desc = {
							order = 0,
							type = "description",
							name = "Replace totem nameplates with icons for easy identification in PvP and raids.\n\n|cffff8800Note:|r Requires the |cff00ff00ShamanPower [Totem Plates]|r module to be enabled in your AddOns list.\n",
						},
						totemplates_enabled = {
							order = 1,
							name = "Enable Totem Plates",
							desc = "Replace totem nameplates with clean icons",
							type = "toggle",
							width = "full",
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.enabled = val
								ShamanPower:ToggleTotemPlates()
							end
						},
						totemplates_show_enemy = {
							order = 2,
							name = "Show Enemy Totems",
							desc = "Replace enemy totem nameplates with icons",
							type = "toggle",
							width = 1.0,
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.showEnemy ~= false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.showEnemy = val
							end
						},
						totemplates_show_friendly = {
							order = 3,
							name = "Show Friendly Totems",
							desc = "Replace friendly totem nameplates with icons",
							type = "toggle",
							width = 1.0,
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.showFriendly ~= false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.showFriendly = val
							end
						},
						totemplates_size = {
							order = 4,
							name = "Icon Size",
							desc = "Size of the totem plate icons",
							type = "range",
							min = 20, max = 80, step = 2,
							width = 1.5,
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.iconSize or 40
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.iconSize = val
								ShamanPower:UpdateTotemPlatesSize()
							end
						},
						totemplates_alpha = {
							order = 5,
							name = "Opacity",
							desc = "Opacity of the totem plate icons",
							type = "range",
							min = 0.3, max = 1.0, step = 0.1,
							isPercent = true,
							width = 1.5,
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.alpha or 0.9
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.alpha = val
							end
						},
						totemplates_show_name = {
							order = 6,
							name = "Show Totem Name",
							desc = "Display the totem name below the icon",
							type = "toggle",
							width = "full",
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.showName or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.showName = val
							end
						},
						totemplates_pulse_header = {
							order = 7,
							type = "header",
							name = "Pulse Timer",
							hidden = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled) end,
						},
						totemplates_pulse_enabled = {
							order = 8,
							name = "Show Pulse Timer",
							desc = "Show countdown to next pulse for totems like Tremor, Healing Stream, etc.",
							type = "toggle",
							width = "full",
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.showPulseTimer ~= false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.showPulseTimer = val
								ShamanPower:UpdateTotemPlatesPulseSettings()
							end
						},
						totemplates_pulse_text = {
							order = 9,
							name = "Countdown Text",
							desc = "Display the time until next pulse as text on the icon",
							type = "toggle",
							width = 1.0,
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled and ShamanPower.opt.totemPlates.showPulseTimer) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.showPulseText ~= false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.showPulseText = val
								ShamanPower:UpdateTotemPlatesPulseSettings()
							end
						},
						totemplates_pulse_bar = {
							order = 10,
							name = "Pulse Bar",
							desc = "Display a progress bar showing time until next pulse",
							type = "toggle",
							width = 1.0,
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled and ShamanPower.opt.totemPlates.showPulseTimer) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.showPulseBar ~= false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.showPulseBar = val
								ShamanPower:UpdateTotemPlatesPulseSettings()
							end
						},
						totemplates_pulse_cooldown = {
							order = 11,
							name = "Cooldown Swipe",
							desc = "Display a cooldown swipe animation on the icon",
							type = "toggle",
							width = 1.0,
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled and ShamanPower.opt.totemPlates.showPulseTimer) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.showPulseCooldown or false
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.showPulseCooldown = val
								ShamanPower:UpdateTotemPlatesPulseSettings()
							end
						},
						totemplates_pulse_text_size = {
							order = 12,
							name = "Text Size",
							desc = "Font size for the pulse countdown text",
							type = "range",
							min = 8, max = 24, step = 1,
							width = 1.0,
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled and ShamanPower.opt.totemPlates.showPulseTimer and ShamanPower.opt.totemPlates.showPulseText) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.pulseTextSize or 14
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.pulseTextSize = val
								ShamanPower:UpdateTotemPlatesPulseSettings()
							end
						},
						totemplates_pulse_bar_height = {
							order = 13,
							name = "Bar Height",
							desc = "Height of the pulse progress bar",
							type = "range",
							min = 2, max = 12, step = 1,
							width = 1.0,
							disabled = function() return not (ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.enabled and ShamanPower.opt.totemPlates.showPulseTimer and ShamanPower.opt.totemPlates.showPulseBar) end,
							get = function(info)
								return ShamanPower.opt.totemPlates and ShamanPower.opt.totemPlates.pulseBarHeight or 4
							end,
							set = function(info, val)
								ShamanPower:EnsureProfileTable("totemPlates")
								ShamanPower.opt.totemPlates.pulseBarHeight = val
								ShamanPower:UpdateTotemPlatesPulseSettings()
							end
						},
					}
				},
			}
		},
		raids = {
			order = 4,
			name = _G.RAID,
			desc = L["Raid only options"],
			type = "group",
			cmdHidden = true,
			hidden = true,  -- Hidden - paladin-specific Main Tank/Assist blessing options not applicable to Shamans
			disabled = function(info)
				return ShamanPower.opt.enabled == false or not isShaman
			end,
			args = {
				visibility = {
					order = 1,
					name = L["Visibility Settings"],
					type = "group",
					inline = true,
					args = {
						hide_high = {
							order = 1,
							type = "toggle",
							name = L["Hide Bench (by Subgroup)"],
							desc = L["While you are in a Raid dungeon, hide any players outside of the usual subgroups for that dungeon. For example, if you are in a 10-player dungeon, any players in Group 3 or higher will be hidden."],
							width = "full",
							get = function()
								return ShamanPower.opt.hideHighGroups
							end,
							set = function(info, val)
								ShamanPower.opt.hideHighGroups = val
								ShamanPower:UpdateRoster()
							end
						},
					},
				},
				mainroles = {
					order = 2,
					name = L["Main Tank / Main Assist Roles"],
					type = "group",
					inline = true,
					args = {
						mainroles_desc = {
							order = 0,
							type = "description",
							name = ShamanPower.isWrath and L["MAIN_ROLES_DESCRIPTION_WRATH"] or L["MAIN_ROLES_DESCRIPTION"]
						},
						maintank_buff = {
							order = 1,
							type = "toggle",
							name = L["Auto-Buff Main Tank"],
							desc = ShamanPower.isWrath and L["If you enable this option ShamanPower will automatically over-write a Greater Blessing with a Normal Blessing on players marked with the |cffffd200Main Tank|r role in the Blizzard Raid Panel. This is useful for spot buffing the |cffffd200Main Tank|r role with Blessing of Sanctuary."] or L["If you enable this option ShamanPower will automatically over-write a Greater Blessing with a Normal Blessing on players marked with the |cffffd200Main Tank|r role in the Blizzard Raid Panel. This is useful to avoid blessing the |cffffd200Main Tank|r role with a Greater Blessing of Salvation."],
							width = "full",
							get = function(info)
								return ShamanPower.opt.mainTank
							end,
							set = function(info, val)
								ShamanPower.opt.mainTank = val
								ShamanPower:UpdateRoster()
							end
						},
						maintank_GBWarriorPDeathKnight = {
							order = 2,
							type = "select",
							name = ShamanPower.isWrath and L["Override Warriors / Death Knights..."] or L["Override Warriors..."],
							desc = ShamanPower.isWrath and L["Select the Greater Blessing assignment you wish to over-write on Main Tank: Warriors / Death Knights."] or L["Select the Greater Blessing assignment you wish to over-write on Main Tank: Warriors."],
							width = 1.2,
							disabled = function(info)
								return (not (ShamanPower.opt.mainTank))
							end,
							get = function(info)
								return ShamanPower.opt.mainTankGSpellsW
							end,
							set = function(info, val)
								ShamanPower.opt.mainTankGSpellsW = val
								ShamanPower:UpdateRoster()
							end,
							values = ShamanPower.isWrath and {
								[0] = L["None"],
								[1] = ShamanPower.GSpells[1], -- Greater Blessing of Wisdom
								[2] = ShamanPower.GSpells[2], -- Greater Blessing of Might
								[3] = ShamanPower.GSpells[3], -- Greater Blessing of Kings
								[4] = ShamanPower.GSpells[4] -- Greater Blessing of Sanctuary
							} or {
								[0] = L["None"],
								[1] = ShamanPower.GSpells[1], -- Greater Blessing of Wisdom
								[2] = ShamanPower.GSpells[2], -- Greater Blessing of Might
								[3] = ShamanPower.GSpells[3], -- Greater Blessing of Kings
								[4] = ShamanPower.GSpells[4], -- Greater Blessing of Salvation
								[5] = ShamanPower.GSpells[5], -- Greater Blessing of Light
								[6] = ShamanPower.GSpells[6] -- Greater Blessing of Sanctuary
							}
						},
						maintank_NBWarriorPDeathKnight = {
							order = 3,
							type = "select",
							name = L["...with Normal..."],
							desc = ShamanPower.isWrath and L["Select the Normal Blessing you wish to use to over-write the Main Tank: Warriors / Death Knights."] or L["Select the Normal Blessing you wish to use to over-write the Main Tank: Warriors."],
							width = 0.9,
							disabled = function(info)
								return (not (ShamanPower.opt.mainTank))
							end,
							get = function(info)
								return ShamanPower.opt.mainTankSpellsW
							end,
							set = function(info, val)
								ShamanPower.opt.mainTankSpellsW = val
								ShamanPower:UpdateRoster()
							end,
							values = ShamanPower.isWrath and {
								[0] = L["None"],
								[1] = ShamanPower.Spells[1], -- Blessing of Wisdom
								[2] = ShamanPower.Spells[2], -- Blessing of Might
								[3] = ShamanPower.Spells[3], -- Blessing of Kings
								[4] = ShamanPower.Spells[4] -- Blessing of Sanctuary
							} or {
								[0] = L["None"],
								[1] = ShamanPower.Spells[1], -- Earth Totem
								[2] = ShamanPower.Spells[2], -- Fire Totem
								[3] = ShamanPower.Spells[3], -- Water Totem
								[4] = ShamanPower.Spells[4], -- Air Totem
							}
						},
						maintank_GBDruidPPaladin = {
							order = 4,
							type = "select",
							name = L["Override Druids / Paladins..."],
							desc = L["Select the Greater Blessing assignment you wish to over-write on Main Tank: Druids / Paladins."],
							width = 1.2,
							disabled = function(info)
								return (not (ShamanPower.opt.mainTank))
							end,
							get = function(info)
								return ShamanPower.opt.mainTankGSpellsDP
							end,
							set = function(info, val)
								ShamanPower.opt.mainTankGSpellsDP = val
								ShamanPower:UpdateRoster()
							end,
							values = ShamanPower.isWrath and {
								[0] = L["None"],
								[1] = ShamanPower.GSpells[1], -- Greater Blessing of Wisdom
								[2] = ShamanPower.GSpells[2], -- Greater Blessing of Might
								[3] = ShamanPower.GSpells[3], -- Greater Blessing of Kings
								[4] = ShamanPower.GSpells[4] -- Greater Blessing of Sanctuary
							} or {
								[0] = L["None"],
								[1] = ShamanPower.GSpells[1], -- Greater Blessing of Wisdom
								[2] = ShamanPower.GSpells[2], -- Greater Blessing of Might
								[3] = ShamanPower.GSpells[3], -- Greater Blessing of Kings
								[4] = ShamanPower.GSpells[4], -- Greater Blessing of Salvation
								[5] = ShamanPower.GSpells[5], -- Greater Blessing of Light
								[6] = ShamanPower.GSpells[6] -- Greater Blessing of Sanctuary
							}
						},
						maintank_NBDruidPPaladin = {
							order = 5,
							type = "select",
							name = L["...with Normal..."],
							desc = L["Select the Normal Blessing you wish to use to over-write the Main Tank: Druids / Paladins."],
							width = 0.9,
							disabled = function(info)
								return (not (ShamanPower.opt.mainTank))
							end,
							get = function(info)
								return ShamanPower.opt.mainTankSpellsDP
							end,
							set = function(info, val)
								ShamanPower.opt.mainTankSpellsDP = val
								ShamanPower:UpdateRoster()
							end,
							values = ShamanPower.isWrath and {
								[0] = L["None"],
								[1] = ShamanPower.Spells[1], -- Blessing of Wisdom
								[2] = ShamanPower.Spells[2], -- Blessing of Might
								[3] = ShamanPower.Spells[3], -- Blessing of Kings
								[4] = ShamanPower.Spells[4] -- Blessing of Sanctuary
							} or {
								[0] = L["None"],
								[1] = ShamanPower.Spells[1], -- Earth Totem
								[2] = ShamanPower.Spells[2], -- Fire Totem
								[3] = ShamanPower.Spells[3], -- Water Totem
								[4] = ShamanPower.Spells[4], -- Air Totem
							}
						},
						mainassist_buff = {
							order = 6,
							type = "toggle",
							name = L["Auto-Buff Main Assistant"],
							desc = ShamanPower.isWrath and L["If you enable this option ShamanPower will automatically over-write a Greater Blessing with a Normal Blessing on players marked with the |cffffd200Main Assistant|r role in the Blizzard Raid Panel. This is useful for spot buffing the |cffffd200Main Assistant|r role with Blessing of Sanctuary."] or L["If you enable this option ShamanPower will automatically over-write a Greater Blessing with a Normal Blessing on players marked with the |cffffd200Main Assistant|r role in the Blizzard Raid Panel. This is useful to avoid blessing the |cffffd200Main Assistant|r role with a Greater Blessing of Salvation."],
							width = "full",
							get = function(info)
								return ShamanPower.opt.mainAssist
							end,
							set = function(info, val)
								ShamanPower.opt.mainAssist = val
								ShamanPower:UpdateRoster()
							end
						},
						mainassist_GBWarriorPDeathKnight = {
							order = 7,
							type = "select",
							name = ShamanPower.isWrath and L["Override Warriors / Death Knights..."] or L["Override Warriors..."],
							desc = ShamanPower.isWrath and L["Select the Greater Blessing assignment you wish to over-write on Main Assist: Warriors / Death Knights."] or L["Select the Greater Blessing assignment you wish to over-write on Main Assist: Warriors."],
							width = 1.2,
							disabled = function(info)
								return (not (ShamanPower.opt.mainAssist))
							end,
							get = function(info)
								return ShamanPower.opt.mainAssistGSpellsW
							end,
							set = function(info, val)
								ShamanPower.opt.mainAssistGSpellsW = val
								ShamanPower:UpdateRoster()
							end,
							values = ShamanPower.isWrath and {
								[0] = L["None"],
								[1] = ShamanPower.GSpells[1], -- Greater Blessing of Wisdom
								[2] = ShamanPower.GSpells[2], -- Greater Blessing of Might
								[3] = ShamanPower.GSpells[3], -- Greater Blessing of Kings
								[4] = ShamanPower.GSpells[4] -- Greater Blessing of Sanctuary
							} or {
								[0] = L["None"],
								[1] = ShamanPower.GSpells[1], -- Greater Blessing of Wisdom
								[2] = ShamanPower.GSpells[2], -- Greater Blessing of Might
								[3] = ShamanPower.GSpells[3], -- Greater Blessing of Kings
								[4] = ShamanPower.GSpells[4], -- Greater Blessing of Salvation
								[5] = ShamanPower.GSpells[5], -- Greater Blessing of Light
								[6] = ShamanPower.GSpells[6] -- Greater Blessing of Sanctuary
							}
						},
						mainassist_NBWarriorPDeathKnight = {
							order = 8,
							type = "select",
							name = L["...with Normal..."],
							desc = ShamanPower.isWrath and L["Select the Normal Blessing you wish to use to over-write the Main Assist: Warriors / Death Knights."] or L["Select the Normal Blessing you wish to use to over-write the Main Assist: Warriors."],
							width = 0.9,
							disabled = function(info)
								return (not (ShamanPower.opt.mainAssist))
							end,
							get = function(info)
								return ShamanPower.opt.mainAssistSpellsW
							end,
							set = function(info, val)
								ShamanPower.opt.mainAssistSpellsW = val
								ShamanPower:UpdateRoster()
							end,
							values = ShamanPower.isWrath and {
								[0] = L["None"],
								[1] = ShamanPower.Spells[1], -- Blessing of Wisdom
								[2] = ShamanPower.Spells[2], -- Blessing of Might
								[3] = ShamanPower.Spells[3], -- Blessing of Kings
								[4] = ShamanPower.Spells[4] -- Blessing of Sanctuary
							} or {
								[0] = L["None"],
								[1] = ShamanPower.Spells[1], -- Earth Totem
								[2] = ShamanPower.Spells[2], -- Fire Totem
								[3] = ShamanPower.Spells[3], -- Water Totem
								[4] = ShamanPower.Spells[4], -- Air Totem
							}
						},
						mainassist_GBDruidPaladin = {
							order = 9,
							type = "select",
							name = L["Override Druids / Paladins..."],
							desc = L["Select the Greater Blessing assignment you wish to over-write on Main Assist: Druids / Paladins."],
							width = 1.2,
							disabled = function(info)
								return (not (ShamanPower.opt.mainAssist))
							end,
							get = function(info)
								return ShamanPower.opt.mainAssistGSpellsDP
							end,
							set = function(info, val)
								ShamanPower.opt.mainAssistGSpellsDP = val
								ShamanPower:UpdateRoster()
							end,
							values = ShamanPower.isWrath and {
								[0] = L["None"],
								[1] = ShamanPower.GSpells[1], -- Greater Blessing of Wisdom
								[2] = ShamanPower.GSpells[2], -- Greater Blessing of Might
								[3] = ShamanPower.GSpells[3], -- Greater Blessing of Kings
								[4] = ShamanPower.GSpells[4] -- Greater Blessing of Sanctuary
							} or {
								[0] = L["None"],
								[1] = ShamanPower.GSpells[1], -- Greater Blessing of Wisdom
								[2] = ShamanPower.GSpells[2], -- Greater Blessing of Might
								[3] = ShamanPower.GSpells[3], -- Greater Blessing of Kings
								[4] = ShamanPower.GSpells[4], -- Greater Blessing of Salvation
								[5] = ShamanPower.GSpells[5], -- Greater Blessing of Light
								[6] = ShamanPower.GSpells[6] -- Greater Blessing of Sanctuary
							}
						},
						mainassist_NBDruidPaladin = {
							order = 10,
							type = "select",
							name = L["...with Normal..."],
							desc = L["Select the Normal Blessing you wish to use to over-write the Main Assist: Druids / Paladins."],
							width = 0.9,
							disabled = function(info)
								return (not (ShamanPower.opt.mainAssist))
							end,
							get = function(info)
								return ShamanPower.opt.mainAssistSpellsDP
							end,
							set = function(info, val)
								ShamanPower.opt.mainAssistSpellsDP = val
								ShamanPower:UpdateRoster()
							end,
							values = ShamanPower.isWrath and {
								[0] = L["None"],
								[1] = ShamanPower.Spells[1], -- Blessing of Wisdom
								[2] = ShamanPower.Spells[2], -- Blessing of Might
								[3] = ShamanPower.Spells[3], -- Blessing of Kings
								[4] = ShamanPower.Spells[4] -- Blessing of Sanctuary
							} or {
								[0] = L["None"],
								[1] = ShamanPower.Spells[1], -- Earth Totem
								[2] = ShamanPower.Spells[2], -- Fire Totem
								[3] = ShamanPower.Spells[3], -- Water Totem
								[4] = ShamanPower.Spells[4], -- Air Totem
							}
						}
					}
				}
			}
		},
		totems = {
			order = 4,
			name = "Totem Assignments",
			type = "execute",
			guiHidden = true,
			func = function()
				if not (UnitAffectingCombat("player")) then
					ShamanPowerBlessings_Toggle()
				end
			end
		},
		options = {
			order = 5,
			name = "ShamanPower Options",
			type = "execute",
			guiHidden = true,
			func = function()
				if not (UnitAffectingCombat("player")) then
					ShamanPower:OpenConfigWindow()
				end
			end
		}
	}
}
