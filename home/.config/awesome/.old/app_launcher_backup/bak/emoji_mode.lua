---------------------------------------------------------------------------
-- Emoji mode: renders a paginated grid of emoji buttons.
-- Activated when the prompt text starts with ':'.
---------------------------------------------------------------------------

local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local dpi = beautiful.xresources.apply_dpi
local emoji_db = require("mods.app_launcher.emoji")

local string = string
local math = math

local emoji_mode = {}

function emoji_mode.render_grid(self)
    self._private.emoji_grid:reset()
    local filtered = self._private.emoji_filtered or {}
    local offset = self._private.emoji_offset or 0
    local limit = math.min(#filtered - offset, 75)
    for i = 1, limit do
        local idx = offset + i
        local em = filtered[idx]
        if not em then break end
        local bg = wibox.widget {
            widget = wibox.container.background,
            shape = self.app_shape or gears.shape.rounded_rect,
            bg = self.app_normal_color or beautiful.bg_normal,
            { widget = wibox.widget.textbox, text = em.unicode, align = "center", valign = "center",
              font = "Noto Color Emoji 18", ellipsize = "none" }
        }
        awful.tooltip { objects = { bg }, text = em.name, mode = "outside", align = "top",
            preferred_positions = { "top", "bottom", "right", "left" } }
        bg:connect_signal("button::press", function()
            local copy_cmd = string.format(
                "printf '%%s' '%s' | xclip -selection clipboard 2>/dev/null || " ..
                "printf '%%s' '%s' | xsel --clipboard --input 2>/dev/null || " ..
                "printf '%%s' '%s' | wl-copy 2>/dev/null || " ..
                "copyq add '%s' 2>/dev/null",
                em.unicode, em.unicode, em.unicode, em.unicode)
            awful.spawn.with_shell(copy_cmd)
            self:hide()
        end)
        bg:connect_signal("mouse::enter", function() bg.bg = beautiful.bg_focus or "#555555" end)
        bg:connect_signal("mouse::leave", function() bg.bg = beautiful.bg_normal or "#333333" end)
        self._private.emoji_grid:add(wibox.widget { widget = wibox.container.margin, margins = dpi(2), bg })
    end
end

function emoji_mode.handle_search(self, text)
    self._private.emoji_filtered = emoji_db.filter_emojis(emoji_db.emojis, text:sub(2):lower())
    self._private.emoji_offset = 0
    emoji_mode.render_grid(self)
end

return emoji_mode