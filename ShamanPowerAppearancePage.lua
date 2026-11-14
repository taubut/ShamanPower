-- Appearance (3.0.9.1, laid out from G's review of the page): Settings > General > Appearance,
-- the page for how the bars look, by the thing being styled: Totem Bar, Cooldown Bar (new: the
-- same rows as the totem bar's, in the same order), Flyouts, Colors & Borders, Visibility.
-- Nothing leaves a right-click menu or another page for this: a setting that lives elsewhere
-- too is a twin here (its own label, text, width and order; the same saved setting through the
-- same get / set), and the original stays where it is. The rows only this page ever had keep
-- their objects (Unlock UI and the Themes tab read them by their old paths; a move records an
-- alias for the old path). Window.lua composes the tabs from the groups built here.
local SP = ShamanPower
if not (SP and SP.options) then return end
local F = SP.options.args.fluffy.args
local S = SP.options.args.settings.args
local isShaman = select(2, UnitClass("player")) == "SHAMAN"
local SHIELD, IMBUE = 1, 7   -- the cooldown items with a flyout (ShamanPowerCdItems.lua)

local function near(a, b) return math.abs((a or 0) - (b or 0)) < 0.0005 end

-- a twin: a copy of a row for this page, the same saved setting through the same get / set
local function twin(src, over)
	if type(src) ~= "table" then return nil end
	local t = {}
	for k, v in pairs(src) do t[k] = v end
	t.order = nil
	if over then for k, v in pairs(over) do t[k] = v end end
	return t
end

local function desc(text, hidden)
	return { type = "description", name = text, hidden = hidden }
end

local function note(text, hidden)
	return { type = "description", name = "|cffffa040" .. text .. "|r", hidden = hidden }
end

local function cdbarOff() return not SP.opt.showCooldownBar end

-- a theme color (Appearance > Themes' swatch for a part of a panel) as a settings row here.
-- Cancel in the picker hands back the color it opened with: an edit that started with no
-- color of its own ends with none, as the Themes tab's own swatch does, never as a saved copy
-- of the standard color.
local function ThemeColorRow(spot, role, name, text, disabled)
	local lastR, lastG, lastB, lastKeep
	local openR, openG, openB, openKeep, editing
	return {
		type = "color", name = name, desc = text, width = 1.0, disabled = disabled,
		get = function()
			local r, g, b, src = SP:ThemeDisplayColor(spot, role)
			lastR, lastG, lastB = r, g, b
			lastKeep = (src == "custom") or (SP.ThemeRoleIsSetting and SP:ThemeRoleIsSetting(spot, role)) or false
			if not lastKeep then editing = nil end
			return r, g, b
		end,
		set = function(_, r, g, b)
			if not editing then
				openR, openG, openB, openKeep, editing = lastR, lastG, lastB, lastKeep, true
			end
			if openR ~= nil and near(r, openR) and near(g, openG) and near(b, openB) then
				-- the color it opened with: the edit is off (Cancel), or nothing changed
				if openKeep then SP:SetSpotColor(spot, role, openR, openG, openB) else SP:SetSpotColor(spot, role, nil) end
				editing = nil
			else
				SP:SetSpotColor(spot, role, r, g, b)
			end
		end,
	}
end

-- a theme switch and a border thickness (Appearance > Themes has the same rows)
local function ThemeToggle(field, name, text, hidden)
	return {
		type = "toggle", name = name, desc = text .. " The same setting as on Appearance > Themes.", width = "full", hidden = hidden,
		get = function() return SP:ThemeField(field) == true end,
		set = function(_, v) SP:SetThemeField(field, v and true or nil) end,
	}
end
local function ThemeSize(field, name, what, hidden)
	return {
		type = "range", name = name, width = "full", min = 1, max = 6, step = 1, hidden = hidden,
		desc = "How thick the element-colored border is on " .. what .. ", in pixels: the square edge, or the ring round Rounded and Circle icons. 2 by default. The same setting as on Appearance > Themes.",
		get = function() return SP:ThemeField(field) or 2 end,
		set = function(_, v)
			v = math.floor((tonumber(v) or 2) + 0.5)
			if v == 2 then v = nil end
			SP:SetThemeField(field, v)
		end,
	}
end
local function bordersOn() return SP:ThemeField("borders") == true end
local function cdBordersOn() return bordersOn() and SP:ThemeField("bordersCooldown") == true end

-- ---------------------------------------------------------------------------
-- Totem Bar: Size & Spacing, Icons, Opacity, Background & Border (the panel's texture
-- and colors from Colors & Borders, as twins), Dropped Totem Indicator; Shared Resets
-- ---------------------------------------------------------------------------
do
	local tb = F.totembar_appearance
	local a = tb.args
	local tex = F.texture_section and F.texture_section.args or {}
	local col = F.color_section and F.color_section.args or {}
	-- the panel is not drawn: hidden, or a style without one (ApplySkin says which)
	local function noPanel()
		if SP.opt.hideTotemBarFrame then return true end
		if SP.GridActive and SP:GridActive() then return true end
		if SP.UsingBlizzardTotemBar and SP:UsingBlizzardTotemBar() then return true end
		if SP.DroppedActive and SP:DroppedActive() then return true end
		return false
	end
	local function panelNote()
		if SP.opt.hideTotemBarFrame then return "|cffffa040Hide Background and Border is on, so the panel's texture and colors are not shown.|r" end
		if SP.GridActive and SP:GridActive() then return "|cffffa040The Grid style has no panel, so these are not shown while it is on.|r" end
		if SP.UsingBlizzardTotemBar and SP:UsingBlizzardTotemBar() then return "|cffffa040Blizzard's Totem Bar is on. It has no ShamanPower panel, so these are not shown.|r" end
		if SP.DroppedActive and SP:DroppedActive() then return "|cffffa040Dropped Totems has no panel, so these are not shown while it is on.|r" end
		return ""
	end
	local grayed = function() return not isShaman or noPanel() end

	-- the shared border rows go to Colors & Borders (one Panel Edge Style, one Keep Icon
	-- Borders Square, one border gradient for everything they shade)
	F.borders_appearance = { type = "group", name = "Shared Border Shape", order = 6.3, args = {} }
	SP.MoveSettingsOptions({ "fluffy", "totembar_appearance" }, { "fluffy", "borders_appearance" }, {
		"frame_edge", "icon_borders_square", "outlineGradient", "outlineGradient_direction", "outlineGradient_own",
		"outlineGradient_color1", "outlineGradient_color2", "outlineGradient_fade",
	})

	a.tb_size_desc = desc("Choose the bar's direction, overall size and the space between buttons.")
	a.tb_icons_desc = desc("Changes the totem icons, their flyouts, the dropped-totem indicators and Drop All.")
	a.tb_opacity_desc = desc("Choose how visible the buttons are, then whether active buttons become fully visible.")
	a.tb_panel_desc = desc("The panel behind the buttons. Its background color changes with how many assigned totems are down.")
	a.tb_panel_note = { type = "description", name = panelNote, hidden = function() return not noPanel() end }
	a.tb_skin = twin(tex.skin, { name = "Background Texture", width = "full", disabled = grayed,
		desc = "The texture that fills the totem bar's panel, the box behind the totem buttons." })
	a.tb_edges = twin(tex.edges, { name = "Border Texture", width = "full", disabled = grayed,
		desc = "The border drawn round the totem bar's panel." })
	a.tb_color_good = twin(col.color_good, { name = "All Assigned Totems Down", width = 1.0, disabled = grayed,
		desc = "The panel's color while every totem you have assigned is down." })
	a.tb_color_partial = twin(col.color_partial, { name = "Some Assigned Totems Down", width = 1.0, disabled = grayed,
		desc = "The panel's color while some of your assigned totems are down." })
	a.tb_color_missing = twin(col.color_missing, { name = "No Assigned Totems Down", width = 1.0, disabled = grayed,
		desc = "The panel's color while none of your assigned totems are down." })
	a.tb_border_color = ThemeColorRow("tb.frame", "border", "Border Color",
		"The color of the line round the panel. The same as Border on Appearance > Themes > Totem Bar > Frame Background and Border.", grayed)
	a.tb_indicator_desc = desc("Choose where the separate dropped-totem indicator appears. This also places the Earth Shield indicator when there is one.")

	SP.OrderSettingsBands(tb, {
		{ header = "tb_size_header", name = "Size & Spacing", keys = { "tb_size_desc", "layout", "buffscale", "totemBarPadding" },
		  names = { layout = "Layout", buffscale = "Scale", totemBarPadding = "Button Spacing" } },
		{ header = "tb_icons_header", name = "Icons", keys = { "tb_icons_desc", "icon_shape", "icon_dark" } },
		{ header = "tb_opacity_header", name = "Opacity", keys = { "tb_opacity_desc", "totemBarOpacity", "totemBarFullOpacityWhenActive" },
		  names = { totemBarOpacity = "Opacity", totemBarFullOpacityWhenActive = "Fully Visible While a Totem Is Down" } },
		{ header = "tb_panel_header", name = "Background & Border", keys = { "tb_panel_desc", "hide_totem_bar_frame", "tb_panel_note",
			"tb_skin", "tb_edges", "tb_color_good", "tb_color_partial", "tb_color_missing", "tb_border_color" },
		  names = { hide_totem_bar_frame = "Hide Background and Border" } },
		{ header = "tb_indicator_header", name = "Dropped Totem Indicator", keys = { "tb_indicator_desc", "activeOverlayDirection" } },
	})
	local W = { layout = "full", buffscale = 1.0, totemBarPadding = 1.0, icon_shape = "full", icon_dark = "full", totemBarOpacity = 1.0,
		totemBarFullOpacityWhenActive = "full", hide_totem_bar_frame = "full", activeOverlayDirection = "full" }
	for k, w in pairs(W) do if a[k] then a[k].width = w end end
	if a.hide_totem_bar_frame then a.hide_totem_bar_frame.desc = "Hide the panel behind the totem buttons, its background and its border, and show the icons alone." end

	-- Shared Resets: what each button covers, above it
	local r = F.appearance_resets and F.appearance_resets.args
	if r then
		r.scale_desc.name = "These buttons also change settings outside this tab. Positions stay where they are."
		r.scale_reset.name = "Reset Shared Sizes"
		r.scale_reset.desc = "Resets both bars' scale, the Totem Assignments window's scale and the shared cooldown flyout icon size. Each item's own flyout size stays. Asks first."
		r.opacity_desc.name = "Reset Shared Opacity: both bars' opacity, their Full Opacity switches and both flyouts' opacity. Each item's own flyout opacity stays."
		r.opacity_reset.desc = r.opacity_desc.name .. " Asks first."
		r.padding_desc.name = "Reset Both Bars' Spacing: the totem bar's and the cooldown bar's Button Spacing."
		r.padding_reset.desc = r.padding_desc.name .. " Asks first."
		for _, k in ipairs({ "scale_reset", "opacity_reset", "padding_reset" }) do r[k].width = "full" end
		SP.OrderSettingsBands(F.appearance_resets, {
			{ keys = { "scale_desc", "scale_reset", "opacity_desc", "opacity_reset", "padding_desc", "padding_reset" } },
		})
	end
	-- the panel's old tabs open this one
	SP.SettingsPathAliases["fluffy/texture_section"] = { "fluffy", "totembar_appearance" }
	SP.SettingsPathAliases["fluffy/color_section"] = { "fluffy", "totembar_appearance" }
end

-- ---------------------------------------------------------------------------
-- Cooldown Bar: the same bands as the totem bar's, from the Cooldown Bar page's own rows
-- (twins: that page keeps its Bar rows), plus the panel's two colors from Appearance > Themes
-- ---------------------------------------------------------------------------
do
	local app = F.cooldownbar_appearance and F.cooldownbar_appearance.args or {}
	local cd = { type = "group", name = "Cooldown Bar", order = 1.15, args = {} }
	F.cdbar_appearance = cd
	local a = cd.args
	local function same(what) return " The same setting as " .. what .. " on the Cooldown Bar page." end
	local grayed = function() return cdbarOff() or SP.opt.hideCooldownBarFrame and true or false end
	a.cd_off_note = note("The cooldown bar is off. Its switch is beside Cooldown Bar in the sidebar.", function() return not cdbarOff() end)
	a.cd_size_desc = desc("Choose the bar's direction, overall size and the space between buttons.")
	a.cdbarLayout = twin(app.cdbarLayout, { name = "Layout", width = "full" })
	a.cooldownBarScale = twin(app.cooldownBarScale, { name = "Scale", width = 1.0 })
	a.cooldownBarPadding = twin(app.cooldownBarPadding, { name = "Button Spacing", width = 1.0 })
	a.cd_icons_desc = desc("Changes the cooldown icons and their shield and weapon imbue flyouts.")
	a.icon_shape = twin(app.icon_shape, { name = "Icon Shape", width = "full" })
	a.icon_dark = twin(app.icon_dark, { name = "Dark Icons", width = "full" })
	a.cd_opacity_desc = desc("Choose how visible the buttons are, then whether active buttons become fully visible.")
	a.cooldownBarOpacity = twin(app.cooldownBarOpacity, { name = "Opacity", width = 1.0 })
	a.cooldownBarFullOpacityWhenActive = twin(app.cooldownBarFullOpacityWhenActive, { name = "Fully Visible While Active or on Cooldown", width = "full",
		desc = "Show a button at full opacity while its buff is up or its cooldown is running, even if the opacity above is lower." .. same("Full Opacity When Active") })
	a.cd_panel_desc = desc("The panel behind the cooldown buttons. It has one background color.")
	a.hide_cooldown_bar_frame = twin(app.hide_cooldown_bar_frame, { name = "Hide Background and Border", width = "full",
		desc = "Hide the panel behind the cooldown buttons, its background and its border, and show the icons alone." .. same("Hide Background") })
	a.cd_bg_color = ThemeColorRow("cd.frame", "bg", "Background Color",
		"The panel's color. The same as Background on Appearance > Themes > Cooldown Bar > Frame Background and Border.", grayed)
	a.cd_border_color = ThemeColorRow("cd.frame", "border", "Border Color",
		"The color of the line round the panel. The same as Border on Appearance > Themes > Cooldown Bar > Frame Background and Border.", grayed)
	for _, k in ipairs({ "cdbarLayout", "cooldownBarScale", "cooldownBarPadding", "icon_shape", "cooldownBarOpacity" }) do
		if a[k] and app[k] then a[k].desc = (app[k].desc or "") .. same(app[k].name or a[k].name) end
	end
	-- Shared Resets, as on Totem Bar (the same buttons)
	local r = F.appearance_resets and F.appearance_resets.args
	if r then
		a.cd_resets_desc = desc(r.scale_desc.name)
		a.cd_scale_reset = twin(r.scale_reset)
		a.cd_reset_opacity_desc = desc(r.opacity_desc.name)
		a.cd_opacity_reset = twin(r.opacity_reset)
		a.cd_reset_padding_desc = desc(r.padding_desc.name)
		a.cd_padding_reset = twin(r.padding_reset)
	end
	SP.OrderSettingsBands(cd, {
		{ keys = { "cd_off_note" } },
		{ header = "cd_size_header", name = "Size & Spacing", keys = { "cd_size_desc", "cdbarLayout", "cooldownBarScale", "cooldownBarPadding" } },
		{ header = "cd_icons_header", name = "Icons", keys = { "cd_icons_desc", "icon_shape", "icon_dark" } },
		{ header = "cd_opacity_header", name = "Opacity", keys = { "cd_opacity_desc", "cooldownBarOpacity", "cooldownBarFullOpacityWhenActive" } },
		{ header = "cd_panel_header", name = "Background & Border", keys = { "cd_panel_desc", "hide_cooldown_bar_frame", "cd_bg_color", "cd_border_color" } },
		{ header = "cd_resets_header", name = "Shared Resets", keys = { "cd_resets_desc", "cd_scale_reset", "cd_reset_opacity_desc", "cd_opacity_reset", "cd_reset_padding_desc", "cd_padding_reset" } },
	})
end

-- ---------------------------------------------------------------------------
-- Flyouts: the totem flyouts, Compact, the shield's and the weapon imbue's flyouts (their
-- menus' Flyout rows, as twins), the shared background, the arrows, the colored borders
-- ---------------------------------------------------------------------------
do
	local fl = F.flyout_appearance
	local a = fl.args
	-- Dropped Totems set every row here aside (it has no totem flyouts); the shared rows and
	-- the cooldown bar's flyouts are still there, so those keep their own rule only
	local function noBoxes() return not (SP:FlyoutBoxMode()) end
	for _, k in ipairs({ "flyout_style", "flyout_frame_opacity", "flyout_arrows_always", "flyout_reset" }) do
		if a[k] then a[k].hidden = noBoxes end
	end
	if a.flyout_blizzard_arrows then
		a.flyout_blizzard_arrows.hidden = function()
			return not (SPCompat and SPCompat.FOREVER) or not (SPCompat and SPCompat.SecureSnippetsWork and SPCompat.SecureSnippetsWork())
		end
	end

	a.totem_fl_desc = desc("Set the direction, icon size and opacity of the totem bar's flyouts.")
	if a.compact and a.compact.args then
		a.compact.args.compact_desc = { order = 0, type = "description", name = "Compact uses this icon size instead of the normal totem flyout size." }
		if a.compact.args.compactFlyoutSize then
			a.compact.args.compactFlyoutSize.name = "Compact Flyout Icon Size"
			a.compact.args.compactFlyoutSize.width = "full"
		end
	end
	local function itemFlyoutRows(t, prefix, what)
		a[prefix .. "_desc"] = desc("Set the direction, icon size and opacity of " .. what .. ".")
		a[prefix .. "_direction"] = {
			type = "select", name = "Direction", width = "full",
			desc = "Where " .. what .. " opens while the cooldown bar is horizontal. The same setting as Flyout > Direction in its right-click menu on the Cooldown Bar page.",
			values = { below = "Below", auto = "Auto", above = "Above" }, sorting = { "below", "auto", "above" },
			hidden = function() return (SP.opt.cdbarLayout or SP.opt.layout) ~= "Horizontal" end,
			disabled = cdbarOff,
			get = function() return SP:CdItemOpt(t, "flyoutDirection") or "auto" end,
			set = function(_, v) SP:SetCdItemOpt(t, "flyoutDirection", v) end,
		}
		a[prefix .. "_size"] = {
			type = "range", name = "Icon Size", width = 1.0, min = 12, max = 56, step = 1,
			desc = "How big the icons in " .. what .. " are. 22 is the classic size. The Cooldown Bar's size also affects these icons. The same setting as Flyout > Icon Size in its right-click menu.",
			disabled = cdbarOff,
			get = function() return SP:CdItemOpt(t, "flyoutIconSize") or 22 end,
			set = function(_, v) SP:SetCdItemOpt(t, "flyoutIconSize", v) end,
		}
		a[prefix .. "_opacity"] = {
			type = "range", name = "Opacity", width = 1.0, min = 0.1, max = 1, step = 0.05, isPercent = true,
			desc = "How see-through " .. what .. " is. The same setting as Flyout > Opacity in its right-click menu.",
			disabled = cdbarOff,
			get = function() return SP:CdItemOpt(t, "flyoutOpacity") or 1 end,
			set = function(_, v) SP:SetCdItemOpt(t, "flyoutOpacity", v) end,
		}
	end
	itemFlyoutRows(SHIELD, "shield_flyout", "the shield's flyout")
	itemFlyoutRows(IMBUE, "imbue_flyout", "the weapon imbue's flyout")

	a.shared_fl_desc = desc("Shared by the totem, shield and weapon imbue flyouts.", noBoxes)
	if a.flyout_style then
		a.flyout_style.values = { icons = "Icons Only", frame = "Blizzard Background and Border" }
		if type(a.flyout_style.desc) == "string" then
			a.flyout_style.desc = a.flyout_style.desc:gsub("Icons only", "Icons Only"):gsub("Blizzard frame", "Blizzard Background and Border")
		end
	end
	a.arrows_desc = desc("These settings also change how the flyouts open.", function()
		local ba = a.flyout_blizzard_arrows
		local h1 = ba and ba.hidden and ba.hidden() or not ba
		return h1 and noBoxes()
	end)

	a.fl_borders_desc = desc("These use the colored-border settings on Colors & Borders. Cooldown flyout borders also need the cooldown bar's icon borders.")
	a.fl_borders_note = note("Turn on Element-Colored Icon Borders (Colors & Borders) to use these.", bordersOn)
	a.fl_borders_totem = ThemeToggle("bordersFlyouts", "Totem Flyout Colored Borders",
		"Gives every totem in the totem bar's flyouts the same element-colored border as the bar's icons.", function() return not bordersOn() end)
	a.fl_border_size_totem = ThemeSize("borderSizeFlyouts", "Totem Flyout Border Thickness", "the totem bar's flyouts",
		function() return not (bordersOn() and SP:ThemeField("bordersFlyouts") == true) end)
	a.fl_borders_cd_note = note("Cooldown flyout borders need Cooldown Icon Colored Borders (Colors & Borders) on.",
		function() return not bordersOn() or cdBordersOn() end)
	a.fl_borders_cd = ThemeToggle("bordersCooldownFlyouts", "Cooldown Flyout Colored Borders",
		"Gives every shield and weapon imbue in the cooldown bar's flyouts a border in the color of what it shows, like the cooldown bar's own buttons.", function() return not cdBordersOn() end)
	a.fl_border_size_cd = ThemeSize("borderSizeCooldownFlyouts", "Cooldown Flyout Border Thickness", "the cooldown bar's flyouts",
		function() return not (cdBordersOn() and SP:ThemeField("bordersCooldownFlyouts") == true) end)

	local scope = "Resets the shared flyout background, the opening rules and the normal totem flyout icon size. The shield's and the weapon imbue's own flyout settings, the directions, the opacities and the Compact size stay."
	a.flyout_reset_scope = desc(scope, noBoxes)
	if a.flyout_reset then
		a.flyout_reset.name = "Reset Flyout Look and Behavior"
		a.flyout_reset.desc = scope .. " Asks first. Positions are not changed."
		a.flyout_reset.width = "full"
	end

	SP.OrderSettingsBands(fl, {
		{ header = "totem_header", name = "Totem Flyouts", keys = { "totem_fl_desc", "totem_flyout_direction", "totem_flyout_button_size", "totemFlyoutOpacity", "compact" },
		  names = { totem_flyout_direction = "Direction", totem_flyout_button_size = "Icon Size", totemFlyoutOpacity = "Opacity" } },
		{ header = "shield_header", name = "Shield Flyout", keys = { "shield_flyout_desc", "shield_flyout_direction", "shield_flyout_size", "shield_flyout_opacity" } },
		{ header = "imbue_header", name = "Weapon Imbue Flyout", keys = { "imbue_flyout_desc", "imbue_flyout_direction", "imbue_flyout_size", "imbue_flyout_opacity" } },
		{ header = "shared_header", name = "Shared Flyout Background", keys = { "shared_fl_desc", "flyout_style", "flyout_frame_opacity" },
		  names = { flyout_style = "Flyout Background", flyout_frame_opacity = "Background and Border Opacity" } },
		{ header = "arrows_header", name = "Flyout Arrows", keys = { "arrows_desc", "flyout_blizzard_arrows", "flyout_arrows_always" } },
		{ header = "fl_borders_header", name = "Flyout Icon Borders", keys = { "fl_borders_desc", "fl_borders_note", "fl_borders_totem", "fl_border_size_totem",
			"fl_borders_cd_note", "fl_borders_cd", "fl_border_size_cd" } },
		{ header = "reset_header", name = "Reset", keys = { "flyout_reset_scope", "flyout_reset" } },
	})
	local W = { totem_flyout_direction = "full", totem_flyout_button_size = 1.0, totemFlyoutOpacity = 1.0, flyout_style = "full", flyout_frame_opacity = "full",
		flyout_blizzard_arrows = "full", flyout_arrows_always = "full" }
	for k, w in pairs(W) do if a[k] then a[k].width = w end end
end

-- ---------------------------------------------------------------------------
-- Colors & Borders: Element Colors first, Low-Mana Tint, then the shared border rows
-- ---------------------------------------------------------------------------
do
	local ec = F.element_colors_section
	if ec and ec.args then
		local a = ec.args
		a.ec_desc = desc("Choose the element colors used across ShamanPower.")
		SP.OrderSettingsBands(ec, {
			{ keys = { "ec_desc", "element_color_palette", "element_color_1", "element_color_2", "element_color_3", "element_color_4", "element_color_reset" } },
		})
		if a.element_color_palette then a.element_color_palette.width = "full" end
		for i = 1, 4 do if a["element_color_" .. i] then a["element_color_" .. i].width = 1.0 end end
		if a.element_color_reset then a.element_color_reset.width = "full" end
	end

	local bt = F.button_tints_section
	if bt and bt.args then
		bt.name = "Low-Mana Tint"
		local a = bt.args
		a.lt_desc = desc("Tints the totem and cooldown buttons when you do not have enough mana to use them.")
		if a.manaTint then a.manaTint.name = "Tint Buttons When Mana Is Too Low"; a.manaTint.width = "full" end
		if a.manaTintColor then a.manaTintColor.name = "Low-Mana Tint Color"; a.manaTintColor.width = "full" end
		SP.OrderSettingsBands(bt, { { keys = { "lt_desc", "manaTint", "manaTintColor" } } })
	end

	local b = F.borders_appearance
	local a = b.args
	a.sb_desc = desc("Panel Edge Style changes both bars' panels and ShamanPower's other panels. Keep Icon Borders Square also changes Ready Reminders.")
	if a.frame_edge then
		a.frame_edge.name = "Panel Edge Style"
		a.frame_edge.width = "full"
		a.frame_edge.desc = "Add a shadow, raised edge or thick border to the totem bar's and the cooldown bar's panels and to ShamanPower's other panels. The same setting as Frame Edge on Appearance > Themes and on the Cooldown Bar page."
		a.frame_edge.hidden = function() return SP.opt.hideTotemBarFrame and SP.opt.hideCooldownBarFrame and true or false end
	end
	a.sb_hidden_note = note("Both panels are hidden (Hide Background and Border on each bar's tab), so Panel Edge Style is not shown.",
		function() return not (SP.opt.hideTotemBarFrame and SP.opt.hideCooldownBarFrame) end)
	if a.icon_borders_square then
		a.icon_borders_square.name = "Keep Icon Borders Square"
		a.icon_borders_square.width = "full"
		a.icon_borders_square.desc = "With Rounded or Circle icons, borders (the element-colored borders, Ready Reminders' border) follow the shape. Turn this on to keep them square. One setting for every bar. The same setting as Keep Borders Square on Appearance > Themes and on the Cooldown Bar page."
		a.icon_borders_square.hidden = function()
			local t, c = SP:IconShapeOf("totem"), SP:IconShapeOf("cooldown")
			local function round(k) return k == "rounded" or k == "circle" end
			return not (round(t) or round(c))
		end
	end
	a.cb_desc = desc("Turn on colored borders, then choose their thickness and whether the cooldown bar gets them too.")
	a.cb_borders = ThemeToggle("borders", "Element-Colored Icon Borders",
		"Outlines each totem on the totem bar in its element color. Not shown with the Compact, Grid or Blizzard's Totem Bar styles.")
	a.cb_size = ThemeSize("borderSize", "Totem Icon Border Thickness", "the totem bar", function() return not bordersOn() end)
	a.cb_borders_cd = ThemeToggle("bordersCooldown", "Cooldown Icon Colored Borders",
		"Gives every button on the cooldown bar a border in the color of what it shows: shields in your Shield Colors, weapon imbues and element spells in their element color, other spells in the logo blue.",
		function() return not bordersOn() end)
	a.cb_size_cd = ThemeSize("borderSizeCooldown", "Cooldown Icon Border Thickness", "the cooldown bar", function() return not cdBordersOn() end)
	a.sg_desc = desc("Shared shading for the totem icons' borders, both bars' panel borders and ShamanPower's other panels.")
	local G = {
		outlineGradient = { "Border Gradient", 1.0 }, outlineGradient_direction = { "Border Gradient Direction", 1.0 },
		outlineGradient_own = { "Start From Each Border's Own Color", "full" }, outlineGradient_color1 = { "Border First Color", 1.0 },
		outlineGradient_color2 = { "Border Second Color", 1.0 }, outlineGradient_fade = { "Border Fade-End Opacity", "full" },
	}
	for k, v in pairs(G) do if a[k] then a[k].name, a[k].width = v[1], v[2] end end
	if a.outlineGradient_own then
		a.outlineGradient_own.desc = "On: each border starts in its own color (Earth green, Fire red...) and shades into the second color. Off: every one starts in the first color."
	end
	if a.outlineGradient_fade then
		a.outlineGradient_fade.desc = "How much of the color is left at the faded end of the border: 0% fades right into the game world."
	end
	-- Cooldown Numbers (3.0.9.1, A49): the colors the number a cooldown counts down with can take, and the three bars' switches
	a.cc_desc = desc("The number a cooldown counts down with changes color as it runs: the first color while more than half is left, the"
		.. " second from the half mark down, the third under a quarter. Every cooldown, short or long, goes through all three. Each bar has its own switch, here and on its page.")
	local presetValues, presetOrder = {}, {}
	for _, pr in ipairs(SP.COUNTDOWN_PRESETS or {}) do presetValues[pr[1]] = pr[2]; presetOrder[#presetOrder + 1] = pr[1] end
	a.cc_preset = { type = "select", name = "Colors", width = "full", values = presetValues, sorting = presetOrder,
		desc = "ShamanPower: red, yellow, green. White / Yellow / Red. One Color the Whole Time: the Totem Bar's Cooldown Text Color, start"
			.. " to end. Custom: the three swatches below (editing a swatch makes the colors Custom).",
		get = function() return SP:CountdownPreset() end, set = function(_, v) SP:SetCountdownPreset(v) end }
	local function swatch(n, label, width)
		return { type = "color", name = label, width = width or 1.0,
			hidden = function() return n > 1 and SP:CountdownSolid() end,
			get = function() return SP:CountdownColorN(n) end, set = function(_, r, g, bb) SP:SetCountdownColor(n, r, g, bb) end }
	end
	a.cc_color1 = swatch(1, "More Than Half Left (the Totem Bar's Cooldown Text Color)", "full")
	a.cc_color2 = swatch(2, "Under Half Left")
	a.cc_color3 = swatch(3, "Almost Ready (Under a Quarter Left)")
	local function ccSwitch(key, label, descText)
		return { type = "toggle", name = label, width = 1.0, desc = descText,
			get = function() return SP.opt[key] == true end,
			set = function(_, v)
				if v then SP.opt[key] = true else SP.opt[key] = nil end
				SP:CountdownChanged()
			end }
	end
	a.cc_totem = ccSwitch("totemBarCountdownColors", "Totem Bar", "A totem's cooldown number on its button (the same switch as Totem Bar > Duration Bars > Color the Cooldown Numbers).")
	a.cc_cdbar = ccSwitch("cdbarCountdownColors", "Cooldown Bar", "A cooldown's number on the cooldown bar (the same switch as Cooldown Bar > Color the Cooldown Numbers). Only a number ShamanPower draws.")
	a.cc_ready = ccSwitch("readyCountdownColors", "Ready Reminders", "The cooldown number on a Ready Reminder's icon, Combined Shocks too (the same switch as the Ready Reminders page's).")
	-- Buff Timers (the owner, 2026-10-17): the same shape for a time left: a buff's, a shield's, an imbue's, a totem's
	a.bt_desc = desc("The time left on a buff, a shield, an imbue or a totem changes color as it runs out: the first color while more than half"
		.. " is left, the second from the half mark down, the third under a quarter. Every buff, short or long, goes through all three. Each bar has its own switch, here and on its page.")
	a.bt_preset = { type = "select", name = "Colors", width = "full", values = presetValues, sorting = presetOrder,
		desc = "ShamanPower: red, yellow, green. White / Yellow / Red. One Color the Whole Time: the first swatch, start to end."
			.. " Custom: the three swatches below (editing a swatch makes the colors Custom).",
		get = function() return SP:CountdownPreset("buff") end, set = function(_, v) SP:SetCountdownPreset(v, "buff") end }
	local function bswatch(n, label, width)
		return { type = "color", name = label, width = width or 1.0,
			hidden = function() return n > 1 and SP:CountdownSolid("buff") end,
			get = function() return SP:CountdownColorN(n, "buff") end, set = function(_, r, g, bb) SP:SetCountdownColor(n, r, g, bb, "buff") end }
	end
	a.bt_color1 = bswatch(1, "More Than Half Left", "full")
	a.bt_color2 = bswatch(2, "Under Half Left")
	a.bt_color3 = bswatch(3, "Almost Gone (Under a Quarter Left)")
	a.bt_totem = ccSwitch("totemBarBuffTimerColors", "Totem Bar", "A totem's time left on its button (the same switch as Totem Bar > Duration Bars > Color the Time Left).")
	a.bt_cdbar = ccSwitch("cdbarBuffTimerColors", "Cooldown Bar", "The shield's and the imbue's time left on the cooldown bar (the same switch as Cooldown Bar > Color the Shield and Imbue Timers).")
	a.bt_ready = ccSwitch("readyBuffTimerColors", "Ready Reminders", "A buff's time left on its Ready Reminder (the same switch as Ready Reminders > Color the Buff Timers).")
	SP.OrderSettingsBands(b, {
		{ keys = { "sb_desc", "frame_edge", "sb_hidden_note", "icon_borders_square" } },
		{ header = "cb_header", name = "Colored Icon Borders", keys = { "cb_desc", "cb_borders", "cb_size", "cb_borders_cd", "cb_size_cd" } },
		{ header = "sg_header", name = "Shared Border Shading", keys = { "sg_desc", "outlineGradient", "outlineGradient_direction", "outlineGradient_own",
			"outlineGradient_color1", "outlineGradient_color2", "outlineGradient_fade" } },
		{ header = "cc_header", name = "Cooldown Numbers", keys = { "cc_desc", "cc_preset", "cc_color1", "cc_color2", "cc_color3", "cc_totem", "cc_cdbar", "cc_ready" } },
		{ header = "bt_header", name = "Buff Timers", keys = { "bt_desc", "bt_preset", "bt_color1", "bt_color2", "bt_color3", "bt_totem", "bt_cdbar", "bt_ready" } },
	})
end

-- ---------------------------------------------------------------------------
-- Visibility: each bar's auto-hide, Out Of The Way (with its shared faded opacity and the
-- displays it covers), Button Labels (the keybind text rows from General > Keybinds, as twins)
-- ---------------------------------------------------------------------------
do
	local v = S.settings_visibility
	if v and v.args then
		local a = v.args
		a.tb_hide_desc = desc("Choose when the totem bar hides or fades. Each bar has its own rules.")
		a.cd_hide_desc = desc("Choose when the cooldown bar hides or fades.")
		local target = "Show the bar outside combat while you target anything you can attack, including neutral creatures."
		if a.showWithTarget then a.showWithTarget.desc = target; a.showWithTarget.width = "full" end
		if a.cdbarShowWithTarget then a.cdbarShowWithTarget.desc = target; a.cdbarShowWithTarget.width = "full" end
		SP.OrderSettingsBands(v, {
			{ header = "totem_bar_header", name = "Totem Bar Auto-Hide", keys = {
				"tb_hide_desc", "hideOutOfCombat", "hideWhenNoTotems", "fadeInsteadOfHide", "fadeOpacity", "fadeSmooth", "showWithTarget",
			}, names = { hideWhenNoTotems = "Hide When No Totems Are Down", showWithTarget = "Show When I Target an Enemy" } },
			{ header = "cdbar_header", name = "Cooldown Bar Auto-Hide", keys = {
				"cd_hide_desc", "cdbarHideOutOfCombat", "cdbarFadeInsteadOfHide", "cdbarFadeOpacity", "cdbarFadeSmooth", "cdbarShowWithTarget",
			}, names = { cdbarShowWithTarget = "Show When I Target an Enemy" } },
		})
	end

	local t = S.settings_town
	if t and t.args then
		local a = t.args
		a.town_desc = desc("Hide or fade the displays below outside a fight, while you have no target you can attack.")
		a.town_fade_opacity = {
			type = "range", name = "Shared Faded Opacity", width = "full", min = 0, max = 0.9, step = 0.01, isPercent = true,
			desc = "The same value as Totem Bar Auto-Hide's Faded Opacity. It also sets how faint every display faded by Out Of The Way is.",
			hidden = function() return SP.opt.hideInTown ~= true or (SP.opt.townHow or "hide") ~= "fade" end,
			get = function() return SP.opt.fadeOpacity or 0.25 end,
			set = function(_, val)
				SP.opt.fadeOpacity = val
				if SP.UpdateTotemBarVisibility then SP:UpdateTotemBarVisibility(true) end
				if SP.TownRefresh then SP:TownRefresh(true) end
			end,
		}
		if a.townWhich then a.townWhich.name = "Choose which displays follow Out Of The Way. Turn off a display here to keep using its own show and hide settings." end
		if a.townHow then a.townHow.name = "Hide or Fade"; a.townHow.width = "full" end
		if a.townWhere then a.townWhere.width = "full" end
		if a.hideInTown then a.hideInTown.width = "full" end
		if a.townMod_tb then a.townMod_tb.name = "Totem Bar and Its Flyouts" end
		SP.OrderSettingsBands(t, {
			{ keys = { "town_desc", "hideInTown", "townWhere", "townHow", "town_fade_opacity" } },
			{ header = "town_which_header", name = "Displays to Hide or Fade", keys = { "townWhich", "townMod_tb", "townMod_cd", "townMod_lb", "townMod_ctl",
				"townMod_rr", "townMod_sc", "townMod_ea", "townMod_es", "townMod_pb" } },
		})
	end

	local vs = F.visibility_section
	if vs and vs.args then
		vs.name = "Button Labels"
		local a = vs.args
		a.visibility_desc = nil   -- ("Show or hide backgrounds, labels and drag handles": those rows live elsewhere now)
		a.bl_desc = desc("Choose which text appears on the buttons. The keys themselves are set on General > Keybinds and in Keybind Mode.")
		local kb = S.settings_keybinds and S.settings_keybinds.args or {}
		a.bl_show_keybinds = twin(kb.show_button_keybinds, { width = "full",
			desc = "Show the key bound to each button in its top-right corner. The same setting as on General > Keybinds." })
		a.bl_keybind_source = twin(kb.keybind_source, { width = "full" })
		if a.bl_keybind_source then a.bl_keybind_source.desc = (a.bl_keybind_source.desc or "") .. " The same setting as on General > Keybinds." end
		if a.hide_earth_shield_text then a.hide_earth_shield_text.name = "Hide Earth Shield Target Name"; a.hide_earth_shield_text.width = "full" end
		SP.OrderSettingsBands(vs, {
			{ keys = { "bl_desc", "bl_show_keybinds", "bl_keybind_source", "hide_earth_shield_text" } },
		})
	end
end
