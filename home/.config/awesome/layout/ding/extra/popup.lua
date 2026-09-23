-- popup notif --
-- ~~~~~~~~~~~ --
local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local helpers = require("helpers")
local dpi = beautiful.xresources.apply_dpi

-- Shared Widgets
local icon = wibox.widget({
    font 	= beautiful.icon_var .. "16",
    align 	= "center",
    valign 	= "center",
    widget 	= wibox.widget.textbox,
})

local bar = wibox.widget{
    bar_color           = beautiful.bg_frost_3,
    handle_color        = beautiful.blue_color,
    handle_shape        = gears.shape.circle,
    bar_active_color    = beautiful.blue_color,
    bar_height			= dpi(4),
    bar_width			= dpi(10),
    value               = 25,
    minimum				= 0,
    maximum 			= 100,
    widget              = wibox.widget.slider,
}

local pop = wibox({
    type    = "popup",
    screen  = screen.primary,
    height  = dpi(180),
    width   = dpi(55),
    shape   = helpers.rrect(beautiful.rounded_wids),
    bg      = beautiful.bg_transparent,
    shape_border_width = dpi(1),
    shape_border_color = beautiful.fg_color .. "14",
    halign  = "left",
    valign  = "center",
    ontop   = true,
    visible = false,
})

awful.placement.right(pop, {margins = {right = dpi(64) + beautiful.useless_gap * 2}})

local timeout = gears.timer({
    autostart   = true,
    timeout     = 2.4,
    single_shot = true,
    callback    = function() pop.visible = false end,
})

local function toggle_pop()
    if pop.visible then
        timeout:again()
    else
        pop.visible = true
        timeout:start()
    end
end

pop:setup({
        {
            {
                bar,
            		forced_height = dpi(100),
                	forced_width  = dpi(5),
                	direction     = 'east',
            		widget        = wibox.container.rotate,
            },
            margins = dpi(15),
            layout = wibox.container.margin
        },
        {
            icon,
            margins = {bottom = dpi(10)},
            widget = wibox.container.margin
        },
        spacing = dpi(10),
        layout = wibox.layout.fixed.vertical
})

-- ==========================================
-- 1. VOLUME & MUTE POPUPS
-- ==========================================
awesome.connect_signal("volume::changed", function(delta)
    if control_c.visible then return end
    bar.handle_color = beautiful.accent
    bar.bar_active_color = beautiful.accent
    icon.markup = "<span foreground='" .. beautiful.accent .. "'>󰕾</span>"
    local current = tonumber(bar.value) or 0
    local change = tonumber(delta) or 0
    bar.value = math.max(0, math.min(100, current + change))
    toggle_pop()
end)

awesome.connect_signal("volume::value", function(value)
    bar.value = tonumber(value) or 0
end)

awesome.connect_signal("volume::muted", function(muted)
    if control_c.visible then return end
    local mute_red = beautiful.red_color or "#9C474C"
    local grey = "#888888"
    if muted then
        bar.handle_color = mute_red
        bar.bar_active_color = mute_red
        icon.markup = "<span foreground='" .. mute_red .. "'>󰖁</span>"
    else
        bar.handle_color = grey
        bar.bar_active_color = grey
        icon.markup = "<span foreground='" .. grey .. "'>󰖁</span>"
    end
    toggle_pop()
end)

-- ==========================================
-- 2. UNIFIED BRIGHTNESS POPUP
-- ==========================================
local first_B = true
awesome.connect_signal("signal::brightness", function(value)
    if first_B or control_c.visible then
        first_B = false
        return
    end

    local val = tonumber(value) or 0
    local yellow = beautiful.yellow_color or beautiful.accent

    -- If below 50%, show moon icon. If above, show sun icon.
    if val <= 50 then
        icon.markup = "<span foreground='" .. yellow .. "'>󰃞 </span>"
        bar.handle_color = yellow
        bar.bar_active_color = yellow
    else
        icon.markup = "<span foreground='" .. beautiful.accent .. "'>󰃠 </span>"
        bar.handle_color = beautiful.accent
        bar.bar_active_color = beautiful.accent
    end

    bar.value = val
    toggle_pop()
end)
