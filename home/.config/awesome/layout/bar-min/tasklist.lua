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
local rubato = require("mods.rubato")

-- variables
------------

-- task height based on client state
local function task_height(c)
    if c.active then return dpi(45) end
    if c.minimized then return dpi(30) end
    return dpi(35)
end

-- buttons for the tasklist
local tasklist_buttons = gears.table.join(
                 awful.button({ }, 1, function (c)
                                          if c == client.focus then
                                              c.minimized = true
                                          else
                                              c:emit_signal(
                                                  "request::activate",
                                                  "tasklist",
                                                  {raise = true}
                                              )
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
                                      end))



-- widgets
----------

-- the tasklist widget itself
local tasklist_widget = awful.widget.tasklist({
    screen = awful.screen.focused(),
    filter = awful.widget.tasklist.filter.currenttags,
    buttons = tasklist_buttons,
    style = {
        font = beautiful.font_var,
        bg_normal = beautiful.bg_frost_2,
        bg_focus = beautiful.accent_transparent,
        bg_minimize = beautiful.bg_transparent,
        shape = helpers.rrect(beautiful.rounded - 2)
    },
    layout = {
        layout = wibox.layout.fixed.vertical,
        spacing = dpi(5)
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
                        bg = beautiful.fg_color,
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
        shape_border_width = dpi(1),
        shape_border_color = beautiful.fg_color .. "14",

        update_callback = function(self, c, _, __)
            -- Removed collectgarbage("collect") as it causes severe performance issues/stuttering

            if c.active then
                self:get_children_by_id("pointer")[1].bg = beautiful.fg_color
            elseif c.minimized then
                self:get_children_by_id("pointer")[1].bg = beautiful.fg_color .. "1A"
            else
                self:get_children_by_id("pointer")[1].bg = beautiful.bg_frost_2
            end

            -- glide to the new height instead of snapping
            local target = task_height(c)
            if self.anim then
                if self.anim.target ~= target then
                    self.anim.target = target
                end
            else
                self.forced_height = target
            end
        end,

        create_callback = function(self, c, index, objects) --luacheck: no unused args
            -- apply state immediately so heights are correct before any animation runs
            local h = task_height(c)
            self.forced_height = h

            -- per-task height animation
            self.anim = rubato.timed{
                pos = h,
                target = h, -- explicitly set target on creation to prevent drop to 0
                rate = 60,
                intro = 0.15,
                duration = 0.3,
                easing = rubato.quadratic,
                awestore_compat = true,
                rapid_set = true,
                subscribed = function(pos)
                    -- filter out NaN/negatives
                    if pos and pos == pos and pos > 0 then
                        self.forced_height = math.max(dpi(15), math.min(pos, dpi(50)))
                    end
                end
            }

            -- BLING: Toggle the popup on hover and disable it off hover
            local timed_show = gears.timer {
                timeout   = 1,
                call_now  = false,
                autostart = false,
                callback  = function()
                    awesome.emit_signal("bling::task_preview::visibility", s, true, c)
                end
            }
            self:connect_signal('mouse::enter', function()
                timed_show:start()
            end)
            self:connect_signal('mouse::leave', function()
                timed_show:stop()
                awesome.emit_signal("bling::task_preview::visibility", s, false, c)
            end)
        end,
    },
})


-- finalize
-----------
return tasklist_widget


-- eof
------