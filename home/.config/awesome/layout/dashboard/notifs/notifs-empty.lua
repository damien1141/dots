local helpers = require("helpers")
local awful = require("awful")
local beautiful = require("beautiful")
local dpi = beautiful.xresources.apply_dpi
local wibox = require("wibox")

return wibox.widget {
    nil,
    {
        nil,
        {
            {
                widget = wibox.widget.textbox,
                markup = helpers.colorize_text(" ", (beautiful.fg_color .. "33")),
                font = beautiful.font_var .. "40",
                valign = "center",
                align = "center"
            },
            {
                widget = wibox.widget.textbox,
                markup = helpers.colorize_text("此处空空如也", (beautiful.fg_color .. "33")),
                font = beautiful.font_var .. "14",
                valign = "center",
                align = "center"
            },
            layout = wibox.layout.fixed.vertical,
            spacing = dpi(15)
        },
        layout = wibox.layout.align.horizontal,
        expand = "none"
    },
    layout = wibox.layout.align.vertical,
    expand = "none",
}