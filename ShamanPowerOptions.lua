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
					name = L["Change the way ShamanPower looks"],
					type = "group",
					inline = true,
					args = {
						buffscale = {
							order = 1,
							name = L["ShamanPower Buttons Scale"],
							desc = L["This allows you to adjust the overall size of the ShamanPower Buttons"],
							type = "range",
							width = 1.5,
							min = 0.4,
							max = 1.5,
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
								ShamanPower:UpdateRoster()
							end
						},
						padding1 = {
							order = 2,
							name = "",
							type = "description",
							width = .2
						},
						layout = {
							order = 3,
							type = "select",
							width = 1.4,
							name = L["Buff Button | Player Button Layout"],
							desc = L["LAYOUT_TOOLTIP"],
							disabled = function(info)
								return ShamanPower.opt.enabled == false or not isShaman
							end,
							get = function(info)
								return ShamanPower.opt.layout
							end,
							set = function(info, val)
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
										if frame then
											local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint()
											if point and xOfs and yOfs then
												frame:ClearAllPoints()
												frame:SetPoint(point, relativeTo, relativePoint, xOfs + deltaX, yOfs + deltaY)
											end
										end
									end
								end
							end,
							values = {
								["Horizontal"] = "Horizontal",
								["Vertical"] = "Vertical",
							}
						},
						skin = {
							order = 4,
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
						padding2 = {
							order = 5,
							name = "",
							type = "description",
							width = .2
						},
						edges = {
							order = 6,
							name = L["Borders"],
							desc = L["Change the Button Borders"],
							type = "select",
							width = 1.4,
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
						assignmentsscale = {
							order = 7,
							name = L["Totem Assignments Scale"],
							desc = L["This allows you to adjust the overall size of the Totem Assignments Panel"],
							type = "range",
							width = 1.5,
							min = 0.4,
							max = 1.5,
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
						padding3 = {
							order = 8,
							name = "",
							type = "description",
							width = .2
						},
						reset = {
							order = 9,
							name = L["Reset Frames"],
							desc = L["Reset all ShamanPower frames back to center"],
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
				},
				settings_color = {
					order = 4,
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
								ShamanPower.opt.cBuffNeedAll.r = r
								ShamanPower.opt.cBuffNeedAll.g = g
								ShamanPower.opt.cBuffNeedAll.b = b
								ShamanPower.opt.cBuffNeedAll.t = t
							end,
							hasAlpha = true
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
								ShamanPower.opt.autobuff.waitforpeople = val
								ShamanPower:UpdateRoster()
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
								ShamanPower.opt.display.buffDuration = val
								ShamanPower:UpdateRoster()
							end
						}
					}
				},
				drag_button = {
					order = 5,
					name = L["Drag Handle Button"],
					type = "group",
					inline = true,
					disabled = function(info)
						return ShamanPower.opt.enabled == false
					end,
					args = {
						misc_desc = {
							order = 0,
							type = "description",
							name = L["[|cffffd200Enable|r/|cffffd200Disable|r] The Drag Handle Button."]
						},
						drag_enable = {
							order = 1,
							type = "toggle",
							name = L["Drag Handle"],
							desc = L["[Enable/Disable] The Drag Handle"],
							width = 1.1,
							get = function(info)
								return ShamanPower.opt.display.enableDragHandle
							end,
							set = function(info, val)
								ShamanPower.opt.display.enableDragHandle = val
								ShamanPower:UpdateRoster()
							end
						}
					}
				}
			}
		},
		raids = {
			order = 3,
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
