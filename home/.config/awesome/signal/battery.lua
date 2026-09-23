
local upower_widget = require("mods.battery-widget")
local battery_listener = upower_widget {
    device_path = '/org/freedesktop/UPower/devices/battery_BAT1',
    instant_update = true
}

battery_listener:connect_signal("upower::update", function(_, device)
    -- Convert UPower state string to numeric value
    -- 1 = charging, 2 = discharging, 3 = charged, 4 = full
    local state_num = 0
    if device.state then
        if device.state == "charging" then
            state_num = 1
        elseif device.state == "discharging" then
            state_num = 2
        elseif device.state == "charged" then
            state_num = 3
        elseif device.state == "full" then
            state_num = 4
        end
    end
    awesome.emit_signal("signal::battery", math.floor(device.percentage), state_num)
end)
