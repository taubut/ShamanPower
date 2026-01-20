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
							name = "Totem Bar Scale",
							desc = "Adjust the size of the totem bar and main ShamanPower buttons",
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
								ShamanPower:UpdateCooldownBarScale()
								ShamanPower:UpdateRoster()
							end
						},
						cooldownBarScale = {
							order = 1.5,
							name = "Cooldown Bar Scale",
							desc = "Adjust the size of the cooldown tracker bar independently",
							type = "range",
							width = 1.5,
							min = 0.4,
							max = 1.5,
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
						unlock_cooldown_bar = {
							order = 1.6,
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
						hide_totem_bar_frame = {
							order = 1.7,
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
							order = 1.8,
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
						show_button_keybinds = {
							order = 1.9,
							type = "toggle",
							name = "Show Keybinds on Buttons",
							desc = "Display keybind text on cooldown bar buttons (top-right corner)",
							width = 1.5,
							disabled = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
							get = function(info)
								return ShamanPower.opt.showButtonKeybinds
							end,
							set = function(info, val)
								ShamanPower.opt.showButtonKeybinds = val
								ShamanPower:UpdateButtonKeybindText()
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
								-- Don't change layout in combat
								if InCombatLockdown() then return end

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
						show_cooldown_bar = {
							order = 2.2,
							type = "toggle",
							name = "Show Cooldown Bar",
							desc = "[Enable/Disable] Show a cooldown tracker bar below the totem bar (Shields, Ankh, Nature's Swiftness)",
							width = 1.3,
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
							width = 1.3,
							get = function(info)
								return ShamanPower.opt.showTotemFlyouts
							end,
							set = function(info, val)
								ShamanPower.opt.showTotemFlyouts = val
							end
						},
						hide_earth_shield_text = {
							order = 2.26,
							type = "toggle",
							name = "Hide Earth Shield Text",
							desc = "[Enable/Disable] Hide the Earth Shield target name text below the button on the totem bar",
							width = 1.3,
							get = function(info)
								return ShamanPower.opt.hideEarthShieldText
							end,
							set = function(info, val)
								ShamanPower.opt.hideEarthShieldText = val
								ShamanPower:UpdateEarthShieldButton()
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
						totem_bar_order_header = {
							order = 2.91,
							type = "description",
							name = "\n|cffffd200Totem Bar Order:|r Choose the order of totem buttons",
							fontSize = "medium",
						},
						totem_bar_order_1 = {
							order = 2.911,
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
								-- Swap if duplicate
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
							order = 2.912,
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
								-- Swap if duplicate
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
							order = 2.913,
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
								-- Swap if duplicate
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
							order = 2.914,
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
								-- Swap if duplicate
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
						cooldown_bar_order_header = {
							order = 2.92,
							type = "description",
							name = "\n|cffffd200Cooldown Bar Order:|r Choose the order of cooldown buttons",
							fontSize = "medium",
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
						},
						cooldown_bar_order_1 = {
							order = 2.921,
							type = "select",
							name = "1st",
							desc = "First cooldown button position",
							width = 0.42,
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
							values = {
								[1] = "Shield",
								[2] = "Recall",
								[3] = "Ankh",
								[4] = "NS",
								[5] = "MTT",
								[6] = "BL",
								[7] = "Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[1] or 1
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7} end
								-- Swap if duplicate
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
							order = 2.922,
							type = "select",
							name = "2nd",
							desc = "Second cooldown button position",
							width = 0.42,
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
							values = {
								[1] = "Shield",
								[2] = "Recall",
								[3] = "Ankh",
								[4] = "NS",
								[5] = "MTT",
								[6] = "BL",
								[7] = "Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[2] or 2
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7} end
								-- Swap if duplicate
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
							order = 2.923,
							type = "select",
							name = "3rd",
							desc = "Third cooldown button position",
							width = 0.42,
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
							values = {
								[1] = "Shield",
								[2] = "Recall",
								[3] = "Ankh",
								[4] = "NS",
								[5] = "MTT",
								[6] = "BL",
								[7] = "Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[3] or 3
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7} end
								-- Swap if duplicate
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
							order = 2.924,
							type = "select",
							name = "4th",
							desc = "Fourth cooldown button position",
							width = 0.42,
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
							values = {
								[1] = "Shield",
								[2] = "Recall",
								[3] = "Ankh",
								[4] = "NS",
								[5] = "MTT",
								[6] = "BL",
								[7] = "Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[4] or 4
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7} end
								-- Swap if duplicate
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
							order = 2.925,
							type = "select",
							name = "5th",
							desc = "Fifth cooldown button position",
							width = 0.42,
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
							values = {
								[1] = "Shield",
								[2] = "Recall",
								[3] = "Ankh",
								[4] = "NS",
								[5] = "MTT",
								[6] = "BL",
								[7] = "Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[5] or 5
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7} end
								-- Swap if duplicate
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
							order = 2.926,
							type = "select",
							name = "6th",
							desc = "Sixth cooldown button position",
							width = 0.42,
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
							values = {
								[1] = "Shield",
								[2] = "Recall",
								[3] = "Ankh",
								[4] = "NS",
								[5] = "MTT",
								[6] = "BL",
								[7] = "Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[6] or 6
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7} end
								-- Swap if duplicate
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
							order = 2.927,
							type = "select",
							name = "7th",
							desc = "Seventh cooldown button position",
							width = 0.42,
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
							values = {
								[1] = "Shield",
								[2] = "Recall",
								[3] = "Ankh",
								[4] = "NS",
								[5] = "MTT",
								[6] = "BL",
								[7] = "Imbue",
							},
							get = function(info)
								return ShamanPower.opt.cooldownBarOrder and ShamanPower.opt.cooldownBarOrder[7] or 7
							end,
							set = function(info, val)
								if not ShamanPower.opt.cooldownBarOrder then ShamanPower.opt.cooldownBarOrder = {1, 2, 3, 4, 5, 6, 7} end
								-- Swap if duplicate
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
						cdbar_items_header = {
							order = 2.95,
							type = "description",
							name = "\n|cffffd200Cooldown Bar Items:|r Choose which items to show",
							fontSize = "medium",
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
						},
						cdbar_show_shields = {
							order = 2.96,
							type = "toggle",
							name = "Shields",
							desc = "Show Lightning/Water Shield button on cooldown bar",
							width = 0.6,
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
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
							order = 2.97,
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
							order = 2.98,
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
							order = 2.981,
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
							order = 2.982,
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
							order = 2.983,
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
							order = 2.984,
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
						cdbar_display_header = {
							order = 2.99,
							type = "description",
							name = "\n|cffffd200Cooldown Display:|r Choose how cooldowns are shown",
							fontSize = "medium",
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
						},
						cdbar_show_progress_bars = {
							order = 2.991,
							type = "toggle",
							name = "Progress Bars",
							desc = "Show colored progress bars on the edges of cooldown buttons",
							width = 0.7,
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
							get = function(info)
								return ShamanPower.opt.cdbarShowProgressBars ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowProgressBars = val
							end
						},
						cdbar_show_color_sweep = {
							order = 2.992,
							type = "toggle",
							name = "Color Sweep",
							desc = "Show greyed-out sweep overlay as time depletes",
							width = 0.7,
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
							get = function(info)
								return ShamanPower.opt.cdbarShowColorSweep ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowColorSweep = val
							end
						},
						cdbar_show_cd_text = {
							order = 2.993,
							type = "toggle",
							name = "CD Text",
							desc = "Show cooldown time remaining as text",
							width = 0.55,
							hidden = function(info)
								return not ShamanPower.opt.showCooldownBar
							end,
							get = function(info)
								return ShamanPower.opt.cdbarShowCDText ~= false
							end,
							set = function(info, val)
								ShamanPower.opt.cdbarShowCDText = val
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
								-- Also update cooldown bar drag handle visibility
								ShamanPower:UpdateCooldownBarPosition()
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
