 ---------------------------------------------------------------------------
-- Power profiles mode: quick-switch between powersave, balanced, performance.
-- Activated when the prompt text starts with '`'.
---------------------------------------------------------------------------

local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local dpi = beautiful.xresources.apply_dpi
local helpers = require("helpers")

local string = string
local math = math

local power_profiles_mode = {}

local profiles = {
    { label = "powersave",  ppd = "power-saver" },
    { label = "balanced",   ppd = "balanced" },
    { label = "performance", ppd = "performance" }
}

local DBUS_NAME  = "org.freedesktop.UPower.PowerProfiles"
local DBUS_PATH  = "/org/freedesktop/UPower/PowerProfiles"
local DBUS_IFACE = "org.freedesktop.UPower.PowerProfiles"

local current_profile_idx = 2

function power_profiles_mode.create_widget(self)
    local grid = wibox.widget {
        layout = wibox.layout.grid,
        orientation = "vertical",
        homogeneous = true,
        expand = true,
        spacing = dpi(8),
        forced_num_rows = 3,
        forced_num_cols = 1,
        visible = false
    }

    self._private.power_profile_buttons = {}
    self._private.power_profile_textboxes = {}
    self._private.power_profile_selected_row = current_profile_idx

    local accent = beautiful.accent or beautiful.fg_focus or "#ffffff"
    local normal_bg = beautiful.bg_normal or beautiful.bg_2
    local normal_fg = beautiful.fg_normal or beautiful.fg_color

    for i, profile in ipairs(profiles) do
        local btn_text = wibox.widget {
            widget = wibox.widget.textbox,
            markup = helpers.colorize_text(profile.label, i == current_profile_idx and accent or normal_fg),
            font = beautiful.font .. " 10",
            align = "center",
            valign = "center"
        }
        local is_selected = (i == current_profile_idx)
        local btn_container = wibox.widget {
            btn_text,
            widget = wibox.container.background,
            forced_width = dpi(200),
            forced_height = dpi(40),
            bg = is_selected and ((#accent == 7) and (accent .. "22") or accent) or normal_bg,
            shape = helpers.rrect(beautiful.rounded or 4)
        }
        self._private.power_profile_buttons[i] = btn_container
        self._private.power_profile_textboxes[i] = btn_text

        btn_container:connect_signal("button::press", function()
            current_profile_idx = i
            self._private.power_profile_selected_row = i
            power_profiles_mode.update_highlight(self)

            local cmd = "busctl call " .. DBUS_NAME .. " " .. DBUS_PATH .. " " .. DBUS_IFACE .. " HoldProfile sss " .. profile.ppd .. " AwesomeWM awesomewm.power"
            awful.spawn.easy_async_with_shell(cmd, function(stdout)
                local cookie_str = stdout:match("u%s+(%d+)")
                if cookie_str then
                    local state_dir = gears.filesystem.get_configuration_dir() .. "misc/.information"
                    local state_file = state_dir .. "/power_profile_state"
                    os.execute("mkdir -p '" .. state_dir .. "'")
                    local f = io.open(state_file, "w")
                    if f then
                        f:write(profile.ppd .. ":" .. cookie_str)
                        f:close()
                    end
                end
            end)
        end)

        grid:add(btn_container)
    end

    return grid
end

function power_profiles_mode.handle_search(self, text)
    self._private.power_profile_selected_row = current_profile_idx
    power_profiles_mode.update_highlight(self)
end

function power_profiles_mode.update_highlight(self, selected_row)
    selected_row = selected_row or self._private.power_profile_selected_row or current_profile_idx
    local accent = beautiful.accent or beautiful.fg_focus or "#ffffff"
    local normal_bg = beautiful.bg_normal or beautiful.bg_2
    local normal_fg = beautiful.fg_normal or beautiful.fg_color
    for i = 1, #self._private.power_profile_buttons do
        local is_active = (i == selected_row)
        self._private.power_profile_textboxes[i].markup = helpers.colorize_text(profiles[i].label, is_active and accent or normal_fg)
        self._private.power_profile_buttons[i].bg = is_active and ((#accent == 7) and (accent .. "22") or accent) or normal_bg
    end
end

function power_profiles_mode.scroll_up(self)
    local row = self._private.power_profile_selected_row or current_profile_idx
    if row > 1 then
        self._private.power_profile_selected_row = row - 1
        power_profiles_mode.update_highlight(self)
    end
end

function power_profiles_mode.scroll_down(self)
    local row = self._private.power_profile_selected_row or current_profile_idx
    if row < #profiles then
        self._private.power_profile_selected_row = row + 1
        power_profiles_mode.update_highlight(self)
    end
end

function power_profiles_mode.select_active(self)
    local row = self._private.power_profile_selected_row or current_profile_idx
    if row < 1 or row > #profiles then return end

    current_profile_idx = row
    power_profiles_mode.update_highlight(self)

    local profile = profiles[current_profile_idx]
    if profile then
        local cmd = "busctl call " .. DBUS_NAME .. " " .. DBUS_PATH .. " " .. DBUS_IFACE .. " HoldProfile sss " .. profile.ppd .. " AwesomeWM awesomewm.power"
        awful.spawn.easy_async_with_shell(cmd, function(stdout)
            local cookie_str = stdout:match("u%s+(%d+)")
            if cookie_str then
                local state_dir = gears.filesystem.get_configuration_dir() .. "misc/.information"
                local state_file = state_dir .. "/power_profile_state"
                os.execute("mkdir -p '" .. state_dir .. "'")
                local f = io.open(state_file, "w")
                if f then
                    f:write(profile.ppd .. ":" .. cookie_str)
                    f:close()
                end
            end
        end)
    end
end

return power_profiles_mode
