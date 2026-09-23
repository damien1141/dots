-- Simple music widget (minimal: transport controls only)
---------------------------------------------------------
-- Copyleft © 2022 Saimoomedits


-- requirements
---------------
local awful     = require("awful")
local helpers   = require("helpers")
local gears     = require("gears")
local wibox     = require("wibox")
local beautiful = require("beautiful")
local dpi       = beautiful.xresources.apply_dpi



-- widgets
----------

-- toggle button
local toggle_button = wibox.widget{
    widget  = wibox.widget.textbox,
    markup  = helpers.colorize_text("", beautiful.fg_color),
    font    = beautiful.icon_var .. "15",
    align   = "center",
    valign  = "center",
    forced_width = dpi(30)
}

-- skip to previous button (dimmer: secondary control)
local prev_button = wibox.widget{
    widget  = wibox.widget.textbox,
    markup  = helpers.colorize_text("", (beautiful.fg_color or "#ffffff") .. "A6"),
    font    = beautiful.icon_var .. "15",
    align   = "center",
    valign  = "center",
    forced_width = dpi(30)
}

-- skip song button (dimmer: secondary control)
local skip_button = wibox.widget{
    widget  = wibox.widget.textbox,
    markup  = helpers.colorize_text("", (beautiful.fg_color or "#ffffff") .. "A6"),
    font    = beautiful.icon_var .. "15",
    align   = "center",
    valign  = "center",
    forced_width = dpi(30)
}




-- update widget's info.
-------------------------

-- playerctl module - bling
local playerctl = require("mods.bling").signal.playerctl.lib()

local toggle_command = function() playerctl:play_pause() end  -- toggle command
local prev_command = function() playerctl:previous() end  -- skip to previous command
local skip_command = function() playerctl:next() end  -- skip song command


-- press functions/buttons
toggle_button:buttons(gears.table.join(
    awful.button({}, 1, function() toggle_command() end)))

prev_button:buttons(gears.table.join(
    awful.button({}, 1, function() prev_command() end)))

skip_button:buttons(gears.table.join(
    awful.button({}, 1, function() skip_command() end)))


-- update toggle button status
playerctl:connect_signal("playback_status", function(_, playing, __)
    if playing then
        -- accent glow while something is playing
        toggle_button.markup = helpers.colorize_text("", beautiful.accent or "#8AB4F8")
    else
        toggle_button.markup = helpers.colorize_text("", beautiful.fg_color)
    end
end)



-- finalize
-----------
return wibox.widget {
    prev_button,
    toggle_button,
    skip_button,
    layout = wibox.layout.fixed.vertical,
    spacing = dpi(8)
}


-- eof
------
