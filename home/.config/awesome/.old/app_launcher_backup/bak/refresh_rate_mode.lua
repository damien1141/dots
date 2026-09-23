 ---------------------------------------------------------------------------
-- Refresh rate mode: quick-switch between display refresh rates.
-- Activated when the prompt text starts with '~'.
-- Replace the placeholder xrandr commands in select_active().
---------------------------------------------------------------------------

local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local dpi = beautiful.xresources.apply_dpi
local helpers = require("helpers")

local string = string
local math = math

local refresh_rate_mode = {}

local profiles = {
    { label = "60hz",  cmd = nil },
    { label = "120hz", cmd = nil },
    { label = "144hz", cmd = nil }
}

local current_profile_idx = 1

function refresh_rate_mode.create_widget(self)
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

    self._private.refresh_rate_buttons = {}
    self._private.refresh_rate_textboxes = {}
    self._private.refresh_rate_selected_row = current_profile_idx

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
        self._private.refresh_rate_buttons[i] = btn_container
        self._private.refresh_rate_textboxes[i] = btn_text

        btn_container:connect_signal("button::press", function()
            current_profile_idx = i
            self._private.refresh_rate_selected_row = i
            refresh_rate_mode.update_highlight(self)

            local cmd = profiles[i].cmd
            if cmd then
                awful.spawn.easy_async_with_shell(cmd, function(stdout, stderr)
                    -- xrandr commands are fire-and-forget
                end)
            end
        end)

        grid:add(btn_container)
    end

    return grid
end

function refresh_rate_mode.handle_search(self, text)
    self._private.refresh_rate_selected_row = current_profile_idx
    refresh_rate_mode.update_highlight(self)
end

function refresh_rate_mode.update_highlight(self, selected_row)
    selected_row = selected_row or self._private.refresh_rate_selected_row or current_profile_idx
    local accent = beautiful.accent or beautiful.fg_focus or "#ffffff"
    local normal_bg = beautiful.bg_normal or beautiful.bg_2
    local normal_fg = beautiful.fg_normal or beautiful.fg_color
    for i = 1, #self._private.refresh_rate_buttons do
        local is_active = (i == selected_row)
        self._private.refresh_rate_textboxes[i].markup = helpers.colorize_text(profiles[i].label, is_active and accent or normal_fg)
        self._private.refresh_rate_buttons[i].bg = is_active and ((#accent == 7) and (accent .. "22") or accent) or normal_bg
    end
end

function refresh_rate_mode.scroll_up(self)
    local row = self._private.refresh_rate_selected_row or current_profile_idx
    if row > 1 then
        self._private.refresh_rate_selected_row = row - 1
        refresh_rate_mode.update_highlight(self)
    end
end

function refresh_rate_mode.scroll_down(self)
    local row = self._private.refresh_rate_selected_row or current_profile_idx
    if row < #profiles then
        self._private.refresh_rate_selected_row = row + 1
        refresh_rate_mode.update_highlight(self)
    end
end

function refresh_rate_mode.select_active(self)
    local row = self._private.refresh_rate_selected_row or current_profile_idx
    if row < 1 or row > #profiles then return end

    current_profile_idx = row
    refresh_rate_mode.update_highlight(self)

    local cmd = profiles[current_profile_idx].cmd
    if cmd then
        awful.spawn.easy_async_with_shell(cmd, function(stdout, stderr)
            -- xrandr commands are fire-and-forget
        end)
    end
end

return refresh_rate_mode
