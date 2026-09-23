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
local rubato = require("mods.rubato")

-- variables
------------
local modkey = "Mod4" -- default modkey

-- pill height for a tag's current state
-----------------------------------------
local function pill_height(t)
    if t.selected then return dpi(32) end
    if #t:clients() > 0 then return dpi(16) end
    return dpi(10)
end

-- pill color for a tag's current state
---------------------------------------
local function pill_color(t)
    if t.selected then
        return beautiful.accent
    elseif #t:clients() > 0 then
        return (beautiful.accent or "#8AB4F8") .. "AA"
    end
    return (beautiful.accent or "#8AB4F8") .. "38"
end

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
        -- REDUCED SPACING: dpi(10) down to dpi(3)
        layout = { layout = wibox.layout.fixed.vertical, spacing = dpi(3), shape = gears.shape.circle},
        widget_template = {
            {
                id = "background_role",
                bg = beautiful.accent,
                shape = gears.shape.rounded_bar,
                widget = wibox.container.background,
                forced_height = dpi(14),
                forced_width = dpi(6),
            },
            -- Wrap it in a place container so the background_role is a child that can be fetched
            widget = wibox.container.place,
            
            -- SHRUNK THE WRAPPER: dpi(40) down to dpi(32) to kill dead space
            forced_height = dpi(32), 
            forced_width = dpi(6),
            
            create_callback = function(self, c3, _)
                local bg = self:get_children_by_id("background_role")[1]
                if not bg then return end -- Safety check

                -- apply state immediately so pills are correct before any animation runs
                bg.bg = pill_color(c3)
                local h = pill_height(c3)
                bg.forced_height = h

                -- per-tag height animation, starts at the correct size (no jump)
                self.anim = rubato.timed{
                    pos = h,
                    target = h, -- Explicitly set target on creation to prevent drop to 0
                    rate = 60,
                    intro = 0.15,
                    duration = 0.3,
                    easing = rubato.quadratic,
                    awestore_compat = true,
                    rapid_set = true,
                    subscribed = function(pos)
                        -- Properly filter out NaN and negative values.
                        if pos and pos == pos and pos > 0 then
                            -- Updated clamp to match the new wrapper size
                            bg.forced_height = math.max(dpi(6), math.min(pos, dpi(32)))
                        end
                    end
                }
            end,
            update_callback = function(self, c3, _)
                local bg = self:get_children_by_id("background_role")[1]
                if not bg then return end -- Safety check

                bg.bg = pill_color(c3)

                -- glide to the new height instead of snapping
                local target = pill_height(c3)
                if self.anim then
                    if self.anim.target ~= target then
                        self.anim.target = target
                    end
                else
                    -- Fallback if the animation object was lost
                    bg.forced_height = target
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
            -- You can also reduce top/bottom margins slightly if you want it even tighter
            margins = {left = dpi(8), right = dpi(8), top = dpi(5), bottom = dpi(5)},
            widget = wibox.container.margin
        },
        "#00000000",  -- invisible at rest: pills float straight on the bar
        fg_color_33,  -- soft glow on hover / press
        dpi(0),
        dpi(0),
        dpi(0),
        helpers.rrect(rounded - 2)
    )

    return kaka
end

-- eof
------