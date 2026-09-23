-- profile widget
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Copyleft © 2022 Saimoomedits

-- requirements
-- ~~~~~~~~~~~~
local beautiful = require("beautiful")
local dpi = beautiful.xresources.apply_dpi
local helpers = require("helpers")
local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")

-- state tracking
-- ~~~~~~~~~~~~~~
local is_inhibiting = false

-- mask overlay
local overlayed = wibox.widget({
	{
		bg = beautiful.bg_frost_2 ,
		forced_height = dpi(160),
		forced_width = dpi(160),
		widget = wibox.container.background,
	},
	direction = "east",
	widget = wibox.container.rotate,
})

-- image (THE SQUARE - keep this at 100x100)
local profile_image = wibox.widget {
	{
		image = beautiful.images.profile,
		shape = helpers.rrect(beautiful.rounded),
		widget = wibox.widget.imagebox
	},
	widget = wibox.container.background,
	forced_width = dpi(100),
	forced_height = dpi(100),
	shape = helpers.rrect(beautiful.rounded),
	shape_border_color = (beautiful.colors and beautiful.colors.accent) or beautiful.accent,
	shape_border_width = 0,
}

-- username
local username = wibox.widget{
	widget = wibox.widget.textbox,
	markup = helpers.colorize_text(user_likes.username, beautiful.fg_color),
	font = beautiful.font_var .. "Medium 13",
	align = "left",
	valign = "center"
}

-- description/host
local desc = wibox.widget{
	widget = wibox.widget.textbox,
	markup = helpers.colorize_text(user_likes.userdesc, beautiful.fg_color .. "99"),
	font = beautiful.font_var .. "11",
	align = "left",
	valign = "center"
}

-- main container (includes both image AND text)
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local profile_widget = wibox.widget {
	{
		{
			profile_image,
			overlayed,
			layout = wibox.layout.stack
		},
		{
			{
				{
					widget = wibox.widget.textbox,
					font = beautiful.font_var .. "11",
					align = "left",
					valign = "center"
				},
				nil,
				{
					username,
					desc,
					layout = wibox.layout.fixed.vertical,
					spacing = dpi(2)
				},
				layout = wibox.layout.align.vertical,
				expand = "none"
			},
			widget = wibox.container.margin,
			margins = dpi(16)
		},
		layout = wibox.layout.stack,
	},
	widget = wibox.container.background,
	shape = helpers.rrect(dpi(beautiful.rounded)),
	-- REMOVE forced_width and forced_height from here!
	-- Let it expand naturally to fit both image and text
}

-- Toggle inhibit state and border
-- -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local function toggle_inhibit()
    is_inhibiting = not is_inhibiting
    
    -- Update shape border width
    profile_image.shape_border_width = is_inhibiting and dpi(4) or 0

    -- Keep screen on logic
    if is_inhibiting then
        awful.spawn.with_shell("xset s off && xset -dpms")
    else
        awful.spawn.with_shell("xset s on && xset +dpms")
    end
end

-- add click handler to the main container
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
profile_widget:buttons(gears.table.join(
	awful.button({}, 1, function()
		toggle_inhibit()
	end)
))

-- finalize
return profile_widget