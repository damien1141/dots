-- sliders for different controls
---------------------------------
local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local dpi = beautiful.xresources.apply_dpi
local helpers = require("helpers")
local wibox = require("wibox")

local brightness_ctrl = require("signal.bright")

-- brightness
-------------
local brightness = wibox.widget{
    widget = wibox.widget.slider,
    value = 50,
    maximum = 100,
    forced_width = dpi(260),
    shape = gears.shape.rounded_bar,
    bar_shape = gears.shape.rounded_bar,
    bar_color = beautiful.bg_frost_3,
    bar_margins = {bottom = dpi(8) ,top = dpi(8)},
    bar_active_color = beautiful.accent_transparent,
    handle_width = dpi(12),
    handle_shape = gears.shape.circle,
    handle_color = beautiful.accent,
    handle_border_width = 3,
    handle_border_color = beautiful.bg_frost_2
}

local brightness_text = wibox.widget{
    widget = wibox.widget.textbox,
    markup = helpers.colorize_text("50%", beautiful.fg_color),
    font = beautiful.font_var .. "10",
    align = "center",
    valign = "center",
    forced_width = dpi(30)
}

local brightness_icon = wibox.widget{
    widget = wibox.widget.textbox,
    markup = helpers.colorize_text("", beautiful.fg_color),
    font = beautiful.icon_var .. "14",
    align = "center",
    valign = "center"
}

local bright_init = wibox.widget{
    brightness_icon,
    {
        brightness,
        widget = wibox.container.rotate,
        forced_height = dpi(15),
        forced_width = dpi(210)
    },
    brightness_text,
    layout = wibox.layout.fixed.horizontal,
    spacing = dpi(20),
}

-- Feedback loop protection
local user_dragging = false
local updating_externally = false

awesome.connect_signal("signal::brightness", function(value)
    local val = math.floor(tonumber(value) or 0)
    if brightness.value ~= val then
        updating_externally = true
        brightness.value = val
        updating_externally = false
    end
    brightness_text.markup = helpers.colorize_text(val .. "%", beautiful.fg_color)
    
    if val <= 50 then
        brightness_icon.markup = helpers.colorize_text("", beautiful.yellow_color or beautiful.fg_color)
    else
        brightness_icon.markup = helpers.colorize_text("", beautiful.fg_color)
    end
end)

brightness:connect_signal("button::press", function() user_dragging = true end)
brightness:connect_signal("button::release", function() user_dragging = false end)

brightness:connect_signal("property::value", function(_, new_value)
    local val = math.floor(new_value)
    brightness_text.markup = helpers.colorize_text(val .. "%", beautiful.fg_color)
    
    if val <= 50 then
        brightness_icon.markup = helpers.colorize_text("", beautiful.yellow_color or beautiful.fg_color)
    else
        brightness_icon.markup = helpers.colorize_text("", beautiful.fg_color)
    end
    
    if user_dragging and not updating_externally then
        brightness_ctrl.set_hw(val)
    end
end)

brightness_icon:buttons(
    gears.table.join(
        awful.button({}, 5, function() brightness_ctrl.down() end),
        awful.button({}, 4, function() brightness_ctrl.up() end)
    )
)

-- volume
-- progressbar (volume)
local volume = wibox.widget{
    widget = wibox.widget.slider,
    value = 10,
    maximum = 100,
    forced_width = dpi(260),
    shape = gears.shape.rounded_bar,
    bar_shape = gears.shape.rounded_bar,
    bar_color = beautiful.bg_frost_3,
    bar_margins = {bottom = dpi(8) ,top = dpi(8)},
    bar_active_color = beautiful.accent_transparent,
    handle_width = dpi(12),
    handle_shape = gears.shape.circle,
    handle_color = beautiful.accent,
    handle_border_width = 3,
    handle_border_color = beautiful.bg_frost_2
}

local volume_icon = wibox.widget{
    widget = wibox.widget.textbox,
    markup = helpers.colorize_text(" ", beautiful.fg_color),
    font = beautiful.icon_var .. "14",
    align = "center",
    valign = "center"
}

local volume_text = wibox.widget{
    widget = wibox.widget.textbox,
    markup = helpers.colorize_text("15%", beautiful.fg_color),
    font = beautiful.font_var .. "10",
    align = "center",
    valign = "center",
    forced_width = dpi(30)
}

local volume_init = wibox.widget{
    volume_icon,
    {
        volume,
        widget = wibox.container.rotate,
        forced_height = dpi(10),
        forced_width = dpi(210)
    },
    volume_text,
    layout = wibox.layout.fixed.horizontal,
    spacing = dpi(20),
}

-- Volume logic
local vol_muted = false
local function update_widget_according_to_vol_muted()
    if not vol_muted then
        volume.opacity = 1
        volume_icon.markup = helpers.colorize_text("", beautiful.fg_color)
    else
        volume_icon.markup = helpers.colorize_text("", beautiful.fg_color .. "66")
        volume.opacity = 0.6
    end
end

awesome.connect_signal("volume::muted", function(muted)
    vol_muted = muted
    update_widget_according_to_vol_muted()
end)

local function toggle_mute()
    if not vol_muted then
        awful.spawn("amixer -D pulse set Master mute", false)
        vol_muted = true
    else
        awful.spawn("amixer -D pulse set Master unmute", false)
        vol_muted = false
    end
    update_widget_according_to_vol_muted()
end

awesome.connect_signal("volume::value", function(value)
    local val = math.floor(tonumber(value))
    volume.value = val
    volume_text.markup = val .. "%"
    awful.spawn("amixer -D pulse set Master " .. val .. "%", false)
end)

volume:connect_signal("property::value", function(_, new_value)
    local val = math.floor(new_value)
    volume_text.markup = helpers.colorize_text(val .. "%", beautiful.fg_color)
    volume.value = val
    awful.spawn("amixer -D pulse set Master " .. val .. "%", false)
end)

volume_icon:buttons(gears.table.join(
    awful.button({}, 1, function() toggle_mute() end)
))

-- microphone
local mic = wibox.widget{
    widget = wibox.widget.slider,
    value = 0,
    maximum = 100,
    forced_width = dpi(260),
    shape = gears.shape.rounded_bar,
    bar_shape = gears.shape.rounded_bar,
    bar_color = beautiful.bg_frost_3,
    bar_margins = {bottom = dpi(8) ,top = dpi(8)},
    bar_active_color = beautiful.accent_transparent,
    handle_width = dpi(12),
    handle_shape = gears.shape.circle,
    handle_color = beautiful.accent,
    handle_border_width = 3,
    handle_border_color = beautiful.bg_frost_2
}

local mic_icon = wibox.widget{
    widget = wibox.widget.textbox,
    markup = helpers.colorize_text("", beautiful.fg_color),
    font = beautiful.icon_var .. "14",
    align = "center",
    valign = "center"
}

local mic_text = wibox.widget{
    widget = wibox.widget.textbox,
    markup = helpers.colorize_text("0%", beautiful.fg_color),
    font = beautiful.font_var .. "10",
    align = "center",
    valign = "center",
    forced_width = dpi(30)
}

local mic_init = wibox.widget{
    mic_icon,
    {
        mic,
        widget = wibox.container.rotate,
        forced_height = dpi(10),
        forced_width = dpi(210)
    },
    mic_text,
    layout = wibox.layout.fixed.horizontal,
    spacing = dpi(20),
}

-- Mic logic
local mic_muted = false
awesome.connect_signal("mic::muted", function(muted)
    mic_muted = muted
    if not mic_muted then
        mic.opacity = 1
        mic_icon.markup = helpers.colorize_text("", beautiful.fg_color)
    else
        mic_icon.markup = helpers.colorize_text("", beautiful.fg_color .. "66")
        mic.opacity = 0.6
    end
end)

local function toggle_mic_mute()
    if not mic_muted then
        awful.spawn("amixer -D pulse set Capture mute", false)
        mic_muted = true
        mic.opacity = 0.6
        mic_icon.markup = helpers.colorize_text("", beautiful.fg_color .. "66")
    else
        awful.spawn("amixer -D pulse set Capture unmute", false)
        mic_muted = false
        mic.opacity = 1
        mic_icon.markup = helpers.colorize_text("", beautiful.fg_color)
    end
    awesome.emit_signal("mic::muted", mic_muted)
end

mic:connect_signal("property::value", function(_, new_value)
    local val = math.floor(new_value)
    mic_text.markup = helpers.colorize_text(val .. "%", beautiful.fg_color)
    mic.value = val
    awful.spawn("amixer -D pulse set Capture " .. val .. "%", false)
end)

mic_icon:buttons(gears.table.join(
    awful.button({}, 1, function() toggle_mic_mute() end)
))

-- finalize
return wibox.widget{
    {
        {
            {
                {
                    widget = wibox.widget.textbox,
                    markup = helpers.colorize_text("控制", beautiful.fg_color .. "4D"),
                    font = beautiful.font_var .. "10",
                    align = "left",
                    valign = "center"
                },
                margins = {left = dpi(15)},
                widget = wibox.container.margin
            },
            {
                {
                    bright_init,
                    volume_init,
                    mic_init,
                    spacing = dpi(24),
                    layout = wibox.layout.fixed.vertical,
                },
                margins = {right = dpi(25), left = dpi(25)},
                widget = wibox.container.margin
            },
            layout = wibox.layout.fixed.vertical,
            spacing = dpi(12)
        },
        widget = wibox.container.margin,
        margins = {top = dpi(10), bottom = dpi(15)},
    },
    shape = helpers.rrect(beautiful.rounded),
    bg = beautiful.bg_frost_2,
    widget = wibox.container.background,
}