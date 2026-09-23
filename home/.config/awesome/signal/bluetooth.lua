-- OPTIMIZED: Consolidated two separate watch calls into one single watcher
-- This reduces shell spawns from 2 to 1 per interval cycle
-- requirements
local awful = require("awful")

-- update interval
local update_interval = 10

-- Single consolidated command to fetch both power state and devices
local bluetooth_cmd = [[
  bash -c "
  echo 'POWER:'\$(bluetoothctl show | grep 'Powered:' | awk '{ print $2 }')
  echo 'DEVICES:'\$(bluetoothctl devices)
  "
]]

awful.widget.watch(bluetooth_cmd, update_interval, function(_, stdout)
    -- Parse power state
    local power_line = stdout:match('POWER:(.-)DEVICES')
    local output = string.gsub(power_line, '^%s*(.-)%s*$', '%1')
    local bluetooth_active = true
    local bluetooth_running_service

    -- Check if bluetooth.service is enabled
    awful.spawn.easy_async_with_shell("bash -c 'pgrep bluetooth'", function (lets_see)
        if lets_see == "" then
            bluetooth_running_service = false
        else
            bluetooth_running_service = true
        end

        -- Set output based on the above info
        if output == "no" then
            bluetooth_active = bluetooth_running_service
        end

        -- Emit the signal (powered on?, is the process running?)
        awesome.emit_signal("signal::bluetooth", bluetooth_active, bluetooth_running_service)
    end)

    -- Parse devices (now in same watcher)
    local devices = {}
    local devices_line = stdout:match('DEVICES:(.*)')
    if devices_line then
        local lines = {}
        for line in devices_line:gmatch("[^\r\n]+") do
            table.insert(lines, line)
        end

        -- Parse the output to get connected devices
        for i, line in ipairs(lines) do
            if i > 1 then -- Skip the first line (header)
                local address, name = line:match("(%S+)%s+(.+)")
                table.insert(devices, {address = address, name = name})
            end
        end
    end

    -- Emit the signal with the connected devices
    awesome.emit_signal("signal::bluetooth_devices", devices)
end)
