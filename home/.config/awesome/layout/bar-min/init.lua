-- bar taglist.
---------------
-- Copyleft © 2022 Saimoomedits



-- requirements
------------
local awful = require("awful")
local helpers = require("helpers")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local xresources = require("beautiful.xresources")
local dpi = xresources.apply_dpi


-- widgets
----------
local statuses = require("layout.bar-min.statuses")
local time = require("layout.bar-min.time")
local music = require("layout.bar-min.music")
--local search = require("layout.bar-min.search")
local tasks = require("layout.bar-min.tasklist")
local launcher = require("layout.bar-min.launcher")
local resetwave = require("layout.bar-min.resetwave")


-- connect to each screen
awful.screen.connect_for_each_screen(function(s)

local taglist = require("layout.bar-min.taglist")(s)

    -- screen height
    local screen_height = s.geometry.height


    -- status strip: resetwave drawn vertically to run down the outer (right) edge
    local wave_strip = resetwave


    -- wibar
    s.wibar_wid = awful.wibar({
        position    = "right",
        screen      = s,
        visible     = true,
        ontop       = false,
        type        = "dock",
        height      = screen_height,
        width       = dpi(64),
        bg          = beautiful.bg_color
    })

    -- set it up!
            s.wibar_wid:setup {
                {
                    wave_strip,
                    layout = wibox.layout.fixed.vertical
                },
                {
                    {
                        {
                            launcher,
                            statuses,
                            tasks,
                            spacing = dpi(12),
                            layout = wibox.layout.fixed.vertical
                        },
                        taglist,

                        {
                            --sliders,
                            music,
                            time,
                            layout = wibox.layout.fixed.vertical,
                            spacing = dpi(12)
                        },
                        layout = wibox.layout.align.vertical,
                        expand = "none"
                    },
                    widget = wibox.container.margin,
                    margins = {left = dpi(7), right = dpi(7), top = dpi(4), bottom = dpi(4)},
                    forced_width = s.wibar_wid.width - dpi(2)
                },
                layout = wibox.layout.fixed.horizontal,
                spacing = dpi(0)
            }




    -- function to remove the bar in maxmized/fullscreen apps
    ------ Stolen from javacafe01 - https://github.com/javacafe01
    -------------------------------------------------------------

    -- Reason commenting this out: Just dont make the bar always on top lol, and this often breaks fullscreen games

--     local function remove_wibar(c)
--         if c.fullscreen or c.maximized then
--             c.screen.wibar_wid.visible = false
--         else
--             c.screen.wibar_wid.visible = true
--         end
--     end

--     local function add_wibar(c)
--         if c.fullscreen or c.maximized then
--             c.screen.wibar_wid.visible = true
--         end
--     end

--     client.connect_signal("property::fullscreen", remove_wibar)

--     client.connect_signal("request::unmanage", add_wibar)

end)

-- EOF
------
