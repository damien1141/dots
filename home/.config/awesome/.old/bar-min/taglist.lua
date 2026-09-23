-- bar taglist.
---------------
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

-- variables
------------
local modkey = "Mod4" -- default modkey

-- finalize
------------
return function(s)

    -- Taglist buttons
    local taglist_buttons = gears.table.join(
        awful.button({}, 1, function(t) t:view_only() end),
        awful.button({modkey}, 1, function(t)
            if client.focus then client.focus:move_to_tag(t) end
        end),
        awful.button({}, 3, awful.tag.viewtoggle),
        awful.button({modkey}, 3, function(t)
            if client.focus then client.focus:toggle_tag(t) end
        end),
        awful.button({}, 4, function(t) awful.tag.viewnext(t.screen) end),
        awful.button({}, 5, function(t) awful.tag.viewprev(t.screen) end)
    )

    -- the taglist itself
    local the_taglist = awful.widget.taglist {
        screen = s,
        filter = awful.widget.taglist.filter.all,
        layout = { layout = wibox.layout.fixed.horizontal, spacing = dpi(14), shape = gears.shape.circle},
        widget_template = {
            {
                id = "background_role",
                bg = beautiful.accent,
                shape = gears.shape.rounded_bar,
                widget = wibox.container.background,
                forced_height = dpi(9),
                forced_width = dpi(9),
            },
            -- Wrap it in a place container so the background_role is a child that can be fetched
            widget = wibox.container.place,
            create_callback = function(self, c3, _)
                local bg = self:get_children_by_id("background_role")[1]
                if not bg then return end -- Safety check
                
                if c3.selected then
                    bg.forced_width = dpi(15)
                elseif #c3:clients() == 0 then
                    bg.forced_width = dpi(9)
                else
                    bg.forced_width = dpi(9)
                end
            end,
            update_callback = function(self, c3, _)
                local bg = self:get_children_by_id("background_role")[1]
                if not bg then return end -- Safety check
                
                if c3.selected then
                    bg.forced_width = dpi(15)
                elseif #c3:clients() == 0 then
                    bg.forced_width = dpi(9)
                else
                    bg.forced_width = dpi(9)
                end
            end,
        },
        buttons = taglist_buttons
    }

    -- Safety fallbacks for colors in case the theme didn't load them
    local bg_3 = beautiful.bg_3 or "#222222"
    local fg_color_33 = (beautiful.fg_color or "#FFFFFF") .. "33"
    local rounded = beautiful.rounded or 4

    local kaka = require("helpers.widgets.create_button")(
        {
            {
                nil,
                the_taglist,
                layout = wibox.layout.align.vertical,
                expand = "none"
            },
            margins = {left = dpi(12), right = dpi(12)},
            widget = wibox.container.margin
        },
        bg_3,
        fg_color_33,
        dpi(0),
        dpi(0),
        dpi(0),
        helpers.rrect(rounded - 2)
    )

    return kaka
end

-- eof
------