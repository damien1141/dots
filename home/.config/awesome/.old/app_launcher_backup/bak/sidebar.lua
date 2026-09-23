 ---------------------------------------------------------------------------
-- Sidebar widgets: profile picture, status icons, clock.
---------------------------------------------------------------------------

local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local helpers = require("helpers")
local readwrite = require("misc.scripts.read_writer")
local rubato = require("mods.rubato")
local dpi = beautiful.xresources.apply_dpi
local math = math
local string = string

local sidebar = {}

-- =====================================================================
-- Profile widget
-- =====================================================================

function sidebar.create_profile_widget()
    local is_inhibiting = false

    local profile_stack = wibox.widget {
        {
            image = beautiful.pfp,
            clip_shape = helpers.rrect(beautiful.rounded_square or beautiful.rounded or 12),
            forced_width = dpi(88),
            forced_height = dpi(88),
            widget = wibox.widget.imagebox
        },
        widget = wibox.container.background,
        bg = beautiful.bg_2,
        forced_width = dpi(88),
        forced_height = dpi(88),
    }

    local function toggle_inhibit()
        is_inhibiting = not is_inhibiting
        if is_inhibiting then
            awful.spawn.with_shell("xset s off && xset -dpms")
        else
            awful.spawn.with_shell("xset s on && xset +dpms")
        end
    end

    profile_stack:buttons(gears.table.join(
        awful.button({}, 1, function()
            toggle_inhibit()
        end)
    ))

    return profile_stack
end

-- =====================================================================
-- Quick settings (Android-style toggles)
-- =====================================================================



function sidebar.create_quicksettings_widget()
    local btn_size = dpi(55)

    -- Keep screen on
    local inhibit_icon = wibox.widget{
        font = beautiful.icon_var .. "16",
        markup = helpers.colorize_text(" ", beautiful.fg_color .. "4D"),
        widget = wibox.widget.textbox,
        valign = "center",
        align = "center"
    }
    local inhibit_state = false
    local inhibit_circle = wibox.widget{
        widget = wibox.container.background,
        shape = helpers.rrect((beautiful.rounded or 4) - 3),
        bg = beautiful.accent,
        forced_width = dpi(65),
        forced_height = dpi(65),
    }
    local inhibit_btn = wibox.widget{
        {
            {
                nil,
                { inhibit_circle, layout = wibox.layout.fixed.horizontal },
                layout = wibox.layout.align.horizontal,
                expand = "none"
            },
            {
                inhibit_icon,
                widget = wibox.container.place,
                halign = "center",
                valign = "center"
            },
            layout = wibox.layout.stack
        },
        shape = gears.shape.circle,
        widget = wibox.container.background,
        border_color = beautiful.fg_color .. "33",
        forced_width = btn_size,
        forced_height = btn_size,
        bg = beautiful.bg_3
    }
    local inhibit_anim = rubato.timed{
        pos = 0, rate = 60, intro = 0.08, duration = 0.3,
        awestore_compat = true,
        subscribed = function(pos) inhibit_circle.opacity = pos end
    }
    local function update_inhibit_visual()
        inhibit_icon.markup = helpers.colorize_text(" ", inhibit_state and beautiful.accent or beautiful.fg_color .. "4D")
        inhibit_anim.target = inhibit_state and 0.09 or 0
    end
    inhibit_btn:buttons(gears.table.join(
        awful.button({}, 1, function()
            inhibit_state = not inhibit_state
            if inhibit_state then
                awful.spawn.with_shell("xset s off && xset -dpms")
            else
                awful.spawn.with_shell("xset s on && xset +dpms")
            end
            update_inhibit_visual()
        end)
    ))

    -- Night light
    local night_icon = wibox.widget{
        font = beautiful.icon_var .. "16",
        markup = helpers.colorize_text(" ", beautiful.fg_color .. "4D"),
        widget = wibox.widget.textbox,
        valign = "center",
        align = "center"
    }
    local night_state = false
    local night_circle = wibox.widget{
        widget = wibox.container.background,
        shape = helpers.rrect((beautiful.rounded or 4) - 3),
        bg = beautiful.accent,
        forced_width = dpi(65),
        forced_height = dpi(65),
    }
    local night_btn = wibox.widget{
        {
            {
                nil,
                { night_circle, layout = wibox.layout.fixed.horizontal },
                layout = wibox.layout.align.horizontal,
                expand = "none"
            },
            {
                night_icon,
                widget = wibox.container.place,
                halign = "center",
                valign = "center"
            },
            layout = wibox.layout.stack
        },
        shape = gears.shape.circle,
        widget = wibox.container.background,
        border_color = beautiful.fg_color .. "33",
        forced_width = btn_size,
        forced_height = btn_size,
        bg = beautiful.bg_3
    }
    local night_anim = rubato.timed{
        pos = 0, rate = 60, intro = 0.08, duration = 0.3,
        awestore_compat = true,
        subscribed = function(pos) night_circle.opacity = pos end
    }
    local night_state_file = os.getenv("HOME") .. "/.config/awesome/misc/.information/blue_light_state"
    os.execute("mkdir -p " .. night_state_file:match("(.*/)"))
    local function update_night_visual()
        night_icon.markup = helpers.colorize_text("󰌵 ", night_state and beautiful.accent or beautiful.fg_color .. "4D")
        night_anim.target = night_state and 0.09 or 0
    end
    do
        local file = io.open(night_state_file, "r")
        if file then
            night_state = (file:read("*l") == "true")
            file:close()
            update_night_visual()
        end
    end
    night_btn:buttons(gears.table.join(awful.button({}, 1, function()
        local cmd = [[
            PID=$(pgrep -x redshift)
            if [ -n "$PID" ]; then
                redshift -x 2>/dev/null
                kill "$PID" 2>/dev/null
                echo "false"
            else
                redshift -l 0:0 -t 2400:2400 -r &>/dev/null &
                echo "true"
            fi
        ]]
        awful.spawn.easy_async({"bash", "-c", cmd}, function(stdout)
            night_state = (stdout:match("true") ~= nil)
            local f = io.open(night_state_file, "w")
            if f then f:write(tostring(night_state)) f:close() end
            update_night_visual()
        end)
    end)))

    -- Do not disturb
    local dnd_icon = wibox.widget{
        font = beautiful.icon_var .. "16",
        markup = helpers.colorize_text("󱏧 ", beautiful.fg_color .. "4D"),
        widget = wibox.widget.textbox,
        valign = "center",
        align = "center"
    }
    local dnd_state = false
    local dnd_circle = wibox.widget{
        widget = wibox.container.background,
        shape = helpers.rrect((beautiful.rounded or 4) - 3),
        bg = beautiful.accent,
        forced_width = dpi(65),
        forced_height = dpi(65),
    }
    local dnd_btn = wibox.widget{
        {
            {
                nil,
                { dnd_circle, layout = wibox.layout.fixed.horizontal },
                layout = wibox.layout.align.horizontal,
                expand = "none"
            },
            {
                dnd_icon,
                widget = wibox.container.place,
                halign = "center",
                valign = "center"
            },
            layout = wibox.layout.stack
        },
        shape = gears.shape.circle,
        widget = wibox.container.background,
        border_color = beautiful.fg_color .. "33",
        forced_width = btn_size,
        forced_height = btn_size,
        bg = beautiful.bg_3
    }
    local dnd_anim = rubato.timed{
        pos = 0, rate = 60, intro = 0.08, duration = 0.3,
        awestore_compat = true,
        subscribed = function(pos) dnd_circle.opacity = pos end
    }
    local function update_dnd_visual()
        dnd_icon.markup = helpers.colorize_text("󱏧 ", dnd_state and beautiful.accent or beautiful.fg_color .. "4D")
        dnd_anim.target = dnd_state and 0.09 or 0
    end
    do
        local output = readwrite.readall("dnd_state")
        local boolconverter = { ["true"] = true, ["false"] = false }
        dnd_state = boolconverter[output] or false
        update_dnd_visual()
    end
    dnd_btn:buttons(gears.table.join(
        awful.button({}, 1, function()
            dnd_state = not dnd_state
            readwrite.write("dnd_state", tostring(dnd_state))
            if dnd_state then
                awful.spawn.with_shell("dunstctl set-paused true")
            else
                awful.spawn.with_shell("dunstctl set-paused false")
            end
            update_dnd_visual()
        end)
    ))

    return wibox.widget{
        inhibit_btn,
        night_btn,
        dnd_btn,
        layout = wibox.layout.fixed.horizontal,
        spacing = dpi(8)
    }
end

-- =====================================================================
-- Status icons (module-scope widgets so watchers can update them)
-- =====================================================================

-- wifi icon
local wifi = wibox.widget{
    font = beautiful.icon_var .. "12",
    markup = helpers.colorize_text("󰖩 ", beautiful.fg_color),
    widget = wibox.widget.textbox
}
wifi:buttons(gears.table.join(
    awful.button({}, 1, function()
        awful.spawn("kitty nmtui")
    end)
))

-- bluetooth icon
local blue = wibox.widget{
    font = beautiful.icon_var .. "12",
    markup = helpers.colorize_text("󰂲 ", beautiful.fg_color .. "99"),
    widget = wibox.widget.textbox
}
blue:buttons(gears.table.join(
    awful.button({}, 1, function()
        awful.spawn("blueberry")
    end)
))

-- volume icon
local volume = wibox.widget{
    font = beautiful.icon_var .. "12",
    markup = helpers.colorize_text("󰕾 ", beautiful.fg_color),
    widget = wibox.widget.textbox
}

local function updateVolumeIcon(volume_level)
    if volume_level >= 40 then
        volume.markup = helpers.colorize_text("󰕾 ", beautiful.fg_color)
    elseif volume_level >= 20 then
        volume.markup = helpers.colorize_text("󰖀 ", beautiful.fg_color)
    elseif volume_level >= 1 then
        volume.markup = helpers.colorize_text("󰕿 ", beautiful.fg_color)
    else
        volume.markup = helpers.colorize_text("󰖁 ", beautiful.fg_color .. "99")
    end
end

-- Non-blocking volume update
awful.widget.watch("amixer -D pulse sget Master", 0.5, function(_, stdout)
    local volumeLevel = tonumber(string.match(stdout, "(%d?%d?%d)%%")) or 0
    updateVolumeIcon(volumeLevel)
end)

-- Set initial volume icon
awful.spawn.easy_async({"amixer", "-D", "pulse", "sget", "Master"}, function(stdout)
    local volumeLevel = tonumber(string.match(stdout, "(%d?%d?%d)%%")) or 0
    updateVolumeIcon(volumeLevel)
end)

-- microphone status indicator
local mic_icon = wibox.widget{
    font = beautiful.icon_var .. "12",
    markup = helpers.colorize_text(" ", beautiful.fg_color),
    widget = wibox.widget.textbox
}

local function updateMicIcon(mic_level)
    if mic_level >= 1 then
        mic_icon.markup = helpers.colorize_text(" ", beautiful.fg_color)
    else
        mic_icon.markup = helpers.colorize_text(" ", beautiful.fg_color .. "99")
    end
end

-- Non-blocking mic update
awful.widget.watch("amixer -D pulse sget Capture", 0.5, function(_, stdout)
    local micLevel = tonumber(string.match(stdout, "(%d?%d?%d)%%")) or 0
    updateMicIcon(micLevel)
end)

-- Set initial mic icon
awful.spawn.easy_async({"amixer", "-D", "pulse", "sget", "Capture"}, function(stdout)
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
    forced_width = dpi(17),
    forced_height = dpi(17)
}

-- bluetooth status
local bluetooth_active = false
local bluetooth_connected = false

local function updateBluetoothIcon()
    if bluetooth_active then
        if bluetooth_connected then
            blue.markup = helpers.colorize_text("󰂱 ", beautiful.fg_color)
        else
            blue.markup = helpers.colorize_text("󰂯 ", beautiful.fg_color)
        end
    else
        blue.markup = helpers.colorize_text("󰂲 ", beautiful.fg_color .. "99")
    end
end

local bt_cmd = "sh -c 'echo -n \"$(bluetoothctl show 2>/dev/null | grep -i \"Powered:\" | awk \"{print \\$2}\") \"; bluetoothctl devices Connected 2>/dev/null | wc -l'"

awful.widget.watch(bt_cmd, 5, function(_, stdout)
    local powered, connected_count = stdout:match("(%w+)%s+(%d+)")
    bluetooth_active = (powered == "yes")
    bluetooth_connected = (tonumber(connected_count) or 0) > 0
    updateBluetoothIcon()
end)

-- wifi signal
awesome.connect_signal("signal::wifi", function (value)
    if value then
        wifi.markup = helpers.colorize_text("󰖩 ", beautiful.fg_color)
    else 
        wifi.markup = helpers.colorize_text("󰖪 ", beautiful.fg_color .. "99")
    end
end)

-- battery signal
awesome.connect_signal("signal::battery", function(value) 
    battery.value = value
end)

function sidebar.create_statuses_widget()
    local statuses = wibox.widget {
        wifi,
        blue,
        volume,
        mic_icon,
        battery,
        layout = wibox.layout.fixed.horizontal,
        spacing = dpi(10)
    }
    return wibox.widget {
        statuses,
        widget = wibox.container.place,
        halign = "right",
        valign = "center"
    }
end

-- =====================================================================
-- Clock / Date / Weather
-- =====================================================================

function sidebar.create_time_widget()
    -- Weather Widget (Open-Meteo)
    local LAT = user_likes.lat or 9.099724
    local LON = user_likes.lon or -94.578331
    local USE_FAHRENHEIT = true

    local function get_weather_emoji(code)
        code = tonumber(code)
        if not code then return "☁️" end
        local weather_map = {
            [0]  = "☀️", [1]  = "🌤️", [2]  = "⛅", [3]  = "☁️",
            [45] = "🌫️", [48] = "🌫️",
            [51] = "🌦️", [53] = "🌦️", [55] = "🌧️",
            [56] = "🌨️", [57] = "🌨️",
            [61] = "🌧️", [63] = "🌧️", [65] = "🌧️",
            [66] = "🌨️", [67] = "🌨️",
            [71] = "🌨️", [73] = "🌨️", [75] = "❄️", [77] = "❄️",
            [80] = "🌦️", [81] = "🌧️", [82] = "⛈️",
            [85] = "🌨️", [86] = "❄️",
            [95] = "⛈️", [96] = "⛈️", [99] = "⛈️",
        }
        return weather_map[code] or "❓"
    end

    local weather_icon = wibox.widget{
        font = beautiful.icon_var .. "12",
        markup = helpers.colorize_text("⛅", beautiful.fg_color .. "4D"),
        widget = wibox.widget.textbox,
        align = "center",
        valign = "center"
    }
    local weather_temp = wibox.widget{
        font = beautiful.font_var .. "10",
        markup = helpers.colorize_text("--°F", beautiful.fg_color .. "4D"),
        widget = wibox.widget.textbox,
        align = "center",
        valign = "center"
    }

    local function update_weather()
        local url = string.format(
            "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current_weather=true&units=metric",
            LAT, LON
        )
        awful.spawn.easy_async({"curl", "-s", url}, function(stdout)
            local temp_match = stdout:match('"temperature":%s*(-?%d+%.?%d*)')
            local code_match = stdout:match('"weathercode":%s*(%d+)')
            if not temp_match or not code_match then return end
            local temp_c = tonumber(temp_match)
            local temp_display = USE_FAHRENHEIT and math.floor(temp_c * 9 / 5 + 32) or math.floor(temp_c)
            local code = tonumber(code_match)
            local icon = get_weather_emoji(code)
            weather_icon.markup = helpers.colorize_text(icon, beautiful.fg_color)
            weather_temp.markup = helpers.colorize_text(temp_display .. (USE_FAHRENHEIT and "°F" or "°C"), beautiful.fg_color)
        end)
    end

    gears.timer.new {
        timeout = 1800,
        callback = update_weather,
        autostart = true,
    }
    update_weather()

    -- Time
    local time_hour = wibox.widget{
        font = beautiful.font_var .. "Bold 12",
        format = "%H",
        widget = wibox.widget.textclock
    }
    local time_min = wibox.widget{
        font = beautiful.font_var .. "Bold 12",
        format = "%M",
        widget = wibox.widget.textclock
    }
    local colon = wibox.widget{
        font = beautiful.font_var .. "Bold 12",
        markup = helpers.colorize_text(":", beautiful.fg_color .. "99"),
        widget = wibox.widget.textbox
    }

    -- Date
    local time_day = wibox.widget{
        font = beautiful.font_var .. "9",
        format = "%a",
        widget = wibox.widget.textclock
    }
    local time_date = wibox.widget{
        font = beautiful.font_var .. "9",
        format = "%d",
        widget = wibox.widget.textclock
    }
    local time_mon = wibox.widget{
        font = beautiful.font_var .. "9",
        format = "de %b",
        widget = wibox.widget.textclock
    }

    local function update_colors()
        local fg = beautiful.fg_color .. "99"
        local fg_dim = beautiful.fg_color .. "4D"
        time_hour.markup = helpers.colorize_text(time_hour.text, fg)
        time_min.markup = helpers.colorize_text(time_min.text, fg)
        time_day.markup = helpers.colorize_text(time_day.text, fg_dim)
        time_date.markup = helpers.colorize_text(time_date.text, fg_dim)
        time_mon.markup = helpers.colorize_text(time_mon.text, fg_dim)
    end

    time_hour:connect_signal("widget::redraw_needed", update_colors)
    time_min:connect_signal("widget::redraw_needed", update_colors)
    time_day:connect_signal("widget::redraw_needed", update_colors)
    time_date:connect_signal("widget::redraw_needed", update_colors)
    time_mon:connect_signal("widget::redraw_needed", update_colors)
    update_colors()

    -- Compressed single-row layout:
    -- [HH:MM] [DAY DD de MON] [🌡️ 72°F]
    local time_part = wibox.widget{
        time_hour,
        colon,
        time_min,
        layout = wibox.layout.fixed.horizontal,
        spacing = dpi(1)
    }
    local date_part = wibox.widget{
        time_day,
        { widget = wibox.container.margin, left = dpi(4), right = dpi(4), time_date },
        time_mon,
        layout = wibox.layout.fixed.horizontal,
        spacing = dpi(1)
    }
    local weather_part = wibox.widget{
        { widget = wibox.container.margin, left = dpi(6), weather_icon },
        weather_temp,
        layout = wibox.layout.fixed.horizontal,
        spacing = dpi(2)
    }

    local content = wibox.widget{
        time_part,
        date_part,
        weather_part,
        layout = wibox.layout.fixed.horizontal,
        spacing = dpi(10)
    }

    return wibox.widget {
        content,
        widget = wibox.container.place,
        halign = "left",
        valign = "center"
    }
end

return sidebar
