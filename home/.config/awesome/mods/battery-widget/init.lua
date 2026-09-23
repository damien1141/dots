---------------------------------------------------------------------------
-- Sysfs battery widget for AwesomeWM.
-- No UPowerGlib/lgi required. Auto-detects batteries, including
-- BAT0/BAT1/macsmc-battery on MacBooks.
---------------------------------------------------------------------------

local wibox = require("wibox")
local wbase = require("wibox.widget.base")
local gears = require("gears")

local battery_widget = {}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function read_str(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    if not s then return nil end
    return trim(s)
end

local function read_num(path)
    local s = read_str(path)
    return s and tonumber(s) or nil
end

local function magnitude(n)
    if not n or n ~= n then return nil end
    if n == math.huge or n == -math.huge then return nil end
    n = math.abs(n)
    if n == 0 then return nil end
    return n
end

local function list_power_supplies()
    local names = {}
    local p = io.popen("ls -1 /sys/class/power_supply 2>/dev/null")
    if not p then return names end
    for name in p:lines() do
        name = trim(name)
        if name ~= "" then
            table.insert(names, name)
        end
    end
    p:close()
    return names
end

local function is_battery_dir(dir)
    local t = read_str(dir .. "/type")
    return t ~= nil and t:lower() == "battery"
end

local function is_ac_dir(dir)
    local t = read_str(dir .. "/type")
    if not t then return false end
    t = t:lower()
    return t == "mains" or t == "usb" or t == "wireless"
end

local function normalize_ps_name(s)
    return (s:upper():gsub("[%-_]", ""))
end

local function preferred_matches(name, preferred)
    if not preferred or preferred == "" then
        return false
    end

    local n = name:upper()
    local p = preferred:upper()

    if n == p then
        return true
    end

    if normalize_ps_name(name) == normalize_ps_name(preferred) then
        return true
    end

    local last = preferred:match("([^/]+)/?$")
    if last then
        local l = last:upper()

        if n == l then
            return true
        end

        if normalize_ps_name(name) == normalize_ps_name(last) then
            return true
        end

        local stripped = l:match("^BATTERY_(.+)$")
        if stripped then
            if n == stripped then
                return true
            end

            if normalize_ps_name(name) == normalize_ps_name(stripped) then
                return true
            end
        end
    end

    local batnum = p:match("BAT(%d+)")
    if batnum and n:match("BAT" .. batnum) then
        return true
    end

    return false
end

local function find_battery(preferred)
    local base = "/sys/class/power_supply/"
    local supplies

    if preferred and preferred ~= "" then
        if preferred:sub(1, 1) == "/" then
            if is_battery_dir(preferred) then
                return preferred
            end
        else
            local dir = base .. preferred
            if is_battery_dir(dir) then
                return dir
            end
        end

        supplies = list_power_supplies()
        for _, name in ipairs(supplies) do
            if preferred_matches(name, preferred) then
                local dir = base .. name
                if is_battery_dir(dir) then
                    return dir
                end
            end
        end
    end

    local known = {
        "BAT0", "BAT1", "BAT2", "BATT",
        "battery", "Battery",
        "macsmc-battery", "macsmc_battery",
    }

    for _, name in ipairs(known) do
        local dir = base .. name
        if is_battery_dir(dir) then
            return dir
        end
    end

    supplies = supplies or list_power_supplies()
    for _, name in ipairs(supplies) do
        local dir = base .. name
        if is_battery_dir(dir) then
            return dir
        end
    end

    return nil
end

local function find_ac()
    local base = "/sys/class/power_supply/"

    local known = {
        "AC", "ACAD", "ADP0", "ADP1", "AC0", "AC1",
        "USB", "UCSI", "TCPM",
        "macsmc-ac", "macsmc_ac",
    }

    for _, name in ipairs(known) do
        local dir = base .. name
        if is_ac_dir(dir) then
            return dir
        end
    end

    for _, name in ipairs(list_power_supplies()) do
        local dir = base .. name
        if is_ac_dir(dir) then
            return dir
        end
    end

    return nil
end

local function to_clock(seconds)
    seconds = tonumber(seconds) or 0
    if seconds <= 0 or seconds ~= seconds or seconds == math.huge then
        return "00:00"
    end

    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    return string.format("%02d:%02d", h, m)
end

local function clamp_percent(p)
    if not p or p ~= p then return nil end
    if p < 0 then return 0 end
    if p > 100 then return 100 end
    return p
end

local function get_info(bat_dir, ac_dir)
    local info = {
        present = false,
        percentage = nil,
        status = "Unknown",
        state = "unknown",
        ac_online = false,
        charging = false,
        discharging = false,
        full = false,
        seconds = nil,
        time_text = "",
    }

    if ac_dir and is_ac_dir(ac_dir) then
        info.ac_online = read_num(ac_dir .. "/online") == 1
    end

    if not bat_dir or not is_battery_dir(bat_dir) then
        return info
    end

    local present = read_num(bat_dir .. "/present")
    if present == 0 then
        return info
    end

    info.present = true

    local status = read_str(bat_dir .. "/status")
    info.status = (status and status ~= "") and status or "Unknown"
    info.state = info.status:lower()

    local charging_found = info.state:find("charging", 1, true) ~= nil
    local discharging_found = info.state:find("discharging", 1, true) ~= nil
    local not_charging = info.state:find("not charging", 1, true) ~= nil

    info.discharging = discharging_found
    info.charging = charging_found and not discharging_found and not not_charging
    info.full = info.state:find("full", 1, true) ~= nil

    if info.charging or not_charging then
        info.ac_online = true
    end

    info.percentage = clamp_percent(read_num(bat_dir .. "/capacity"))

    local energy_now = read_num(bat_dir .. "/energy_now")
    local energy_full = read_num(bat_dir .. "/energy_full")
        or read_num(bat_dir .. "/energy_full_design")

    local charge_now = read_num(bat_dir .. "/charge_now")
    local charge_full = read_num(bat_dir .. "/charge_full")
        or read_num(bat_dir .. "/charge_full_design")

    local power_now = magnitude(read_num(bat_dir .. "/power_now"))
    local current_now = magnitude(read_num(bat_dir .. "/current_now"))
    local voltage_now = magnitude(read_num(bat_dir .. "/voltage_now"))

    local time_to_full = magnitude(read_num(bat_dir .. "/time_to_full_now"))
    local time_to_empty = magnitude(read_num(bat_dir .. "/time_to_empty_now"))

    if not power_now and current_now and voltage_now then
        -- µA * µV / 1e6 = µW
        power_now = current_now * voltage_now / 1e6
    end

    if power_now and (power_now ~= power_now or power_now == math.huge or power_now == 0) then
        power_now = nil
    end

    if not info.percentage then
        if energy_now and energy_full and energy_full > 0 then
            info.percentage = clamp_percent(math.floor((energy_now / energy_full) * 100 + 0.5))
        elseif charge_now and charge_full and charge_full > 0 then
            info.percentage = clamp_percent(math.floor((charge_now / charge_full) * 100 + 0.5))
        end
    end

    if info.percentage then
        info.percentage = clamp_percent(math.floor(info.percentage + 0.5))
    end

    -- Some drivers report status as Unknown. Try to infer direction.
    if info.status == "Unknown" and not info.charging and not info.discharging and not info.full then
        if time_to_full and not time_to_empty then
            info.charging = true
            info.state = "charging"
            info.ac_online = true
        elseif time_to_empty and not time_to_full then
            info.discharging = true
            info.state = "discharging"
        elseif power_now or current_now then
            if info.ac_online then
                info.charging = true
                info.state = "charging"
            else
                info.discharging = true
                info.state = "discharging"
            end
        end
    end

    local seconds

    if info.charging then
        seconds = time_to_full

        if not seconds then
            if energy_now and energy_full and power_now and energy_full > energy_now then
                seconds = ((energy_full - energy_now) / power_now) * 3600
            elseif charge_now and charge_full and current_now and charge_full > charge_now then
                seconds = ((charge_full - charge_now) / current_now) * 3600
            end
        end
    elseif info.discharging then
        seconds = time_to_empty

        if not seconds then
            if energy_now and power_now then
                seconds = (energy_now / power_now) * 3600
            elseif charge_now and current_now then
                seconds = (charge_now / current_now) * 3600
            end
        end
    end

    if seconds and seconds > 0 and seconds < 48 * 3600 then
        info.seconds = math.floor(seconds + 0.5)

        if info.charging then
            info.time_text = string.format(" (%s to full)", to_clock(info.seconds))
        elseif info.discharging then
            info.time_text = string.format(" (%s left)", to_clock(info.seconds))
        end
    end

    return info
end

local function default_format(info)
    if not info.present then
        return info.ac_online and "AC" or "no battery"
    end

    local pct = info.percentage and string.format("%d%%", info.percentage) or "?%"

    local icon = "BAT"
    if info.ac_online and not info.discharging then
        icon = "AC"
    end

    if info.percentage and info.percentage <= 20 and info.discharging then
        icon = "LOW"
    end

    local state
    if info.discharging then
        state = "discharging"
    elseif info.full or (info.ac_online and info.percentage == 100) then
        state = "full"
    elseif info.charging then
        state = "charging"
    elseif info.ac_online then
        state = "ac"
    else
        state = info.status:lower()
    end

    if state == "ac" then
        state = ""
    end

    local state_text = state ~= "" and (" " .. state) or ""
    return string.format("%s %s%s%s", icon, pct, state_text, info.time_text)
end

battery_widget.default_format = default_format
battery_widget.to_clock = to_clock

function battery_widget.list_devices()
    local base = "/sys/class/power_supply/"
    local ret = {}
    for _, name in ipairs(list_power_supplies()) do
        table.insert(ret, base .. name)
    end
    return ret
end

function battery_widget.get_BAT0_device_path()
    return find_battery("") or ""
end

function battery_widget.get_device(path)
    local dir = find_battery(path)
    if not dir then
        return nil
    end
    return get_info(dir, find_ac())
end

function battery_widget.new(args)
    if type(args) == "string" then
        args = { device = args }
    else
        args = args or {}
    end

    if type(args) ~= "table" then
        args = {}
    end

    local timeout = tonumber(args.timeout)
    if not timeout or timeout ~= timeout or timeout == math.huge or timeout <= 0 then
        timeout = 10
    end

    local preferred = ""
    if args.device ~= nil and args.device ~= false and args.device ~= "" then
        preferred = tostring(args.device)
    elseif args.device_path ~= nil and args.device_path ~= false and args.device_path ~= "" then
        preferred = tostring(args.device_path)
    end

    local bat_dir = find_battery(preferred)
    local ac_dir = find_ac()

    local widget
    if args.widget_template then
        widget = wbase.make_widget_from_value(args.widget_template)
    else
        widget = wibox.widget.textbox()
        widget:set_text("...")
    end

    local fake_device = {}

    fake_device.get_object_path = function(self)
        self = self or fake_device
        return self.native_path or ""
    end

    fake_device.get_native_path = function(self)
        self = self or fake_device
        return self.native_path or ""
    end

    fake_device.refresh_sync = function()
        return true
    end

    fake_device.refresh = function(self, callback)
        if type(self) == "function" then
            callback = self
        end
        if type(callback) == "function" then
            pcall(callback, true)
        end
        return true
    end

    fake_device.present = false
    fake_device.is_present = false
    fake_device.percentage = 0.0
    fake_device.state = 0.0
    fake_device.state_string = "unknown"
    fake_device.status = "Unknown"
    fake_device.online = false
    fake_device.is_rechargeable = true
    fake_device.kind = 1
    fake_device.kind_string = "battery"
    fake_device.native_path = ""
    fake_device.object_path = ""
    fake_device.time_to_full = 0.0
    fake_device.time_to_empty = 0.0
    fake_device.time_text = ""
    fake_device.seconds = nil
    fake_device.update_time = os.time()

    rawset(widget, "device", fake_device)

    local format = type(args.format) == "function" and args.format or default_format
    local auto_text = args.widget_template == nil or (args.auto_text and true or false)
    local use_markup = args.markup and true or false

    local function set_text(text)
        if use_markup and widget.set_markup then
            widget:set_markup(tostring(text))
        elseif widget.set_text then
            widget:set_text(tostring(text))
        end
    end

    local function update()
        if not bat_dir or not is_battery_dir(bat_dir) then
            bat_dir = find_battery(preferred)
        end

        if not ac_dir or not is_ac_dir(ac_dir) then
            ac_dir = find_ac()
        end

        local info = get_info(bat_dir, ac_dir)

        -- UPower-like state numbers:
        -- 0 unknown, 1 charging, 2 discharging, 4 fully charged
        local state_num = 0.0
        if info.discharging then
            state_num = 1
        elseif info.full or (info.ac_online and info.percentage == 100) then
            state_num = 1
        elseif info.charging then
            state_num = 1
        end

        fake_device.present = info.present
        fake_device.is_present = info.present
        fake_device.percentage = info.percentage or 0
        fake_device.state = state_num
        fake_device.state_string = info.state
        fake_device.status = info.status
        fake_device.online = info.ac_online
        fake_device.is_rechargeable = true
        fake_device.kind = 1
        fake_device.kind_string = "battery"
        fake_device.native_path = bat_dir or ""
        fake_device.object_path = bat_dir or ""
        fake_device.time_to_full = info.charging and info.seconds or 0
        fake_device.time_to_empty = info.discharging and info.seconds or 0
        fake_device.time_text = info.time_text
        fake_device.seconds = info.seconds
        fake_device.update_time = os.time()

        rawset(widget, "battery_info", info)

        if auto_text then
            local ok, text = pcall(format, info, widget)
            if ok and (type(text) == "string" or type(text) == "number") then
                pcall(set_text, text)
            end
        end

        widget:emit_signal("battery::update", info)
        widget:emit_signal("upower::update", fake_device)

        if type(fake_device.on_notify) == "function" then
            pcall(fake_device.on_notify, fake_device)
        end
    end

    local timer = gears.timer {
        timeout = timeout,
        autostart = false,
        callback = update,
    }

    rawset(widget, "battery_timer", timer)
    rawset(widget, "update_battery", update)

    update()
    timer:start()

    if args.instant_update ~= false then
        gears.timer.delayed_call(update)
    end

    return widget
end

return setmetatable(battery_widget, {
    __call = function(_, ...)
        return battery_widget.new(...)
    end,
})