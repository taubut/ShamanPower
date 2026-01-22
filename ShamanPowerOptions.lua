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
			cmdHidden = true,
			disabled = function(info)
				return ShamanPower.opt.enabled == false
			end,
			args = {
				aura_button = {
					order = 1,
					name = L["Aura Button"],
					type = "group",
					inline = true,
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
					inline = true,
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
					inline = true,
					disabled = function(info)
						return ShamanPower.opt.enabled == false or not isShaman
					end,
					args = {
						auto_desc = {
							order = 0,
							type = "description",
							name = "[|cffffd200Enable|r/|cffffd200Disable|r] The Mini Totem Bar (clickable totem buttons)."
						},
						auto_enable = {
							order = 1,
							type = "toggle",
							name = "Mini Totem Bar",
							desc = "[Enable/Disable] The Mini Totem Bar",
							width = 1.1,
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
							width = 1.1,
							get = function(info)
								return ShamanPower.opt.showDropAllButton
							end,
							set = function(info, val)
								ShamanPower.opt.showDropAllButton = val
								ShamanPower:UpdateRoster()
							end
						},
						show_party_range = {
							order = 2.1,
							type = "toggle",
							name = "Show Party Range Dots",
							desc = "[Enable/Disable] Show colored dots indicating which party members are in range of your totems (party only, not raid)",
							width = 1.3,
							get = function(info)
								return ShamanPower.opt.showPartyRangeDots
							end,
							set = function(info, val)
								ShamanPower.opt.showPartyRangeDots = val
								ShamanPower:UpdatePartyRangeDots()
							end
						},
						show_totem_flyouts = {
							order = 2.25,
							type = "toggle",
							name = "Show Totem Flyouts",
							desc = "[Enable/Disable] Show flyout menus on mouseover for quick totem selection (TotemTimers style)",
							width = 1.0,
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
							name = "Show ES Flyout",
							desc = "[Enable/Disable] Show flyout menu on Earth Shield button for quick target selection",
							width = 1.3,
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
							type = "description",
							name = "\n|cffffd200Drop Order:|r Choose the order totems are dropped",
							fontSize = "medium",
						},
						drop_order_1 = {
							order = 2.6,
							type = "select",
							name = "1st",
							desc = "First totem to drop",
							width = 0.5,
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
							name = "2nd",
							desc = "Second totem to drop",
							width = 0.5,
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
							name = "3rd",
							desc = "Third totem to drop",
							width = 0.5,
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
							name = "4th",
							desc = "Fourth totem to drop",
							width = 0.5,
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
							type = "description",
							name = "\n|cffffd200Exclude from Drop All:|r Skip these totems when using Drop All",
							fontSize = "medium",
						},
						exclude_earth = {
							order = 2.902,
							type = "toggle",
							name = "Earth",
							desc = "Exclude Earth totem from the Drop All button",
							width = 0.5,
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
							name = "Fire",
							desc = "Exclude Fire totem from the Drop All button",
							width = 0.5,
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
							name = "Water",
							desc = "Exclude Water totem from the Drop All button",
							width = 0.5,
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
							name = "Air",
							desc = "Exclude Air totem from the Drop All button",
							width = 0.5,
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
					inline = true,
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
					inline = true,
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
					order = 0.5,
					name = "Layout",
					type = "group",
					inline = true,
					args = {
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
					}
				},
				scale_section = {
					order = 1,
					name = "Scale",
					type = "group",
					inline = true,
					args = {
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
					order = 1.5,
					name = "Opacity",
					type = "group",
					inline = true,
					args = {
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
					order = 2,
					name = "Button Padding",
					type = "group",
					inline = true,
					args = {
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
					order = 3,
					name = "Frame Visibility",
					type = "group",
					inline = true,
					args = {
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
					order = 4,
					name = "Textures",
					type = "group",
					inline = true,
					args = {
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
					order = 5,
					name = "Cooldown Display",
					type = "group",
					inline = true,
					hidden = function(info)
						return not ShamanPower.opt.showCooldownBar
					end,
					args = {
						cdbar_show_progress_bars = {
							order = 1,
							type = "toggle",
							name = "Progress Bars",
							desc = "Show colored progress bars on the edges of cooldown buttons",
							width = 0.8,
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
							name = "Color Sweep",
							desc = "Show greyed-out sweep overlay as time depletes",
							width = 0.8,
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
							name = "CD Text",
							desc = "Show cooldown time remaining as text",
							width = 0.6,
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
							name = "Shield Charge Colors",
							desc = "Color shield charge count based on remaining charges (Green=full, Yellow=half, Red=low). Disable for plain white text.",
							width = 1.0,
							get = function(info)
								return ShamanPower.opt.shieldChargeColors ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.shieldChargeColors = val
							end
						},
						spacer1 = {
							order = 5,
							type = "description",
							name = "",
							width = "full",
						},
						cdbar_progress_position = {
							order = 6,
							type = "select",
							name = "Bar Position",
							desc = "Position of the progress bar relative to icons",
							width = 1.1,
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
							name = "Bar Size",
							desc = "Size of the duration bar (height for horizontal bars, width for vertical bars)",
							width = 0.8,
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
							name = "Show Duration",
							desc = "Where to show the remaining duration time",
							width = 0.9,
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
					order = 6,
					name = L["Change the status colors of the buff buttons"],
					type = "group",
					inline = true,
					disabled = function(info)
						return ShamanPower.opt.enabled == false or not isShaman
					end,
					args = {
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
					order = 7,
					name = "Raid Cooldowns",
					type = "group",
					inline = true,
					args = {
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
					order = 8,
					name = "Totem Range Tracker (SPRange)",
					type = "group",
					inline = true,
					args = {
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
								return ShamanPower_RangeTracker and ShamanPower_RangeTracker.opacity or 1.0
							end,
							set = function(info, val)
								if ShamanPower_RangeTracker then
									ShamanPower_RangeTracker.opacity = val
									ShamanPower:UpdateSPRangeOpacity()
								end
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
								return ShamanPower_RangeTracker and ShamanPower_RangeTracker.iconSize or 36
							end,
							set = function(info, val)
								if ShamanPower_RangeTracker then
									ShamanPower_RangeTracker.iconSize = val
									ShamanPower:UpdateSPRangeFrame()
								end
							end
						},
						sprange_vertical = {
							order = 3,
							name = "Vertical Layout",
							desc = "Stack totem icons vertically instead of horizontally",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower_RangeTracker and ShamanPower_RangeTracker.vertical or false
							end,
							set = function(info, val)
								if ShamanPower_RangeTracker then
									ShamanPower_RangeTracker.vertical = val
									ShamanPower:UpdateSPRangeFrame()
									ShamanPower:UpdateSPRangeBorder()
								end
							end
						},
						sprange_hide_names = {
							order = 4,
							name = "Hide Names",
							desc = "Hide totem names below the icons",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower_RangeTracker and ShamanPower_RangeTracker.hideNames or false
							end,
							set = function(info, val)
								if ShamanPower_RangeTracker then
									ShamanPower_RangeTracker.hideNames = val
									ShamanPower:UpdateSPRangeFrame()
								end
							end
						},
						sprange_hide_border = {
							order = 5,
							name = "Hide Border",
							desc = "Hide the frame border and title on the totem range overlay",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower_RangeTracker and ShamanPower_RangeTracker.hideBorder or false
							end,
							set = function(info, val)
								if ShamanPower_RangeTracker then
									ShamanPower_RangeTracker.hideBorder = val
									ShamanPower:UpdateSPRangeBorder()
								end
							end
						},
					}
				},
				estrack_section = {
					order = 8.5,
					name = "Earth Shield Tracker",
					type = "group",
					inline = true,
					args = {
						estrack_enabled = {
							order = 0.5,
							name = "Enable",
							desc = "Enable the Earth Shield tracker to show all Earth Shields in your party/raid",
							type = "toggle",
							width = 0.6,
							get = function(info)
								return ShamanPower_ESTracker and ShamanPower_ESTracker.enabled or false
							end,
							set = function(info, val)
								if ShamanPower_ESTracker then
									ShamanPower_ESTracker.enabled = val
									ShamanPower:ToggleESTracker()
								end
							end
						},
						estrack_opacity = {
							order = 1,
							name = "Opacity",
							desc = "Adjust the opacity of the Earth Shield tracker",
							type = "range",
							width = 1.3,
							min = 0.2,
							max = 1.0,
							step = 0.1,
							get = function(info)
								return ShamanPower_ESTracker and ShamanPower_ESTracker.opacity or 1.0
							end,
							set = function(info, val)
								if ShamanPower_ESTracker then
									ShamanPower_ESTracker.opacity = val
									ShamanPower:UpdateESTrackerOpacity()
								end
							end
						},
						estrack_icon_size = {
							order = 2,
							name = "Icon Size",
							desc = "Adjust the size of the Earth Shield tracker icons",
							type = "range",
							width = 1.5,
							min = 20,
							max = 60,
							step = 4,
							get = function(info)
								return ShamanPower_ESTracker and ShamanPower_ESTracker.iconSize or 36
							end,
							set = function(info, val)
								if ShamanPower_ESTracker then
									ShamanPower_ESTracker.iconSize = val
									ShamanPower:UpdateESTrackerFrame()
								end
							end
						},
						estrack_vertical = {
							order = 3,
							name = "Vertical Layout",
							desc = "Stack Earth Shield icons vertically instead of horizontally",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower_ESTracker and ShamanPower_ESTracker.vertical or false
							end,
							set = function(info, val)
								if ShamanPower_ESTracker then
									ShamanPower_ESTracker.vertical = val
									ShamanPower:UpdateESTrackerFrame()
									ShamanPower:UpdateESTrackerBorder()
								end
							end
						},
						estrack_hide_names = {
							order = 4,
							name = "Hide Names",
							desc = "Hide player names on the Earth Shield tracker",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower_ESTracker and ShamanPower_ESTracker.hideNames or false
							end,
							set = function(info, val)
								if ShamanPower_ESTracker then
									ShamanPower_ESTracker.hideNames = val
									ShamanPower:UpdateESTrackerFrame()
								end
							end
						},
						estrack_hide_border = {
							order = 5,
							name = "Hide Border",
							desc = "Hide the frame border and title (use ALT+drag to move when hidden)",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower_ESTracker and ShamanPower_ESTracker.hideBorder or false
							end,
							set = function(info, val)
								if ShamanPower_ESTracker then
									ShamanPower_ESTracker.hideBorder = val
									ShamanPower:UpdateESTrackerBorder()
								end
							end
						},
						estrack_hide_charges = {
							order = 6,
							name = "Hide Charges",
							desc = "Hide the charge count on Earth Shield icons",
							type = "toggle",
							width = 1.0,
							get = function(info)
								return ShamanPower_ESTracker and ShamanPower_ESTracker.hideCharges or false
							end,
							set = function(info, val)
								if ShamanPower_ESTracker then
									ShamanPower_ESTracker.hideCharges = val
									ShamanPower:UpdateESTrackerFrame()
								end
							end
						},
					}
				},
				totembar_items_section = {
					order = 9,
					name = "Totem Bar Items",
					type = "group",
					inline = true,
					args = {
						totembar_show_earth = {
							order = 1,
							type = "toggle",
							name = "Earth",
							desc = "Show Earth totem button on the mini totem bar",
							width = 0.5,
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
							name = "Fire",
							desc = "Show Fire totem button on the mini totem bar",
							width = 0.45,
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
							name = "Water",
							desc = "Show Water totem button on the mini totem bar",
							width = 0.5,
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
							name = "Air",
							desc = "Show Air totem button on the mini totem bar",
							width = 0.4,
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
							name = "Earth Shield",
							desc = "Show Earth Shield button on the mini totem bar (if you have the talent)",
							width = 0.8,
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
					order = 10,
					name = "Totem Bar Order",
					type = "group",
					inline = true,
					args = {
						totem_bar_order_1 = {
							order = 1,
							type = "select",
							name = "1st",
							desc = "First totem button position",
							width = 0.5,
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
							name = "2nd",
							desc = "Second totem button position",
							width = 0.5,
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
							name = "3rd",
							desc = "Third totem button position",
							width = 0.5,
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
							name = "4th",
							desc = "Fourth totem button position",
							width = 0.5,
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
					order = 10.5,
					name = "Totem Bar Duration",
					type = "group",
					inline = true,
					args = {
						duration_bar_position = {
							order = 1,
							type = "select",
							name = "Bar Position",
							desc = "Position of the duration bar relative to totem icons",
							width = 1.1,
							values = {
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
							min = 3,
							max = 16,
							step = 1,
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
						pulse_bar_position = {
							order = 4,
							type = "select",
							name = "Pulse Bar Position",
							desc = "Position of the white pulse countdown bar for pulsing totems (Tremor, Healing Stream, etc)",
							width = 1.2,
							values = {
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
					}
				},
				cdbar_items_section = {
					order = 11,
					name = "Cooldown Bar",
					type = "group",
					inline = true,
					args = {
						show_cooldown_bar = {
							order = 0,
							type = "toggle",
							name = "Show Cooldown Bar",
							desc = "[Enable/Disable] Show a cooldown tracker bar (Shields, Ankh, Nature's Swiftness, etc.)",
							width = 1.3,
							get = function(info)
								return ShamanPower.opt.showCooldownBar
							end,
							set = function(info, val)
								ShamanPower.opt.showCooldownBar = val
								ShamanPower:UpdateCooldownBar()
							end
						},
						cdbar_show_shields = {
							order = 1,
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
							type = "toggle",
							name = "Shields",
							desc = "Show Lightning/Water Shield button on cooldown bar",
							width = 0.6,
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
							order = 2,
							type = "toggle",
							name = "Recall",
							desc = "Show Totemic Call button on cooldown bar",
							width = 0.5,
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
							get = function(info)
								return ShamanPower.opt.cdbarShowRecall ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowRecall = val
								if not InCombatLockdown() then
									ShamanPower:RecreateCooldownBar()
								end
							end
						},
						cdbar_show_reincarnation = {
							order = 3,
							type = "toggle",
							name = "Ankh",
							desc = "Show Reincarnation cooldown on cooldown bar",
							width = 0.5,
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
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
							order = 4,
							type = "toggle",
							name = "NS",
							desc = "Show Nature's Swiftness cooldown on cooldown bar",
							width = 0.4,
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
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
							order = 5,
							type = "toggle",
							name = "Mana Tide",
							desc = "Show Mana Tide Totem cooldown on cooldown bar",
							width = 0.6,
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
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
						cdbar_show_bloodlust = {
							order = 6,
							type = "toggle",
							name = "BL/Hero",
							desc = "Show Bloodlust/Heroism cooldown on cooldown bar",
							width = 0.55,
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
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
							order = 7,
							type = "toggle",
							name = "Imbues",
							desc = "Show Weapon Imbue button on cooldown bar",
							width = 0.55,
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
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
					order = 12,
					name = "Cooldown Bar Order",
					type = "group",
					inline = true,
					hidden = function(info)
						return not ShamanPower.opt.showCooldownBar
					end,
					args = {
						cooldown_bar_order_1 = {
							order = 1,
							type = "select",
							name = "1st",
							desc = "First cooldown button position",
							width = 0.42,
							values = {
								[1] = "Shield",
								[2] = "Recall",
								[3] = "Ankh",
								[4] = "NS",
								[5] = "Mana Tide",
								[6] = "BL/Hero",
								[7] = "Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[1] or 1
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7} end
								for i = 2, 7 do
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
							name = "2nd",
							desc = "Second cooldown button position",
							width = 0.42,
							values = {
								[1] = "Shield",
								[2] = "Recall",
								[3] = "Ankh",
								[4] = "NS",
								[5] = "Mana Tide",
								[6] = "BL/Hero",
								[7] = "Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[2] or 2
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7} end
								for i = 1, 7 do
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
							name = "3rd",
							desc = "Third cooldown button position",
							width = 0.42,
							values = {
								[1] = "Shield",
								[2] = "Recall",
								[3] = "Ankh",
								[4] = "NS",
								[5] = "Mana Tide",
								[6] = "BL/Hero",
								[7] = "Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[3] or 3
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7} end
								for i = 1, 7 do
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
							name = "4th",
							desc = "Fourth cooldown button position",
							width = 0.42,
							values = {
								[1] = "Shield",
								[2] = "Recall",
								[3] = "Ankh",
								[4] = "NS",
								[5] = "Mana Tide",
								[6] = "BL/Hero",
								[7] = "Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[4] or 4
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7} end
								for i = 1, 7 do
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
							name = "5th",
							desc = "Fifth cooldown button position",
							width = 0.42,
							values = {
								[1] = "Shield",
								[2] = "Recall",
								[3] = "Ankh",
								[4] = "NS",
								[5] = "Mana Tide",
								[6] = "BL/Hero",
								[7] = "Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[5] or 5
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7} end
								for i = 1, 7 do
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
							name = "6th",
							desc = "Sixth cooldown button position",
							width = 0.42,
							values = {
								[1] = "Shield",
								[2] = "Recall",
								[3] = "Ankh",
								[4] = "NS",
								[5] = "Mana Tide",
								[6] = "BL/Hero",
								[7] = "Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[6] or 6
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7} end
								for i = 1, 7 do
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
							name = "7th",
							desc = "Seventh cooldown button position",
							width = 0.42,
							values = {
								[1] = "Shield",
								[2] = "Recall",
								[3] = "Ankh",
								[4] = "NS",
								[5] = "Mana Tide",
								[6] = "BL/Hero",
								[7] = "Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[7] or 7
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7} end
								for i = 1, 6 do
									if ShamanPower.opt.cooldownBarOrder[i] == val then
										ShamanPower.opt.cooldownBarOrder[i] = ShamanPower.opt.cooldownBarOrder[7]
										break
									end
								end
								ShamanPower.opt.cooldownBarOrder[7] = val
								if not InCombatLockdown() then ShamanPower:RecreateCooldownBar() end
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
