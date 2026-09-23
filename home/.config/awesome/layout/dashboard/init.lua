local awful = require("awful")
local beautiful = require("beautiful")
local dpi = beautiful.xresources.apply_dpi
local helpers = require("helpers")
local wibox = require("wibox")
local gears = require("gears")
local notifs = require("layout.dashboard.notifs.build")
local ram = require("layout.dashboard.resour.ram")
local cpu = require("layout.dashboard.resour.cpu")
local hdd = require("layout.dashboard.resour.hdd")
local todo = require("layout.dashboard.todo")

awful.screen.connect_for_each_screen(function(s)
    local screen_height = s.geometry.height
    dashbaord_d = wibox({
        type = "dock",
        screen = s,
        width = dpi(430),
        height = screen_height - beautiful.useless_gap * 4,
        shape = helpers.rrect(beautiful.rounded),
        bg = beautiful.bg_transparent,
        shape_border_width = dpi(1),
        shape_border_color = beautiful.fg_color .. "14",
        ontop = true,
        visible = false
    })

    dd_toggle = function()
        if control_hide then control_hide() end
        if not dashbaord_d.visible then
            dashbaord_d.visible = true
            awesome.emit_signal("dashboard::visible", true)
        else
            dashbaord_d.visible = false
            awesome.emit_signal("dashboard::visible", false)
        end
    end

    awful.placement.top_right(dashbaord_d, {honor_workarea = true, margins = beautiful.useless_gap * 2})

    dashbaord_d:setup {
        -- Top: Status Widgets
        {
            {
                ram,
                cpu,
                hdd,
                spacing = dpi(30),
                layout = wibox.layout.fixed.horizontal,
            },
            margins = dpi(25),
            widget = wibox.container.margin
        },
        -- Bottom: Notifs & Todo (50/50 Split)
        {
            {
                todo,
                notifs,
                spacing = dpi(25),
                layout = wibox.layout.flex.vertical
            },
            margins = { left = dpi(25), right = dpi(25), bottom = dpi(25) },
            widget = wibox.container.margin
        },
        layout = wibox.layout.align.vertical
    }
end)