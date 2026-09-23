---------------------------------------------------------------------------
-- Clipboard mode: list widget, scrolling, rendering.
-- Activated when the prompt text starts with ';'.
---------------------------------------------------------------------------

local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local dpi = beautiful.xresources.apply_dpi
local apps = require("mods.app_launcher.apps")

local string = string
local math = math
local capi = { mouse = mouse }

local clipboard_mode = {}

function clipboard_mode.create_widget(self, entry)
    local icon_text = entry.is_image and "🖼️" or "📋"
    local item = wibox.widget {
        widget = wibox.container.background, id = "background", forced_height = dpi(60),
        shape = self.app_shape or gears.shape.rounded_rect,
        bg = self.app_normal_color or beautiful.bg_normal,
        {
            widget = wibox.container.margin, margins = { left = dpi(15), right = dpi(15) },
            {
                layout = wibox.layout.fixed.horizontal, spacing = dpi(15),
                { widget = wibox.widget.textbox,
                  markup = string.format("<span size='large' foreground='%s'>%s</span>",
                    self.app_name_normal_color or beautiful.fg_normal, icon_text),
                  valign = "center" },
                { widget = wibox.widget.textbox, id = "name", text = entry.text,
                  valign = "center", align = "left", font = self.app_name_font or beautiful.font,
                  ellipsize = "end", forced_width = dpi(400) }
            }
        }
    }
    item:connect_signal("mouse::enter", function()
        item.bg = self.app_normal_hover_color or beautiful.bg_focus
        if capi.mouse.current_wibox then capi.mouse.current_wibox.cursor = "hand2" end
    end)
    item:connect_signal("mouse::leave", function()
        item.bg = self.app_normal_color or beautiful.bg_normal
        if capi.mouse.current_wibox then capi.mouse.current_wibox.cursor = "left_ptr" end
    end)
    item:connect_signal("button::press", function()
        self.clipboard_select(entry.id)
        self:hide()
    end)
    return item
end

function clipboard_mode.render_list(self, items)
    self._private.clipboard_grid:reset()
    self._private.clipboard_items = items
    local max_items = 10
    for i = 1, math.min(#items, max_items) do
        self._private.clipboard_grid:add(clipboard_mode.create_widget(self, items[i]))
    end
    if #items > 0 then
        apps.select_app(self, 1, 1)
    else
        apps.unselect_app(self)
    end
end

function clipboard_mode.scroll_up(self)
    local grid = self._private.clipboard_grid
    if not grid or #grid.children < 1 then return end
    local pos = grid:get_widget_position(self._private.active_widget)
    if pos and pos.row > 1 then
        apps.unselect_app(self)
        apps.select_app(self, pos.row - 1, 1)
    end
end

function clipboard_mode.scroll_down(self)
    local grid = self._private.clipboard_grid
    if not grid or #grid.children < 1 then return end
    local pos = grid:get_widget_position(self._private.active_widget)
    if pos and pos.row < #grid.children then
        apps.unselect_app(self)
        apps.select_app(self, pos.row + 1, 1)
    end
end

return clipboard_mode