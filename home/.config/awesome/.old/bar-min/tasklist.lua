-- minimal tasklist
-------------------
-- Copyleft © 2022 Saimoomedits

-- requirements
---------------
local awful = require("awful")
local helpers = require("helpers")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local dpi = beautiful.xresources.apply_dpi

-- variables
------------

-- buttons for the tasklist
local tasklist_buttons = gears.table.join(
    awful.button({ }, 1, function (c)
        if c == client.focus then
            c.minimized = true
        else
            c:emit_signal("request::activate", "tasklist", {raise = true})
        end
    end),
    awful.button({ }, 3, function(c)
        c:kill()
    end),
    awful.button({ }, 4, function ()
        awful.client.focus.byidx(1)
    end),
    awful.button({ }, 5, function ()
        awful.client.focus.byidx(-1)
    end)
)

-- Safe theme fallbacks
local font_var = beautiful.font_var or beautiful.font
local bg_3 = beautiful.bg_3 or "#222222"
local bg_2 = beautiful.bg_2 or "#111111"
local fg_color = beautiful.fg_color or "#FFFFFF"
local rounded = beautiful.rounded or 4

-- widgets
----------

-- the tasklist widget itself
local tasklist_widget = awful.widget.tasklist({
    screen = awful.screen.focused(),
    filter = awful.widget.tasklist.filter.currenttags,
    buttons = tasklist_buttons,
    style = {
        font = font_var,
        bg_normal = bg_3,
        bg_focus = fg_color .. "26",
        bg_minimize = bg_2,
        shape = helpers.rrect(rounded - 2)
    },
    layout = {
        layout = wibox.layout.fixed.horizontal,
    },
    widget_template = {
        {
            {
                {
                    awful.widget.clienticon,
                    forced_height = dpi(15),
                    forced_width = dpi(15),
                    halign = "center",
                    valign = "center",
                    widget = wibox.container.place,
                },
                margins = dpi(9),
                widget = wibox.container.margin,
            },
            {
                nil,
                nil,
                {
                    nil,
                    {
                        widget = wibox.container.background,
                        id = "pointer",
                        bg = fg_color,
                        shape = gears.shape.rounded_bar,
                        forced_height = dpi(2),
                        forced_width = dpi(20)
                    },
                    expand = "none",
                    layout = wibox.layout.align.horizontal
                },
                layout = wibox.layout.align.vertical
            },
            layout = wibox.layout.stack,
        },
        forced_width = dpi(45),
        id = "background_role",
        widget = wibox.container.background,

        update_callback = function(self, c, _, __)
            -- REMOVED: collectgarbage("collect") -- This was causing massive stutter!

            local pointer = self:get_children_by_id("pointer")[1]
            if not pointer then return end -- Safety check

            if c.active then
                pointer.bg = fg_color
            elseif c.minimized then
                pointer.bg = fg_color .. "1A"
            else
                pointer.bg = bg_3
            end
        end,
        
        create_callback = function(self, c, index, objects) --luacheck: no unused args
            -- BLING: Toggle the popup on hover and disable it off hover
            -- Wrapped in pcall so if bling breaks on Wayland, the tasklist survives
            local s = c.screen
            local timed_show = gears.timer {
                timeout   = 1,
                call_now  = false,
                autostart = false,
                callback  = function()
                    pcall(function() awesome.emit_signal("bling::task_preview::visibility", s, true, c) end)
                end
            }
            
            self:connect_signal('mouse::enter', function()
                timed_show:start()
            end)
            
            self:connect_signal('mouse::leave', function()
                timed_show:stop()
                pcall(function() awesome.emit_signal("bling::task_preview::visibility", s, false, c) end)
            end)
        end,
    },
})

-- finalize
-----------
return tasklist_widget

-- eof
------