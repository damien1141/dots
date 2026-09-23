-- time
--------
-- Copyleft © 2022 Saimoomedits

-- requirements
---------------
local beautiful = require("beautiful")
local dpi = beautiful.xresources.apply_dpi
local wibox = require("wibox")
local helpers = require("helpers")
local gears = require("gears")
local awful = require("awful")

-- Weather Widget (Open-Meteo)
-- Place this in your wibar next to the clock/date
-----------------------------------

-- ⚙️ CONFIG: Set your Lat/Lon (find yours at https://open-meteo.com/)
local LAT = user_likes.lat or 9.099724
local LON = user_likes.lon or -94.578331

-- Temperature unit toggle (true = Fahrenheit, false = Celsius)
local USE_FAHRENHEIT = true
local function get_weather_emoji(code)
    -- Ensure the code is a number
    code = tonumber(code)
    if not code then return "☁️❓" end

    -- Lookup table for Open-Meteo WMO Weather interpretation codes
    -- https://open-meteo.com/en/docs
    local weather_map = {
        [0]  = "☀️",   -- Clear sky
        [1]  = "🌤️",   -- Mainly clear
        [2]  = "⛅",   -- Partly cloudy
        [3]  = "☁️",   -- Overcast
        
        [45] = "🌫️",   -- Fog
        [48] = "🌫️",   -- Depositing rime fog
        
        [51] = "🌦️",   -- Light drizzle
        [53] = "🌦️",   -- Moderate drizzle
        [55] = "🌧️",   -- Dense drizzle
        [56] = "🌨️",   -- Light freezing drizzle
        [57] = "🌨️",   -- Dense freezing drizzle
        
        [61] = "🌧️",   -- Slight rain
        [63] = "🌧️",   -- Moderate rain
        [65] = "🌧️",   -- Heavy rain
        [66] = "🌨️",   -- Light freezing rain
        [67] = "🌨️",   -- Heavy freezing rain
        
        [71] = "🌨️",   -- Slight snow fall
        [73] = "🌨️",   -- Moderate snow fall
        [75] = "❄️",   -- Heavy snow fall
        [77] = "❄️",   -- Snow grains
        
        [80] = "🌦️",   -- Slight rain showers
        [81] = "🌧️",   -- Moderate rain showers
        [82] = "⛈️",   -- Violent rain showers
        
        [85] = "🌨️",   -- Slight snow showers
        [86] = "❄️",   -- Heavy snow showers
        
        [95] = "⛈️",   -- Thunderstorm: Slight or moderate
        [96] = "⛈️",   -- Thunderstorm with slight hail
        [99] = "⛈️",   -- Thunderstorm with heavy hail
    }

    return weather_map[code] or "❓"
end

-- Use fallback fonts if beautiful variables aren't defined
local font_normal = beautiful.font_var or beautiful.font or "Sans 11"
local font_bold = beautiful.font_var and (beautiful.font_var .. " Bold 13") or 
                  (beautiful.font and (beautiful.font .. " Bold 13")) or 
                  "Sans Bold 13"
local font_icon = beautiful.icon_var or beautiful.font or "Sans 13"

-- Weather widget components
local weather_icon = wibox.widget{
    font = font_icon,
    markup = helpers.colorize_text("⛅ ", beautiful.fg_normal or beautiful.fg_color or "#ffffff"),
    widget = wibox.widget.textbox,
    align = "center",
    valign = "center",
}

local weather_temp = wibox.widget{
    font = font_bold,
    markup = helpers.colorize_text("--°F", beautiful.fg_normal or beautiful.fg_color or "#ffffff"),
    widget = wibox.widget.textbox,
    align = "center",
    valign = "center",
}

-- Fix 2: Better JSON parsing with debug output
local function update_weather()
    local url = string.format(
        "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current_weather=true&units=metric",
        LAT, LON
    )

    awful.spawn.easy_async({"curl", "-s", url}, function(stdout)
        -- Debug: print the raw response
        -- print("Weather API response:", stdout)
        
        -- More robust JSON parsing
        local temp_match = stdout:match('"temperature":%s*(-?%d+%.?%d*)')
        local code_match = stdout:match('"weathercode":%s*(%d+)')
        
        if not temp_match or not code_match then
            weather_temp.markup = helpers.colorize_text("ERR", beautiful.fg_error or "#ff0000")
            weather_icon.markup = helpers.colorize_text("❓", beautiful.fg_error or "#ff0000")
            return
        end

        -- Convert Celsius to Fahrenheit: °F = (°C × 9/5) + 32
        local temp_c = tonumber(temp_match)
        local temp_display
        
        if USE_FAHRENHEIT then
            -- Convert Celsius to Fahrenheit: °F = (°C × 9/5) + 32
            temp_display = math.floor(temp_c * 9 / 5 + 32)
        else
            temp_display = math.floor(temp_c)
        end
        
        local code = tonumber(code_match)
        local icon = get_weather_emoji(code)

        weather_icon.markup = helpers.colorize_text(icon, beautiful.accent or beautiful.fg_focus or "#ffffff")
        weather_temp.markup = helpers.colorize_text(temp_display .. (USE_FAHRENHEIT and "°F" or "°C"), beautiful.fg_normal or beautiful.fg_color or "#ffffff")
    end)
end

-- Update every 30 minutes (1800 seconds)
gears.timer.new {
    timeout   = 1800,
    callback  = update_weather,
    autostart = true,
}

-- Initial fetch
update_weather()

-- Set Spanish locale for time formatting (with error handling)
local success, err = pcall(function()
    os.setlocale("es_ES.UTF-8")
end)
if not success then
    -- Fallback to C locale if Spanish is not available
    os.setlocale("C")
end

-- widgets
----------

-- small font for the date lines
local font_small = (beautiful.font_var or beautiful.font or "Sans") .. " 9"

-- hour text
local time_hour = wibox.widget{
    font = font_bold,
    format = "%H",
    widget = wibox.widget.textclock
}

-- minute text
local time_min = wibox.widget{
    font = font_bold,
    format = "%M",
    widget = wibox.widget.textclock
}

-- weekday text
local time_day = wibox.widget{
    font = font_small,
    format = "%a,",
    widget = wibox.widget.textclock
}

-- date + month text
local time_date = wibox.widget{
    font = font_small,
    format = "%d %b",
    widget = wibox.widget.textclock
}

-- Apply colors to textclock widgets after creation
local fg_color = beautiful.fg_color or "#ffffff"
local fg_dim = fg_color .. "88"

time_hour.markup = helpers.colorize_text(time_hour.text, fg_color)
time_min.markup = helpers.colorize_text(time_min.text, fg_dim)
time_day.markup = helpers.colorize_text(time_day.text, fg_dim)
time_date.markup = helpers.colorize_text(time_date.text, fg_dim)

-- Update markup when text changes (textclock updates automatically)
time_hour:connect_signal("widget::redraw_needed", function()
    time_hour.markup = helpers.colorize_text(time_hour.text, fg_color)
end)
time_min:connect_signal("widget::redraw_needed", function()
    time_min.markup = helpers.colorize_text(time_min.text, fg_dim)
end)
time_day:connect_signal("widget::redraw_needed", function()
    time_day.markup = helpers.colorize_text(time_day.text, fg_dim)
end)
time_date:connect_signal("widget::redraw_needed", function()
    time_date.markup = helpers.colorize_text(time_date.text, fg_dim)
end)

-- indicator for dashboard
local indicator = wibox.widget{
    widget = wibox.container.background,
    bg = (beautiful.fg_color or "#ffffff") .. "4D",
    forced_height = dpi(2),
    visible = false
}

-- center each line in a fixed-width row so the stack lines up
local function vrow(w)
    return { w, widget = wibox.container.place, forced_width = dpi(46) }
end

-- thin horizontal divider between groups
local function vsep()
    return vrow(wibox.widget{
        widget = wibox.container.background,
        bg = fg_color .. "22",
        forced_width = dpi(28),
        forced_height = dpi(1),
    })
end

-- grouped blocks
local clock_block = wibox.widget{
    vrow(time_hour),
    vrow(time_min),
    spacing = dpi(2),
    layout = wibox.layout.fixed.vertical
}

local date_block = wibox.widget{
    vrow(time_day),
    vrow(time_date),
    spacing = dpi(2),
    layout = wibox.layout.fixed.vertical
}

local weather_block = wibox.widget{
    vrow(weather_icon),
    vrow(weather_temp),
    spacing = dpi(3),
    layout = wibox.layout.fixed.vertical
}

-- main box
local widget_box = wibox.widget{
    {
        {
            nil, nil, indicator,
            layout = wibox.layout.align.vertical
        },
        {
            {
                clock_block,
                vsep(),
                date_block,
                vsep(),
                weather_block,
                spacing = dpi(10),
                layout = wibox.layout.fixed.vertical,
            },
            margins = {left = dpi(4), right = dpi(4), top = dpi(12), bottom = dpi(12)},
            widget = wibox.container.margin
        },
        layout = wibox.layout.stack
    },
    widget = wibox.container.background,
    shape = helpers.rrect(beautiful.rounded - 2),
    shape_border_width = dpi(1),
    shape_border_color = fg_color .. "1A",
    bg = beautiful.bg_frost_2
}

-- effects
----------

-- hover
widget_box:connect_signal("mouse::enter", function ()
    widget_box.bg = (beautiful.fg_color or "#ffffff") .. "26"
end)
widget_box:connect_signal("mouse::leave", function ()
    widget_box.bg = beautiful.bg_frost_2
end)

-- press
widget_box:connect_signal("button::press", function()
    widget_box.opacity = 0.6
    -- Check if dd_toggle exists before calling
    if dd_toggle then
        dd_toggle()
    end
end)
widget_box:connect_signal("button::release", function()
    widget_box.opacity = 1
end)

-- update indicator status
awesome.connect_signal("dashboard::visible", function(val)
    if val then
        indicator.visible = true
    else
        indicator.visible = false
    end
end)

-- finalize
-----------
return widget_box

-- eof
------