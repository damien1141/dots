-- launcher icon
----------------
-- Copyleft © 2022 Saimoomedits


-- requirements
---------------
local awful = require("awful")
local helpers = require("helpers")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local xresources = require("beautiful.xresources")
local dpi = xresources.apply_dpi


-- widgets
----------

-- icon (Material Icons Round: apps)
local icon = wibox.widget {
    markup = colorizeText("", "#8AB4F8"),
    font = beautiful.icon_var .. "18",
    align = "center",
    valign = "center",
    forced_width = dpi(34),
    widget = wibox.widget.textbox
}

-- active dot shown while the app drawer is open
local indicator = wibox.widget{
    widget = wibox.container.background,
    shape = gears.shape.circle,
    bg = beautiful.accent or "#8AB4F8",
    forced_width = dpi(5),
    forced_height = dpi(5),
    visible = false
}
awesome.connect_signal("bling::app_launcher::visibility", function(val)
    indicator.visible = val or false
end)



-- make it more cool!
-- forced square: same footprint as the bar's content width
local kaka = require("helpers.widgets.create_button")(
    {
        {
            {
                icon,
                widget = wibox.container.place
            },
            {
                nil, nil, indicator,
                layout = wibox.layout.align.vertical
            },
            layout = wibox.layout.stack
        },
        margins = dpi(11),
        widget = wibox.container.margin,
        forced_width = dpi(48),
        forced_height = dpi(48)
    },
  beautiful.bg_frost_2,
  beautiful.fg_color .. "33",
  dpi(0),
  dpi(1),
  (beautiful.fg_color or "#ffffff") .. "1A",
  helpers.rrect(beautiful.rounded - 2)
)

kaka:connect_signal(
    "button::press",
    function()
        app_launcher:toggle()
end)

return kaka
