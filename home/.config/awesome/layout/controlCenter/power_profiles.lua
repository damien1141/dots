-- Power profiles control bar (tlp-pd + busctl + state file + xrandr)
-- Three buttons: LOW (power-saver), MED (balanced), HIGH (performance)
-----------------------------------
local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local dpi = beautiful.xresources.apply_dpi
local helpers = require("helpers")
local wibox = require("wibox")
local lgi = require("lgi")
local Gio = lgi.Gio

local profiles = {
    { label = "低",  ppd = "power-saver" },
    { label = "中",  ppd = "balanced" },
    { label = "高", ppd = "performance" }
}

local current_profile_idx = 2
local power_buttons = {}
local textboxes = {}
local current_cookie = nil  -- Tracks the D-Bus hold cookie

-- Pre-declare functions to avoid ordering issues
local update_profile_highlight
local apply_profile
local async_get_profile
local async_set_profile
local apply_refresh_rate

-- tlp-pd implements this specific D-Bus interface
local DBUS_NAME  = "org.freedesktop.UPower.PowerProfiles"
local DBUS_PATH  = "/org/freedesktop/UPower/PowerProfiles"
local DBUS_IFACE = "org.freedesktop.UPower.PowerProfiles"

-- State file for persistence across AwesomeWM restarts
local state_dir  = gears.filesystem.get_configuration_dir() .. "misc/.information"
local state_file = state_dir .. "/power_profile_state"

----------------------------------------------------------
-- 1. State File Helpers
----------------------------------------------------------
local function ensure_state_dir()
    os.execute("mkdir -p '" .. state_dir .. "'")
end

local function read_state_file()
    local f = io.open(state_file, "r")
    if not f then return nil end
    local line = f:read("*l")
    f:close()
    if not line then return nil end
    line = line:match("^%s*(.-)%s*$") -- trim whitespace
    return line ~= "" and line or nil
end

local function write_state_file(data)
    local f = io.open(state_file, "w")
    if f then
        f:write(data)
        f:close()
    end
end

----------------------------------------------------------
-- 2. Core Profile Logic & Refresh Rate
----------------------------------------------------------
update_profile_highlight = function()
    local accent = beautiful.accent or beautiful.fg_focus or "#ffffff"
    for i = 1, #power_buttons do
        if i == current_profile_idx then
            textboxes[i].markup = helpers.colorize_text(profiles[i].label,
                beautiful.fg_color)
            power_buttons[i].bg = beautiful.accent_transparent or ((#accent == 7) and (accent .. "22")) or accent
        else
            textboxes[i].markup = helpers.colorize_text(profiles[i].label,
                beautiful.fg_normal or beautiful.fg_color)
            power_buttons[i].bg = beautiful.bg_frost_3 or beautiful.bg_normal or beautiful.bg_2
        end
    end
end

-- Applies the xrandr commands based on profile
apply_refresh_rate = function(profile_name)
    local cmd = nil
    if profile_name == "performance" then
        -- 90hz (technically 91)
        cmd = [[
            xrandr --newmode "2240x1400_91.00" 415.00  2240 2424 2664 3088  1400 1403 1409 1477 -hsync +vsync 2>/dev/null
            xrandr --addmode eDP-1 "2240x1400_91.00"
            xrandr --output eDP-1 --mode "2240x1400_91.00" --pos 160x1440
            xrandr --output HDMI-1-0 --primary --mode 2560x1440 --pos 0x0 --rotate normal
        ]]
    else
        -- 48hz (technically 49) for balanced and power-saver
        cmd = [[
            xrandr --newmode "2240x1400_49rb" 207.50  2240 2320 2552 2864  1400 1403 1409 1476 +hsync -vsync 2>/dev/null
            xrandr --addmode eDP-1 "2240x1400_49.00"
            xrandr --output eDP-1 --mode "2240x1400_49.00"
        ]]
    end

    if cmd then
        awful.spawn.with_shell(cmd)
    end
end

-- apply_profile updates the UI and triggers refresh rate change
apply_profile = function(profile_name)
    if not profile_name or profile_name == "" then return end

    local new_idx = 2
    for i, p in ipairs(profiles) do
        if p.ppd == profile_name then
            new_idx = i
            break
        end
    end

    -- Only update UI and refresh rate if the profile actually changed
    if current_profile_idx ~= new_idx then
        current_profile_idx = new_idx
        update_profile_highlight()
        apply_refresh_rate(profile_name)
    end
end

----------------------------------------------------------
-- 3. TLP-PD D-Bus Communication (via busctl for reliability)
----------------------------------------------------------
async_get_profile = function(callback)
    local cmd = "busctl get-property " .. DBUS_NAME .. " " .. DBUS_PATH .. " " .. DBUS_IFACE .. " ActiveProfile 2>/dev/null"
    awful.spawn.easy_async_with_shell(cmd, function(stdout)
        -- busctl returns: s "balanced"
        local profile = stdout:match('"([^"]+)"')
        callback(profile and profile ~= "" and profile or nil)
    end)
end

async_set_profile = function(profile_name)
    if not profile_name or profile_name == "" then return end

    local function hold_new_profile()
        -- Standard PPD/tlp-pd uses HoldProfile to change the profile
        local cmd = "busctl call " .. DBUS_NAME .. " " .. DBUS_PATH .. " " .. DBUS_IFACE .. " HoldProfile sss " .. profile_name .. " AwesomeWM awesomewm.power"
        awful.spawn.easy_async_with_shell(cmd, function(stdout)
            -- busctl returns: u <cookie_number>
            local cookie_str = stdout:match("u%s+(%d+)")
            if cookie_str then
                current_cookie = tonumber(cookie_str)
                -- Save profile AND cookie so we can cleanly release it on restart
                write_state_file(profile_name .. ":" .. tostring(current_cookie))
            else
                -- Fallback: try setting property directly (in case tlp-pd allows it)
                local cmd2 = "busctl set-property " .. DBUS_NAME .. " " .. DBUS_PATH .. " " .. DBUS_IFACE .. " ActiveProfile s " .. profile_name
                awful.spawn.easy_async_with_shell(cmd2, function()
                    write_state_file(profile_name)
                end)
            end
        end)
    end

    -- If we have an active cookie, release it first to prevent stacking holds
    if current_cookie then
        local release_cmd = "busctl call " .. DBUS_NAME .. " " .. DBUS_PATH .. " " .. DBUS_IFACE .. " ReleaseProfile u " .. tostring(current_cookie)
        awful.spawn.easy_async_with_shell(release_cmd, function()
            current_cookie = nil
            hold_new_profile()
        end)
    else
        hold_new_profile()
    end
end

----------------------------------------------------------
-- 4. Build UI
----------------------------------------------------------
for i, profile in ipairs(profiles) do
    local btn_text = wibox.widget{
        widget = wibox.widget.textbox,
        markup = helpers.colorize_text(profile.label, beautiful.fg),
        font = beautiful.font .. " 10",
        align = "center",
        valign = "center",
    }
    local btn_container = wibox.widget{
        btn_text,
        widget = wibox.container.background,
        forced_width = dpi(100),
        forced_height = dpi(40),
        bg = beautiful.bg_frost_3 or beautiful.bg_normal or beautiful.bg_2,
        shape = helpers.rrect(beautiful.rounded or 4),
    }
    power_buttons[#power_buttons + 1] = btn_container
    textboxes[#textboxes + 1] = btn_text
end

-- Click handlers
for i, profile in ipairs(profiles) do
    power_buttons[i]:connect_signal("button::press", function(_, _, _, button_id)
        if button_id == 1 then
            -- 1. Optimistic UI & Refresh Rate update for instant feedback
            current_profile_idx = i
            update_profile_highlight()
            apply_refresh_rate(profile.ppd)

            -- 2. Actually set it in the background
            async_set_profile(profile.ppd)
        end
    end)
end

local power_profiles_bar = wibox.widget{
    {
        {
            power_buttons[1], power_buttons[2], power_buttons[3],
            layout = wibox.layout.fixed.horizontal,
            spacing = dpi(14),
        },
        widget = wibox.container.margin,
        margins = { top = dpi(5), bottom = dpi(5) },
    },
    widget = wibox.container.margin,
    margins = { left = dpi(5), right = dpi(5) },
}

----------------------------------------------------------
-- 5. Initialization & Live Signal Listener
----------------------------------------------------------
ensure_state_dir()

local function initialize()
    local saved = read_state_file() or "balanced"
    local saved_profile = "balanced"
    local old_cookie = nil

    -- Parse "profile:cookie" format from state file
    if saved then
        local p, c = saved:match("^(.-):(%d+)$")
        if p and c then
            saved_profile = p
            old_cookie = tonumber(c)
        else
            saved_profile = saved
        end
    end

    -- Force apply_profile to trigger on startup
    -- (prevents it from skipping the xrandr command if default is balanced)
    current_profile_idx = -1
    apply_profile(saved_profile)

    local function hold_profile()
        async_set_profile(saved_profile)
    end

    if old_cookie then
        -- Try to release old cookie to prevent leaking holds across AwesomeWM restarts
        local release_cmd = "busctl call " .. DBUS_NAME .. " " .. DBUS_PATH .. " " .. DBUS_IFACE .. " ReleaseProfile u " .. tostring(old_cookie)
        awful.spawn.easy_async_with_shell(release_cmd, function()
            hold_profile()
        end)
    else
        hold_profile()
    end
end

-- Listen for external changes (e.g., switched via CLI or GNOME settings)
local ok, system_bus = pcall(Gio.bus_get_sync, Gio.BusType.SYSTEM, nil)
if ok and system_bus then
    local ok2, p = pcall(Gio.DBusProxy.new_sync, system_bus,
        Gio.DBusProxyFlags.GET_INVALIDATED_PROPERTIES, nil,
        DBUS_NAME, DBUS_PATH, DBUS_IFACE, nil)

    if ok2 and p then
        p.on_g_properties_changed = function(_, changed, invalidated)
            local needs_update = false
            if changed then
                local val = changed:lookup("ActiveProfile")
                if val then
                    apply_profile(val:get_string())
                    return
                end
            end
            if invalidated then
                local n = invalidated:n_children()
                for i = 0, n - 1 do
                    if invalidated:get_child_value(i):get_string() == "ActiveProfile" then
                        needs_update = true
                        break
                    end
                end
            end
            if needs_update then
                async_get_profile(function(new_profile)
                    if new_profile then apply_profile(new_profile) end
                end)
            end
        end
    end
end

initialize()
update_profile_highlight()

return power_profiles_bar
