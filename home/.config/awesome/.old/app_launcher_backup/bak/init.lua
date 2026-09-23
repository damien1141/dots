---------------------------------------------------------------------------
-- AwesomeWM app launcher — main entry point.
-- Wires together the prompt, app grid, and special modes (emoji/clipboard/math).
-- Heavy logic lives in sibling modules; this file is the orchestrator.
--
-- File map:
--   init.lua              — this file: arg defaults, popup, prompt wiring, public API
--   prompt.lua            — text input keygrabber
--   emoji.lua             — emoji database + filter helpers
--   utils.lua             — pure helpers (match score, has_value, qalc wrapper)
--   apps.lua              — app discovery, widget creation, grid scroll/search
--   sidebar.lua           — sessionctl buttons + clock widget
--   clipboard_mode.lua    — ';' prefix mode
--   emoji_mode.lua        — ':' prefix mode
--   math_mode.lua         — '=' prefix mode
---------------------------------------------------------------------------

local awful = require("awful")
local gears = require("gears")
local gobject = require("gears.object")
local gtable = require("gears.table")
local gtimer = require("gears.timer")
local gfilesystem = require("gears.filesystem")
local wibox = require("wibox")
local beautiful = require("beautiful")

local prompt = require(... .. ".prompt")
local utils = require(... .. ".utils")
local apps = require(... .. ".apps")
local sidebar = require(... .. ".sidebar")
local clipboard_mode = require(... .. ".clipboard_mode")
local emoji_mode = require(... .. ".emoji_mode")
local math_mode = require(... .. ".math_mode")
local power_profiles_mode = require(... .. ".power_profiles_mode")
local refresh_rate_mode = require(... .. ".refresh_rate_mode")

local dpi = beautiful.xresources.apply_dpi
local math = math
local string = string
local table = table
local ipairs = ipairs
local capi = { screen = screen, mouse = mouse }

local app_launcher = { mt = {} }

--------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------

function app_launcher:show()
    local screen = self.screen
    if self.show_on_focused_screen then screen = awful.screen.focused() end
    if not screen then return end
    screen.app_launcher = self._private.widget
    self._private.widget.screen = screen
    self._private.prompt:start()

    local animation = self.rubato
    if animation ~= nil then
        if self._private.widget.goal_x == nil then self._private.widget.goal_x = self._private.widget.x end
        if self._private.widget.goal_y == nil then
            self._private.widget.goal_y = self._private.widget.y
            self._private.widget.placement = nil
        end
        if animation.x then
            animation.x.ended:unsubscribe()
            animation.x:set(self._private.widget.goal_x)
            gtimer { timeout = 0.01, call_now = false, autostart = true, single_shot = true,
                callback = function() screen.app_launcher.visible = true end }
        end
        if animation.y then
            animation.y.ended:unsubscribe()
            animation.y:set(self._private.widget.goal_y)
            gtimer { timeout = 0.01, call_now = false, autostart = true, single_shot = true,
                callback = function() screen.app_launcher.visible = true end }
        end
    else
        screen.app_launcher.visible = true
    end
    self:emit_signal("bling::app_launcher::visibility", true)
end

function app_launcher:hide()
    local screen = self.screen
    if self.show_on_focused_screen then screen = awful.screen.focused() end
    if not screen or screen.app_launcher == nil or screen.app_launcher.visible == false then return end

    self._private.prompt:stop()
    local animation = self.rubato
    if animation ~= nil then
        if animation.x then animation.x:set(animation.x:initial()) end
        if animation.y then animation.y:set(animation.y:initial()) end

        local anim_x_duration = (animation.x and animation.x.duration) or 0
        local anim_y_duration = (animation.y and animation.y.duration) or 0
        local turn_off_on_anim_x_end = (anim_x_duration >= anim_y_duration)

        if turn_off_on_anim_x_end then
            animation.x.ended:subscribe(function()
                if self.reset_on_hide == true then apps.reset(self) end
                screen.app_launcher.visible = false
                screen.app_launcher = nil
                animation.x.ended:unsubscribe()
            end)
        else
            animation.y.ended:subscribe(function()
                if self.reset_on_hide == true then apps.reset(self) end
                screen.app_launcher.visible = false
                screen.app_launcher = nil
                animation.y.ended:unsubscribe()
            end)
        end
    else
        if self.reset_on_hide == true then apps.reset(self) end
        screen.app_launcher.visible = false
        screen.app_launcher = nil
    end
    self:emit_signal("bling::app_launcher::visibility", false)
end

function app_launcher:toggle(screen)
    if not screen then
        screen = self.screen
        if self.show_on_focused_screen then
            screen = awful.screen.focused()
        end
    end
    if not screen then return end
    if screen.app_launcher and screen.app_launcher.visible then
        self:hide()
    else
        self:show()
    end
end

--------------------------------------------------------------------------
-- Prompt callbacks (delegated to mode modules)
--------------------------------------------------------------------------

local function handle_text_changed(ret, text)
    if text == ret._private.text then return end
    local is_emoji = text:match("^:")
    local is_clipboard = text:match("^;")
    local is_math = text:match("^=")
    local is_power_profile = text:match("^`")
    local is_refresh_rate = text:match("^~")

    ret._private.emoji_mode = is_emoji
    ret._private.clipboard_mode = is_clipboard
    ret._private.math_mode = is_math
    ret._private.power_profile_mode = is_power_profile
    ret._private.refresh_rate_mode = is_refresh_rate

    if is_refresh_rate then
        ret._private.grid.visible = false
        ret._private.emoji_grid.visible = false
        ret._private.clipboard_grid.visible = false
        ret._private.math_widget.visible = false
        ret._private.power_profiles_widget.visible = false
        ret._private.refresh_rate_widget.visible = true
        ret._private.active_grid = nil
        refresh_rate_mode.handle_search(ret, text)
        ret._private.text = text
        return
    end

    if is_power_profile then
        ret._private.grid.visible = false
        ret._private.emoji_grid.visible = false
        ret._private.clipboard_grid.visible = false
        ret._private.math_widget.visible = false
        ret._private.power_profiles_widget.visible = true
        ret._private.active_grid = nil
        power_profiles_mode.handle_search(ret, text)
        ret._private.text = text
        return
    end

    if is_math then
        ret._private.grid.visible = false
        ret._private.emoji_grid.visible = false
        ret._private.clipboard_grid.visible = false
        ret._private.power_profiles_widget.visible = false
        ret._private.refresh_rate_widget.visible = false
        ret._private.math_widget.visible = true
        ret._private.active_grid = nil
        math_mode.evaluate(ret, text)

    elseif is_clipboard then
        ret._private.grid.visible = false
        ret._private.emoji_grid.visible = false
        ret._private.clipboard_grid.visible = true
        ret._private.power_profiles_widget.visible = false
        ret._private.refresh_rate_widget.visible = false
        ret._private.math_widget.visible = false
        ret._private.active_grid = ret._private.clipboard_grid
        local query = text:sub(2):lower()

        local function process_items(items)
            local filtered = {}
            for _, item in ipairs(items) do
                if query == "" or item.text:lower():find(query, 1, true) then
                    table.insert(filtered, item)
                end
            end
            clipboard_mode.render_list(ret, filtered)
        end

        if not ret._private.clipboard_items_cache then
            ret.clipboard_fetch(function(items)
                ret._private.clipboard_items_cache = items
                process_items(items)
            end)
        else
            process_items(ret._private.clipboard_items_cache)
        end

    elseif is_emoji then
        ret._private.grid.visible = false
        ret._private.emoji_grid.visible = true
        ret._private.clipboard_grid.visible = false
        ret._private.power_profiles_widget.visible = false
        ret._private.refresh_rate_widget.visible = false
        ret._private.math_widget.visible = false
        ret._private.active_grid = ret._private.emoji_grid
        emoji_mode.handle_search(ret, text)

    else
        ret._private.grid.visible = true
        ret._private.emoji_grid.visible = false
        ret._private.clipboard_grid.visible = false
        ret._private.power_profiles_widget.visible = false
        ret._private.refresh_rate_widget.visible = false
        ret._private.math_widget.visible = false
        ret._private.active_grid = ret._private.grid
        apps.search(ret, text)
    end
    ret._private.text = text
end

local function handle_key_pressed(ret, mod, key, cmd)
    if key == "Escape" then ret:hide(); return true end

    if key == "Return" or key == "KP_Enter" then
        if ret._private.math_mode then
            math_mode.copy_result(ret)
            return true
        elseif ret._private.emoji_mode then
            local offset = ret._private.emoji_offset or 0
            local first_emoji = ret._private.emoji_filtered and ret._private.emoji_filtered[offset + 1]
            if first_emoji then
                local copy_cmd = string.format(
                    "printf '%%s' '%s' | xclip -selection clipboard 2>/dev/null || " ..
                    "printf '%%s' '%s' | xsel --clipboard --input 2>/dev/null || " ..
                    "printf '%%s' '%s' | wl-copy 2>/dev/null || " ..
                    "copyq add '%s' 2>/dev/null",
                    first_emoji.unicode, first_emoji.unicode, first_emoji.unicode, first_emoji.unicode)
                awful.spawn.with_shell(copy_cmd)
                ret:hide()
            end
            return true
        elseif ret._private.power_profile_mode then
            power_profiles_mode.select_active(ret)
            ret:hide()
            return true
        elseif ret._private.refresh_rate_mode then
            refresh_rate_mode.select_active(ret)
            ret:hide()
            return true
        elseif ret._private.clipboard_mode then
            if ret._private.active_widget then
                local pos = ret._private.clipboard_grid:get_widget_position(ret._private.active_widget)
                if pos and ret._private.clipboard_items and ret._private.clipboard_items[pos.row] then
                    ret.clipboard_select(ret._private.clipboard_items[pos.row].id)
                    ret:hide()
                end
            end
            return true
        else
            if ret._private.active_widget then ret._private.active_widget.spawn() end
            return true
        end
    end

    if ret._private.clipboard_mode then
        if key == "Up" then clipboard_mode.scroll_up(ret) end
        if key == "Down" then clipboard_mode.scroll_down(ret) end
    elseif ret._private.power_profile_mode then
        if key == "Up" then power_profiles_mode.scroll_up(ret) end
        if key == "Down" then power_profiles_mode.scroll_down(ret) end
    elseif ret._private.refresh_rate_mode then
        if key == "Up" then refresh_rate_mode.scroll_up(ret) end
        if key == "Down" then refresh_rate_mode.scroll_down(ret) end
    elseif not ret._private.emoji_mode then
        if key == "Up" then apps.scroll_up(ret) end
        if key == "Down" then apps.scroll_down(ret) end
        if key == "Left" then apps.scroll_left(ret) end
        if key == "Right" then apps.scroll_right(ret) end
        if key == "Print" then awful.spawn(os.getenv("HOME") .. "/.scripts/ss full", false) end
    end
    return false
end

--------------------------------------------------------------------------
-- Constructor
--------------------------------------------------------------------------

local function new(args)
    args = args or {}

    -- Behavioral flags
    args.terminal = args.terminal or nil
    args.favorites = args.favorites or {}
    args.search_commands = args.search_commands == nil and true or args.search_commands
    args.skip_names = args.skip_names or {}
    args.skip_commands = args.skip_commands or {}
    args.skip_empty_icons = args.skip_empty_icons ~= nil and args.skip_empty_icons or false
    args.sort_alphabetically = args.sort_alphabetically == nil and true or args.sort_alphabetically
    args.reverse_sort_alphabetically = args.reverse_sort_alphabetically ~= nil and args.reverse_sort_alphabetically or false
    args.select_before_spawn = args.select_before_spawn == nil and true or args.select_before_spawn
    args.hide_on_left_clicked_outside = args.hide_on_left_clicked_outside == nil and true or args.hide_on_left_clicked_outside
    args.hide_on_right_clicked_outside = args.hide_on_right_clicked_outside == nil and true or args.hide_on_right_clicked_outside
    args.hide_on_launch = args.hide_on_launch == nil and true or args.hide_on_launch
    args.try_to_keep_index_after_searching = args.try_to_keep_index_after_searching ~= nil and args.try_to_keep_index_after_searching or false
    args.reset_on_hide = args.reset_on_hide == nil and true or args.reset_on_hide
    args.save_history = args.save_history == nil and true or args.save_history
    args.wrap_page_scrolling = args.wrap_page_scrolling == nil and true or args.wrap_page_scrolling
    args.wrap_app_scrolling = args.wrap_app_scrolling == nil and true or args.wrap_app_scrolling

    -- Icons
    args.default_app_icon_name = args.default_app_icon_name or nil
    args.default_app_icon_path = args.default_app_icon_path or nil
    args.icon_theme = args.icon_theme or nil
    args.icon_size = args.icon_size or nil

    -- Popup geometry
    args.type = args.type or "dock"
    args.show_on_focused_screen = args.show_on_focused_screen == nil and true or args.show_on_focused_screen
    args.screen = args.screen or capi.screen.primary
    args.placement = args.placement or awful.placement.centered
    args.rubato = args.rubato or nil
    args.shrink_width = args.shrink_width ~= nil and args.shrink_width or false
    args.shrink_height = args.shrink_height ~= nil and args.shrink_height or false
    args.background = args.background or "#000000"
    args.shape = args.shape or nil

    -- Prompt styling
    args.prompt_height = args.prompt_height or dpi(100)
    args.prompt_margins = args.prompt_margins or dpi(0)
    args.prompt_paddings = args.prompt_paddings or dpi(30)
    args.prompt_shape = args.prompt_shape or nil
    args.prompt_color = args.prompt_color or beautiful.fg_normal or "#FFFFFF"
    args.prompt_border_width = args.prompt_border_width or beautiful.border_width or dpi(0)
    args.prompt_border_color = args.prompt_border_color or beautiful.border_color or args.prompt_color
    args.prompt_text_halign = args.prompt_text_halign or "left"
    args.prompt_text_valign = args.prompt_text_valign or "center"
    args.prompt_icon_text_spacing = args.prompt_icon_text_spacing or dpi(10)
    args.prompt_show_icon = args.prompt_show_icon == nil and true or args.prompt_show_icon
    args.prompt_icon_font = args.prompt_icon_font or beautiful.font
    args.prompt_icon_color = args.prompt_icon_color or beautiful.bg_normal or "#000000"
    args.prompt_icon = args.prompt_icon or ""
    args.prompt_icon_markup = args.prompt_icon_markup or
        string.format("<span size='xx-large' foreground='%s'>%s</span>", args.prompt_icon_color, args.prompt_icon)
    args.prompt_text = args.prompt_text or "<b>Search</b>: "
    args.prompt_start_text = args.prompt_start_text or ""
    args.prompt_font = args.prompt_font or beautiful.font
    args.prompt_text_color = args.prompt_text_color or beautiful.bg_normal or "#000000"
    args.prompt_cursor_color = args.prompt_cursor_color or beautiful.bg_normal or "#000000"

    -- Clipboard hooks
    args.clipboard_fetch = args.clipboard_fetch or function(callback)
        awful.spawn.easy_async_with_shell("greenclip print 2>/dev/null | head -n 20", function(stdout)
            local items = {}
            if stdout then
                for line in stdout:gmatch("[^\r\n]+") do
                    if line ~= "" then table.insert(items, { id = line, text = line, is_image = false }) end
                end
            end
            callback(items)
        end)
    end
    args.clipboard_select = args.clipboard_select or function(id)
        local safe_text = tostring(id):gsub("'", "'\\''")
        awful.spawn.with_shell(string.format("greenclip print '%s'", safe_text))
    end

    -- Grid layout
    args.apps_per_row = args.apps_per_row or 5
    args.apps_per_column = args.apps_per_column or 4
    args.apps_margin = args.apps_margin or dpi(30)
    args.apps_spacing = args.apps_spacing or dpi(30)

    -- App tile styling
    args.expand_apps = args.expand_apps == nil and true or args.expand_apps
    args.app_width = args.app_width or dpi(350)
    args.app_height = args.app_height or dpi(120)
    args.app_shape = args.app_shape or nil
    args.app_normal_color = args.app_normal_color or beautiful.bg_normal or "#000000"
    args.app_normal_hover_color = args.app_normal_hover_color or beautiful.bg_focus or "#333333"
    args.app_selected_color = args.app_selected_color or beautiful.fg_normal or "#FFFFFF"
    args.app_selected_hover_color = args.app_selected_hover_color or beautiful.fg_focus or "#EEEEEE"
    args.app_content_padding = args.app_content_padding or dpi(10)
    args.app_content_spacing = args.app_content_spacing or dpi(10)
    args.app_show_icon = args.app_show_icon == nil and true or args.app_show_icon
    args.app_icon_halign = args.app_icon_halign or "center"
    args.app_icon_width = args.app_icon_width or dpi(70)
    args.app_icon_height = args.app_icon_height or dpi(70)
    args.app_show_name = args.app_show_name == nil and true or args.app_show_name
    args.app_name_generic_name_spacing = args.app_name_generic_name_spacing or dpi(0)
    args.app_name_halign = args.app_name_halign or "center"
    args.app_name_font = args.app_name_font or beautiful.font
    args.app_name_normal_color = args.app_name_normal_color or beautiful.fg_normal or "#FFFFFF"
    args.app_name_selected_color = args.app_name_selected_color or beautiful.bg_normal or "#000000"
    args.app_show_generic_name = args.app_show_generic_name ~= nil and args.app_show_generic_name or false

    -- Build the object
    local ret = gobject({})
    ret._private = {}
    ret._private.text = ""
    ret._private.emoji_offset = 0
    ret._private.emoji_mode = false
    ret._private.clipboard_mode = false
    ret._private.math_mode = false
    ret._private.active_grid = nil

    gtable.crush(ret, app_launcher)
    gtable.crush(ret, args)

    local grid_width = ret.shrink_width == false and
        dpi((ret.app_width * ret.apps_per_column) + ((ret.apps_per_column - 1) * ret.apps_spacing)) or nil
    local grid_height = ret.shrink_height == false and
        dpi((ret.app_height * ret.apps_per_row) + ((ret.apps_per_row - 1) * ret.apps_spacing)) or nil

    -- Prompt
    ret._private.prompt = prompt {
        prompt = ret.prompt_text,
        text = ret.prompt_start_text,
        font = ret.prompt_font,
        reset_on_stop = ret.reset_on_hide,
        bg_cursor = ret.prompt_cursor_color,
        history_path = ret.save_history == true and gfilesystem.get_cache_dir() .. "/history" or nil,
        changed_callback = function(text) handle_text_changed(ret, text) end,
        keypressed_callback = function(mod, key, cmd) return handle_key_pressed(ret, mod, key, cmd) end,
    }

    -- App grid (default, visible)
    ret._private.grid = wibox.widget {
        layout = wibox.layout.grid,
        forced_width = grid_width, forced_height = grid_height,
        orientation = "horizontal", homogeneous = true, expand = ret.expand_apps,
        spacing = ret.apps_spacing, forced_num_rows = ret.apps_per_row,
        buttons = {
            awful.button({}, 4, function() apps.scroll_up(ret) end),
            awful.button({}, 5, function() apps.scroll_down(ret) end)
        }
    }

    -- Emoji grid (hidden by default)
    ret._private.emoji_grid = wibox.widget {
        layout = wibox.layout.grid,
        orientation = "vertical", homogeneous = true, expand = true, spacing = dpi(8),
        forced_num_rows = 15, forced_num_cols = 5,
        forced_width = grid_width, forced_height = grid_height, visible = false,
        buttons = {
            awful.button({}, 4, function()
                ret._private.emoji_offset = math.max(0, (ret._private.emoji_offset or 0) - 15)
                emoji_mode.render_grid(ret)
            end),
            awful.button({}, 5, function()
                local max_offset = math.max(0, #ret._private.emoji_filtered - 75)
                ret._private.emoji_offset = math.min(max_offset, (ret._private.emoji_offset or 0) + 15)
                emoji_mode.render_grid(ret)
            end)
        }
    }

    -- Clipboard grid (hidden by default)
    ret._private.clipboard_grid = wibox.widget {
        layout = wibox.layout.grid,
        forced_width = grid_width, forced_height = grid_height,
        orientation = "vertical", homogeneous = true, expand = false,
        spacing = dpi(4), forced_num_cols = 1, visible = false,
        buttons = {
            awful.button({}, 4, function() clipboard_mode.scroll_up(ret) end),
            awful.button({}, 5, function() clipboard_mode.scroll_down(ret) end)
        }
    }

    -- Math widget (hidden by default)
    ret._private.math_widget = math_mode.create_widget(ret)
    ret._private.math_widget:connect_signal("button::press", function()
        math_mode.copy_result(ret)
    end)

    -- Power profiles widget (hidden by default)
    ret._private.power_profiles_widget = power_profiles_mode.create_widget(ret)

    -- Refresh rate widget (hidden by default)
    ret._private.refresh_rate_widget = refresh_rate_mode.create_widget(ret)

    ret._private.active_grid = ret._private.grid

    -- Popup
    ret._private.widget = awful.popup {
        type = args.type, visible = false, ontop = true,
        placement = function(w)
            awful.placement.centered(w, { honor_workarea = true, margins = beautiful.useless_gap * 2 })
        end,
        shape = ret.shape, bg = ret.background,
        widget = {
            -- Top bar: profile, clock, statuses
            {
                {
                    {
                        sidebar.create_profile_widget(),
                        sidebar.create_quicksettings_widget(),
                        {
                            sidebar.create_statuses_widget(),
                            sidebar.create_time_widget(),
                            layout = wibox.layout.fixed.vertical,
                            spacing = dpi(4)
                        },
                        layout = wibox.layout.align.horizontal,
                        valign = "center",
                        forced_height = dpi(88)
                    },
                    margins = { left = dpi(20), right = dpi(20), top = dpi(0), bottom = dpi(0) },
                    widget = wibox.container.margin
                },
                widget = wibox.container.background, bg = beautiful.bg_2, forced_height = dpi(88)
            },
            -- Bottom: prompt + grid stack
            {
                layout = wibox.layout.fixed.vertical,
                {
                    widget = wibox.container.margin, margins = ret.prompt_margins,
                    {
                        widget = wibox.container.background, forced_height = ret.prompt_height,
                        shape = ret.prompt_shape, bg = ret.prompt_color, fg = ret.prompt_text_color,
                        border_width = ret.prompt_border_width, border_color = ret.prompt_border_color,
                        {
                            widget = wibox.container.margin, margins = ret.prompt_paddings,
                            {
                                widget = wibox.container.place,
                                halign = ret.prompt_text_halign, valign = ret.prompt_text_valign,
                                {
                                    layout = wibox.layout.fixed.horizontal, spacing = ret.prompt_icon_text_spacing,
                                    { widget = wibox.widget.textbox, font = ret.prompt_icon_font,
                                      markup = ret.prompt_icon_markup },
                                    ret._private.prompt.textbox
                                }
                            }
                        }
                    }
                },
                {
                    widget = wibox.container.margin,
                    margins = ret.apps_margin,
                    { layout = wibox.layout.stack,
                      ret._private.grid, ret._private.emoji_grid,
                      ret._private.clipboard_grid, ret._private.math_widget,
                      ret._private.power_profiles_widget, ret._private.refresh_rate_widget }
                }
            },
            layout = wibox.layout.flex.vertical
        }
    }

    -- Paging state
    ret._private.max_apps_per_page = ret.apps_per_column * ret.apps_per_row
    ret._private.apps_per_page = ret._private.max_apps_per_page
    ret._private.pages_count = 0
    ret._private.current_page = 1

    apps.generate_apps(ret)
    apps.reset(ret)

    -- Rubato animation hooks
    if ret.rubato and ret.rubato.x then
        ret.rubato.x:subscribe(function(pos) ret._private.widget.x = pos end)
    end
    if ret.rubato and ret.rubato.y then
        ret.rubato.y:subscribe(function(pos) ret._private.widget.y = pos end)
    end

    -- Click-outside-to-close
    if ret.hide_on_left_clicked_outside then
        awful.mouse.append_client_mousebinding(awful.button({}, 1, function() ret:hide() end))
        awful.mouse.append_global_mousebinding(awful.button({}, 1, function() ret:hide() end))
    end
    if ret.hide_on_right_clicked_outside then
        awful.mouse.append_client_mousebinding(awful.button({}, 3, function() ret:hide() end))
        awful.mouse.append_global_mousebinding(awful.button({}, 3, function() ret:hide() end))
    end

    -- Live-reload apps when /usr/share/applications changes
    local kill_old = [[ ps x | grep "inotifywait -e modify /usr/share/applications" | grep -v grep | awk '{print $1}' | xargs kill ]]
    local subscribe = [[ bash -c "while (inotifywait -e modify /usr/share/applications -qq) do echo; done" ]]
    awful.spawn.easy_async_with_shell(kill_old, function()
        awful.spawn.with_line_callback(subscribe, { stdout = function() apps.generate_apps(ret) end })
    end)

    return ret
end

--------------------------------------------------------------------------
-- Preset: text-only launcher
--------------------------------------------------------------------------

function app_launcher.text(args)
    args = args or {}
    args.prompt_height = args.prompt_height or dpi(50)
    args.prompt_margins = args.prompt_margins or dpi(30)
    args.prompt_paddings = args.prompt_paddings or dpi(15)
    args.app_width = args.app_width or dpi(350)
    args.app_height = args.app_height or dpi(120)
    args.apps_spacing = args.apps_spacing or dpi(10)
    args.apps_per_row = args.apps_per_row or 15
    args.apps_per_column = args.apps_per_column or 1
    args.app_name_halign = args.app_name_halign or "left"
    args.app_show_icon = args.app_show_icon ~= nil and args.app_show_icon or false
    args.app_show_generic_name = args.app_show_generic_name == nil and true or args.app_show_generic_name
    args.apps_margin = args.apps_margin or { left = dpi(40), right = dpi(40), bottom = dpi(30) }
    return new(args)
end

function app_launcher.mt:__call(...) return new(...) end
return setmetatable(app_launcher, app_launcher.mt)