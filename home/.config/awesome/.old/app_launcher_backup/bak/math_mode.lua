---------------------------------------------------------------------------
-- Math mode: evaluates arithmetic expressions via `qalc` and shows
-- the result. Activated when the prompt text starts with '='.
---------------------------------------------------------------------------

local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local dpi = beautiful.xresources.apply_dpi
local utils = require("mods.app_launcher.utils")

local string = string

local math_mode = {}

function math_mode.create_widget(self)
    return wibox.widget {
        widget = wibox.container.background,
        forced_height = self.app_height,
        shape = self.app_shape or gears.shape.rounded_rect,
        bg = self.app_normal_color or beautiful.bg_normal,
        visible = false,
        { widget = wibox.container.margin, margins = self.app_content_padding or dpi(10),
            { widget = wibox.widget.textbox, id = "math_result",
              font = self.app_name_font or beautiful.font,
              align = "center", valign = "center",
              markup = string.format("<span foreground='%s'>= ...</span>",
                self.app_name_normal_color or beautiful.fg_normal) } }
    }
end

function math_mode.evaluate(self, text)
    utils.evaluate_math(text, function(result)
        local result_widget = self._private.math_widget:get_children_by_id("math_result")[1]
        if result_widget then
            local color_res = result:lower():match("error") and
                beautiful.fg_urgent or
                (self.app_name_normal_color or beautiful.fg_normal)
            result_widget.markup = string.format("<span foreground='%s'>= %s</span>", color_res, result)
        end
    end)
end

function math_mode.copy_result(self)
    local result_widget = self._private.math_widget:get_children_by_id("math_result")[1]
    if result_widget and
       not result_widget.text:lower():match("error") and
       not result_widget.text:match("%.%.%.") then
        local clean_result = result_widget.text:gsub("^=%s*", "")
        awful.spawn.with_shell(string.format(
            "printf '%%s' '%s' | xclip -selection clipboard 2>/dev/null || " ..
            "printf '%%s' '%s' | wl-copy 2>/dev/null",
            clean_result, clean_result))
        self:hide()
    end
end

return math_mode