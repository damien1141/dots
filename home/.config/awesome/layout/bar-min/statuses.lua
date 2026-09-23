-- minimal status indicators
----------------------------
-- Copyleft © 2022 Saimoomedits (Optimized)

-- requirements
---------------
local awful = require("awful")
local helpers = require("helpers")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local dpi = beautiful.xresources.apply_dpi

-- widgets
----------

-- wifi icon
local wifi = wibox.widget{
    font = beautiful.icon_var .. "13",
    markup = helpers.colorize_text("", beautiful.fg_color),
    widget = wibox.widget.textbox,
    valign = "center",
    align = "center",
    forced_width = dpi(28)
}

-- bluetooth icon
local blue = wibox.widget{
    font = beautiful.icon_var .. "13",
    widget = wibox.widget.textbox,
    valign = "center",
    align = "center",
    forced_width = dpi(28)
}

-- volume icon
local volume = wibox.widget{
    font = beautiful.icon_var .. "13",
    markup = helpers.colorize_text("", beautiful.fg_color),
    widget = wibox.widget.textbox,
    valign = "center",
    align = "center",
    forced_width = dpi(28)
}

local function updateVolumeIcon(volume_level)
    if volume_level >= 40 then
        volume.markup = helpers.colorize_text("", beautiful.fg_color)
    elseif volume_level >= 20 then
        volume.markup = helpers.colorize_text("", beautiful.fg_color)
    elseif volume_level >= 1 then
        volume.markup = helpers.colorize_text("", beautiful.fg_color)
    else
        volume.markup = helpers.colorize_text("", beautiful.fg_color .. "99")
    end
end

-- Non-blocking volume update (Replaces io.popen)
awful.widget.watch("amixer -D pulse sget Master", 0.5, function(_, stdout)
    local volumeLevel = tonumber(string.match(stdout, "(%d?%d?%d)%%")) or 0
    updateVolumeIcon(volumeLevel)
end)


-- microphone status indicator
local mic_icon = wibox.widget{
    font = beautiful.icon_var .. "13",
    markup = helpers.colorize_text("", beautiful.fg_color),
    widget = wibox.widget.textbox,
    valign = "center",
    align = "center",
    forced_width = dpi(28)
}

local function updateMicIcon(mic_level)
    if mic_level >= 1 then
        mic_icon.markup = helpers.colorize_text("", beautiful.fg_color)
    else
        mic_icon.markup = helpers.colorize_text("", beautiful.fg_color .. "99")
    end
end

-- Non-blocking mic update (Replaces io.popen)
awful.widget.watch("amixer -D pulse sget Capture", 0.5, function(_, stdout)
    local micLevel = tonumber(string.match(stdout, "(%d?%d?%d)%%")) or 0
    updateMicIcon(micLevel)
end)


-- battery indicator
local battery = wibox.widget{
    widget = wibox.container.arcchart,
    max_value = 100,
    min_value = 0,
    value = 50,
    thickness = dpi(3),
    rounded_edge = true,
    bg = beautiful.green_color .. "4D",
    colors = { beautiful.green_color },
    start_angle = math.pi + math.pi / 2,
    forced_width = dpi(20),
    forced_height = dpi(20)
}

-- indicator for cc. (control center)
local indicator = wibox.widget{
    widget = wibox.container.background,
    bg = beautiful.fg_color .. "4D",
    forced_height = dpi(2),
    visible = false
}

-- make it more cool! (Assuming helpers.widgets.create_button exists in your setup)
-- center every status glyph in a shared-width row so the column lines up
local function crow(w)
    return { w, widget = wibox.container.place, forced_width = dpi(36) }
end

local kaka = require("helpers.widgets.create_button")(
    {
        {
            nil, nil, indicator,
            layout = wibox.layout.align.vertical
        },
        {
            {
                crow(battery),
                crow(wifi),
                crow(blue),
                crow(mic_icon),
                crow(volume),
                layout = wibox.layout.fixed.vertical,
                spacing = dpi(6)
            },
            margins = {left = dpi(13), right = dpi(13), top = dpi(12), bottom = dpi(12)},
            widget = wibox.container.margin
        },
        layout = wibox.layout.stack
    },
    beautiful.bg_frost_2,
    beautiful.fg_color .. "33",
    dpi(0),
    dpi(1),
    (beautiful.fg_color or "#ffffff") .. "1A",
    helpers.rrect(beautiful.rounded - 2)
)

-- the final wrapped box
local widget_box = wibox.widget{
    widget = kaka
}


-- update ind status
--------------------
awesome.connect_signal("control_center::visible", function(val) 
    indicator.visible = val
end)

-- toggle cc (control center) on press
widget_box:connect_signal("button::press", function()
    -- Ensure cc_toggle is defined globally or required in your rc.lua
    if type(cc_toggle) == "function" then
        cc_toggle()
    end
end)


-- update widgets
-----------------

-- BLUETOOTH (Optimized: Single shell call, no sleep hack)
local bluetooth_active = false
local bluetooth_connected = false

local function updateBluetoothIcon()
    if bluetooth_active then
        if bluetooth_connected then
            blue.markup = helpers.colorize_text("", beautiful.fg_color)
        else
            blue.markup = helpers.colorize_text("", beautiful.fg_color)
        end
    else
        blue.markup = helpers.colorize_text("", beautiful.fg_color .. "99")
    end
end

-- Combined command: Returns "yes 1" or "no 0" (Powered State + Connected Count)
local bt_cmd = "sh -c 'echo -n \"$(bluetoothctl show 2>/dev/null | grep -i \"Powered:\" | awk \"{print \\$2}\") \"; bluetoothctl devices Connected 2>/dev/null | wc -l'"

awful.widget.watch(bt_cmd, 5, function(_, stdout)
    -- Parse the two values from the single shell execution
    local powered, connected_count = stdout:match("(%w+)%s+(%d+)")
    
    bluetooth_active = (powered == "yes")
    bluetooth_connected = (tonumber(connected_count) or 0) > 0
    
    updateBluetoothIcon()
end)


-- wifi
awesome.connect_signal("signal::wifi", function (value)
    if value then
        wifi.markup = helpers.colorize_text("", beautiful.fg_color)
    else
        wifi.markup = helpers.colorize_text("", beautiful.fg_color .. "99")
    end
end)

-- battery
awesome.connect_signal("signal::battery", function(value) 
    battery.value = value
end)


-- finalize
-----------
return widget_box

-- eof