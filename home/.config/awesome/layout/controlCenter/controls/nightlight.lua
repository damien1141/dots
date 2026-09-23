-- Night Light Toggle Widget
-- Delegates to the canonical nightlight module (nightlight/init.lua) so the
-- control-center button and the keybinds use the same state machine.
--
-- The previous version spawned its own `sct 2400`
-- daemon, which clobbered both the ICC calibration and the solar curve.
-- That is gone.
--
-- State source of truth: nightlight.status_line() ("off" | "manual %dK" |
-- "%dK <why>"). The on/off decision is whether the module is in any
-- override state vs auto.
-- -----------------------------------
local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local dpi = beautiful.xresources.apply_dpi
local helpers = require("helpers")
local wibox = require("wibox")
local rubato = require("mods.rubato")

local nightlight = require("nightlight")

local service_icon = "" -- nightlight

local icon = wibox.widget{
    font = (beautiful.icon_var or beautiful.font) .. "16",
    markup = helpers.colorize_text(service_icon, beautiful.fg_normal or beautiful.fg_color),
    widget = wibox.widget.textbox,
    valign = "center",
    align = "center",
}

local circle_animate = wibox.widget{
    widget = wibox.container.background,
    shape = helpers.rrect((beautiful.rounded or 4) - 3),
    bg = beautiful.accent,
    forced_width = dpi(65),
    forced_height = dpi(0),
}

local alright = wibox.widget{
    {
        {
            nil,
            { circle_animate, layout = wibox.layout.fixed.horizontal },
            layout = wibox.layout.align.horizontal,
            expand = "none"
        },
        {
            nil,
            { icon, layout = wibox.layout.fixed.vertical, spacing = dpi(10) },
            layout = wibox.layout.align.vertical,
            expand = "none"
        },
        layout = wibox.layout.stack
    },
    widget = wibox.container.background,
    shape = gears.shape.circle,
    border_color = (beautiful.fg_normal or beautiful.fg_color) .. "33",
    forced_width = dpi(55),
    forced_height = dpi(55),
    bg = beautiful.bg_frost_3
}

local animation_button_opacity = rubato.timed{
    pos = 0,
    rate = 60,
    intro = 0.08,
    duration = 0.3,
    subscribed = function(pos)
        circle_animate.opacity = pos
    end
}

-- "on" = auto curve running or in a manual hold; "off" = explicitly off.
local function is_on()
    local s = nightlight.status_line()
    return s ~= "off"
end

local function update_visual()
    local on = is_on()
    if on then
        icon.markup = helpers.colorize_text(service_icon, beautiful.accent)
        animation_button_opacity.target = 0.09
    else
        icon.markup = helpers.colorize_text(service_icon,
            (beautiful.fg_normal or beautiful.fg_color) .. "4D")
        animation_button_opacity.target = 0
    end
end

-- Re-render whenever the module's status changes (covers all callers:
-- keybind, panel, control-center click).
awesome.connect_signal("nightlight::status", function()
    update_visual()
end)

-- Initial paint: ask the module for its current state.
update_visual()

-- Click: delegate to the module.
alright:buttons(gears.table.join(awful.button({}, 1, nil, function()
    nightlight.toggle()
    update_visual()
    local notify = require("layout.ding.extra.short")
    if notify then
        local s = nightlight.status_line()
        local on = is_on()
        notify(on and "" or "", "夜间模式 " .. s)
    end
end)))

return alright
