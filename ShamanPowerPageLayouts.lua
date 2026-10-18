-- Page layouts from the 3.0.9.1 settings pass: General > Main, Totem Bar > Bar, Totem Bar > Duration Bars and
-- General > Reset. Every row stays; the bands, the order and some wording change. The Appearance pages are laid
-- out the same way in ShamanPowerAppearancePage.lua.
local SP = ShamanPower
if not (SP and SP.options) then return end
local S = SP.options.args.settings.args
local F = SP.options.args.fluffy.args
local B = SP.options.args.buttons.args

local function twin(src, over)
	if type(src) ~= "table" then return nil end
	local t = {}
	for k, v in pairs(src) do t[k] = v end
	t.order = nil
	if over then for k, v in pairs(over) do t[k] = v end end
	return t
end
local function desc(text, hidden) return { type = "description", name = text, hidden = hidden } end

-- General > Main: the everyday switches first, the help card short, the codes named by purpose
do
	local m = S.settings_show
	local a = m and m.args
	if a then
		if a.community and a.community.args and a.community.args.about then
			a.community.args.about.name = "|cff5865F2Join the ShamanPower Discord|r for help, bug reports, ideas and early builds."
		end
		if a.support_code then a.support_code.name = "Support Code"; a.support_code.width = "full" end
		if a.share_setup then a.share_setup.name = "Feature Use Code"; a.share_setup.width = "full" end
		a.codes_support_desc = desc("What the developer needs to help you: your settings and versions, nothing personal.")
		a.codes_use_desc = desc("Which features you use, so the developer knows what matters. Nothing personal.")
		for _, k in ipairs({ "showparty", "showsingle", "showminimapicon", "showtooltips" }) do if a[k] then a[k].width = 1.0 end end
		-- (the bands themselves: Window.lua orders this page when the settings window loads)
	end
end

-- Totem Bar > Bar: the icon rows stay exactly as they are; the bottom band becomes Position & Size, the Move
-- button first and a Bar Size slider under it (the same setting as Scale on Appearance > Totem Bar, which stays)
do
	local bar = B.auto_button
	local a = bar and bar.args
	local scale = F.totembar_appearance and F.totembar_appearance.args.buffscale
	if a and scale then
		a.tb_bar_size = twin(scale, { name = "Bar Size", width = 1.0,
			desc = "How big the totem bar is. The same as Scale on Appearance > Totem Bar." })
		-- (3.0.9.2, the owner: room for the glows) the space between its buttons: Button Spacing on Appearance > Totem Bar
		a.tb_bar_spacing = { type = "range", width = 1.0, name = "Space Between Icons", min = 0, max = 20, step = 1,
			desc = "The space between the totem bar's buttons, in pixels, so glows have room. The same as Button Spacing on Appearance > Totem Bar.",
			get = function() return SP.opt.totemBarPadding or 2 end,
			set = function(_, v) SP.opt.totemBarPadding = v; SP:UpdateRoster() end }
		SP.OrderSettingsBands(bar, {
			-- the pictures first, the switches under them (the owner, 2026-10-17: every icon page)
			{ header = "buttons_header", name = "Buttons", keys = { "tb_buttons", "totembar_hide_unlearned" } },
			{ header = "flyouts_header", name = "Totems in the Flyouts", keys = { "tb_totems", "show_totem_flyouts", "tb_flyouts_note" } },
			{ keys = { "auto_enable" } },
			{ header = "position_header", name = "Position & Size", keys = { "unlock_totem_bar", "tb_bar_size", "tb_bar_spacing" },
				names = { unlock_totem_bar = "Move the Totem Bar" } },
		})
	end
end

-- Totem Bar > Duration Bars in three bands: Totem Duration, Cooldown, Pulse Timer
do
	local d = F.totembar_duration_section
	local a = d and d.args
	if a then
		if a.duration_desc then a.duration_desc.name = "The bar on each totem button that runs down as the totem's time runs out." end
		a.cd_desc = desc("The sweep and the number while a totem is on cooldown.")
		a.pulse_desc = desc("The bar and the flash for totems that pulse (Tremor, Healing Stream...).")
		SP.OrderSettingsBands(d, {
			{ header = "td_header", name = "Totem Duration", keys = { "duration_desc", "duration_bar_position", "duration_bar_height",
				"duration_bar_opacity", "duration_bar_background", "barGradient", "barGradient_direction", "barGradient_own",
				"barGradient_color1", "barGradient_color2", "barGradient_fade", "barGradient_dir_duration", "show_duration_text", "duration_icon_side",
				"duration_text_size", "totem_timer_colors" } },
			{ header = "cd_header", name = "Cooldown", keys = { "cd_desc", "show_totem_cooldowns", "totem_cooldown_sweep", "totem_cooldown_edge",
				"totem_cooldown_text", "totem_cooldown_numbers_note", "totem_cooldown_numbers_button", "totem_cooldown_text_color",
				"totem_countdown_colors" } },
			{ header = "pulse_header", name = "Pulse Timer", keys = { "pulse_desc", "pulse_bar_position", "pulse_icon_sweep", "pulse_bar_color", "pulse_flash_opacity",
				"pulse_flash_color", "pulse_flash_shape", "pulse_time_display", "barGradient_dir_pulse", "pulse_totems_note" } },
		})
	end
end

-- General > Reset: Find My Bars first, then Reset, then Setup
do
	local g = S.settings_frames
	local a = g and g.args
	if a then
		a.find_desc = desc("Can't see a bar? Three checks, in order.\n1. Its switch: beside its name in the sidebar on the left.\n"
			.. "2. Its rules: Appearance > Visibility (Hide Out of Combat, Out Of The Way).\n"
			.. "3. Center Both Bars, then Unlock UI to put it where you want.")
		a.find_unlock = { type = "execute", name = "Unlock UI", width = 1.0,
			desc = "Every bar and module under a box you can drag. Press Done when they sit right.",
			func = function() if SP.SetMasterUnlock then SP:SetMasterUnlock(true) end end }
		if a.reset_center then a.reset_center.width = 1.0 end
		a.reset_defaults_desc = desc("The totem bar's size, texture, border and layout, the assignments window's size, and both bars' positions. Asks first.")
		local function noBackup() return not (SP.db and SP.db.global and SP.db.global.setupBackups and SP.db.global.setupBackups[1]) end
		a.restore_backup = { type = "execute", name = "Restore My Previous Setup", width = "full", hidden = noBackup,
			desc = "Your setup from before a layout was applied or a code imported, back as a new profile. This one stays.",
			func = function() if SP.RestoreSetupBackup then SP:RestoreSetupBackup(1) end end }
		a.restore_desc = { type = "description", hidden = noBackup, name = function()
			local b = SP.db.global.setupBackups and SP.db.global.setupBackups[1]
			return b and ("Backed up " .. b.date .. " (" .. b.reason .. "). Comes back as a new profile; this one stays.") or ""
		end }
		a.setup_desc = desc("Opens the setup tour again. It changes nothing until you pick something in it.")
		if a.reset_defaults then a.reset_defaults.width = "full" end
		if a.runSetup then a.runSetup.width = "full" end
		SP.OrderSettingsBands(g, {
			{ header = "find_header", name = "Find My Bars", keys = { "find_desc", "reset_center", "find_unlock" } },
			{ header = "reset_header", name = "Reset", keys = { "reset_defaults", "reset_defaults_desc", "restore_backup", "restore_desc" } },
			{ header = "setup_header", name = "Setup", keys = { "runSetup", "setup_desc" } },
		})
	end
end
