-- helper function to create buttons
-- uses rubato for smoooth animations
-------------------------------------
-- Copyleft © 2022 Saimoomedits


-- requirements
-- ~~~~~~~~~~~~
local beautiful = require "beautiful"
local gears = require "gears"
local wibox = require "wibox"
local rubato = require("mods.rubato")
local dpi = beautiful.xresources.apply_dpi


return function (widget, normal_bg, press_color, margins, border_width, border_color, shape_spe)

    -- containers
    local circle_animate = wibox.widget{
        widget = wibox.container.background,
        shape = shape_spe or gears.shape.rounded_bar,
        bg = press_color or beautiful.accent_3,
    }

    local mainbox = wibox.widget {
        {
            circle_animate,
            {
                widget,
                margins = margins or  dpi(15),
                widget = wibox.container.margin
            },
            layout = wibox.layout.stack
        },
      bg = (normal_bg) or beautiful.bg_3,
      shape = shape_spe or gears.shape.rounded_bar,
      -- container.background draws borders via the shape_* props; plain
      -- border_width/border_color are dead here (and render opaque on wiboxes)
      shape_border_width = border_width or dpi(0),
      shape_border_color = type(border_color) == "string" and border_color or press_color or "#00000000",
      widget = wibox.container.background,
    }

    -- Opacity animation (snappy, no timers, no layout distortion)
    local anim_opacity = rubato.timed{
        pos = 0,
        rate = 60,
        intro = 0.08,
        duration = 0.2,
        easing = rubato.quadratic,
        subscribed = function(pos)
            circle_animate.opacity = pos
        end
    }

    -- hover and press interactions
    mainbox:connect_signal("mouse::enter", function()
        if not mainbox.is_pressed then
            anim_opacity.target = 0.4
        end
    end)

    mainbox:connect_signal("mouse::leave", function()
        if not mainbox.is_pressed then
            anim_opacity.target = 0.0
        end
    end)

    -- add buttons and commands
    mainbox:connect_signal("button::press", function()
        mainbox.is_pressed = true
        anim_opacity.target = 1.0
    end)

    mainbox:connect_signal("button::release", function()
        mainbox.is_pressed = false
        anim_opacity.target = 0.4 -- instantly target hover state, let rubato handle the smooth fade
    end)

    return mainbox

end