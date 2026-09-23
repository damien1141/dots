local Gio = require("lgi").Gio
local awful = require("awful")
local gears = require("gears")
local gobject = require("gears.object")
local gtable = require("gears.table")
local gtimer = require("gears.timer")
local gfilesystem = require("gears.filesystem")
local gstring = require("gears.string")
local wibox = require("wibox")
local beautiful = require("beautiful")
local helpers = require("helpers")
local readwrite = require("misc.scripts.read_writer")
local rubato = require("mods.rubato")
local naughty = require("naughty")
local prompt = require(... .. ".prompt")
local emoji = require("mods.app_launcher.emoji")
local dpi = beautiful.xresources.apply_dpi

local string = string
local table = table
local math = math
local ipairs = ipairs
local pairs = pairs
local root = root
local capi = { screen = screen, mouse = mouse }
local path = ...
local app_launcher = { mt = {} }

local terminal_commands_lookup = {
    alacritty = "alacritty -e",
    termite = "termite -e",
    rxvt = "rxvt -e",
    terminator = "terminator -e"
}

local function get_match_score(text, name)
    if not text or text == "" then return 0 end
    if not name or name == "" then return 100 end
    local t = text:lower()
    local n = name:lower()
    
    if n == t then return 0 end
    if n:sub(1, #t) == t then return 1 end
    
    local pos = n:find(t, 1, true)
    if pos then return pos + 2 end
    
    return 100
end

local function has_value(tab, val)
    if not val or val == "" then return false end
    if not tab then return false end
    local val_lower = tostring(val):lower()
    for _, value in pairs(tab) do
        if val_lower:find(tostring(value):lower(), 1, true) then return true end
    end
    return false
end

local function evaluate_math(expr, callback)
    local clean_expr = expr:gsub("^=%s*", "")
    if clean_expr == "" then
        callback("...")
        return
    end
    local safe_expr = clean_expr:gsub("'", "'\\''")
    awful.spawn.easy_async_with_shell(string.format("qalc -t '%s' 2>&1", safe_expr), function(stdout)
        local result = (stdout or ""):gsub("^%s*(.-)%s*$", "%1")
        result = result:gsub("\27%[[0-9;]*[a-zA-Z]", "")
        result = result:gsub("[%c\r]", "")
        
        if result:lower():match("error") or result == "" then
            callback("Error")
        else
            callback(result)
        end
    end)
end

local function select_app(self, x, y)
    local grid = self._private.active_grid or self._private.grid
    if not grid then return end
    local widgets = grid:get_widgets_at(x, y)
    if widgets then
        self._private.active_widget = widgets[1]
        if self._private.active_widget ~= nil then
            self._private.active_widget.selected = true
            local bg_widget = self._private.active_widget:get_children_by_id("background")[1] or self._private.active_widget
            if bg_widget and bg_widget.bg ~= nil then
                bg_widget.bg = self.app_selected_color
            end

            local name_widget = self._private.active_widget:get_children_by_id("name")[1]
            if name_widget then
                name_widget.markup = string.format("<span foreground='%s'>%s</span>", self.app_name_selected_color, gstring.xml_escape(name_widget.text))
            end
            
            local generic_name_widget = self._private.active_widget:get_children_by_id("generic_name")[1]
            if generic_name_widget then
                generic_name_widget.markup = string.format("<i><span weight='300' foreground='%s'>%s</span></i>", self.app_name_selected_color, gstring.xml_escape(generic_name_widget.text))
            end
        end
    end
end

local function unselect_app(self)
    local grid = self._private.active_grid or self._private.grid
    if not grid then return end
    if self._private.active_widget ~= nil then
        self._private.active_widget.selected = false
        local bg_widget = self._private.active_widget:get_children_by_id("background")[1] or self._private.active_widget
        if bg_widget and bg_widget.bg ~= nil then
            bg_widget.bg = self.app_normal_color
        end

        local name_widget = self._private.active_widget:get_children_by_id("name")[1]
        if name_widget then
            name_widget.markup = string.format("<span foreground='%s'>%s</span>", self.app_name_normal_color, gstring.xml_escape(name_widget.text))
        end
        
        local generic_name_widget = self._private.active_widget:get_children_by_id("generic_name")[1]
        if generic_name_widget then
            generic_name_widget.markup = string.format("<i><span weight='300' foreground='%s'>%s</span></i>", self.app_name_normal_color, gstring.xml_escape(generic_name_widget.text))
        end
        
        self._private.active_widget = nil
    end
end

local function create_app_widget(self, entry)
    local icon_widget = nil
    if self.app_show_icon == true then
        local icon_args = {
            widget = wibox.widget.imagebox,
            halign = self.app_icon_halign,
            forced_width = self.app_icon_width,
            forced_height = self.app_icon_height,
        }
        if entry.icon and entry.icon ~= "" then
            icon_args.image = entry.icon
        end
        icon_widget = icon_args
    end

    local name_widget = nil
    if self.app_show_name == true then
        name_widget = {
            widget = wibox.widget.textbox,
            id = "name",
            font = self.app_name_font,
            markup = gstring.xml_escape(entry.name or "")
        }
    end

    local generic_name_widget = nil
    if entry.generic_name ~= nil and self.app_show_generic_name == true then
        generic_name_widget = {
            widget = wibox.widget.textbox,
            id = "generic_name",
            font = self.app_name_font,
            markup = entry.generic_name ~= "" and "<span weight='300'><i>(" .. gstring.xml_escape(entry.generic_name) .. ")</i></span>" or ""
        }
    end

    local app = wibox.widget {
        widget = wibox.container.background,
        id = "background",
        forced_width = self.app_width,
        forced_height = self.app_height,
        shape = self.app_shape,
        bg = self.app_normal_color,
        {
            widget = wibox.container.margin,
            margins = self.app_content_padding,
            {
                layout = wibox.layout.align.vertical,
                expand = "outside",
                nil,
                {
                    layout = wibox.layout.fixed.horizontal,
                    spacing = self.app_content_spacing,
                    icon_widget,
                    {
                        widget = wibox.container.place,
                        halign = self.app_name_halign,
                        {
                            layout = wibox.layout.fixed.horizontal,
                            spacing = self.app_name_generic_name_spacing,
                            name_widget,
                            generic_name_widget
                        }
                    }
                },
                nil
            }
        }
    }

    function app.spawn()
        if entry.terminal == true then
            if self.terminal ~= nil then
                local terminal_command = terminal_commands_lookup[self.terminal] or self.terminal
                awful.spawn(terminal_command .. " " .. entry.executable)
            else
                awful.spawn.easy_async("gtk-launch " .. entry.executable, function(stdout, stderr)
                    if stderr then awful.spawn(entry.executable) end
                end)
            end
        else
            awful.spawn(entry.executable)
        end

        if self.hide_on_launch then self:hide() end
    end

    app:connect_signal("mouse::enter", function(_self)
        local widget = capi.mouse.current_wibox
        if widget then widget.cursor = "hand2" end

        if _self.selected then
            _self.bg = self.app_selected_hover_color
        else
            _self.bg = self.app_normal_hover_color
        end
    end)

    app:connect_signal("mouse::leave", function(_self)
        local widget = capi.mouse.current_wibox
        if widget then widget.cursor = "left_ptr" end

        if _self.selected then
            _self.bg = self.app_selected_color
        else
            _self.bg = self.app_normal_color
        end
    end)

    app:connect_signal("button::press", function(_self, lx, ly, button, mods, find_widgets_result)
        if button == 1 then
            if self._private.active_widget == _self or not self.select_before_spawn then
                _self.spawn()
            else
                unselect_app(self)
                local pos = self._private.grid:get_widget_position(_self)
                select_app(self, pos.row, pos.col)
            end
        end
    end)

    return app
end

local function search(self, text)
    unselect_app(self)
    local pos = self._private.active_widget and self._private.grid:get_widget_position(self._private.active_widget) or {row = 1, col = 1}

    self._private.matched_entries = {}
    self._private.grid:reset()

    if text == "" then
        self._private.matched_entries = self._private.all_entries
    else
        for _, entry in ipairs(self._private.all_entries) do
            local score = get_match_score(text, entry.name)
            
            if self.search_commands then
                local cmd_score = get_match_score(text, entry.commandline)
                if cmd_score < score then score = cmd_score end
            end

            if score < 100 then
                table.insert(self._private.matched_entries, {
                    name = entry.name,
                    generic_name = entry.generic_name,
                    commandline = entry.commandline,
                    executable = entry.executable,
                    terminal = entry.terminal,
                    icon = entry.icon,
                    _score = score
                })
            end
        end

        table.sort(self._private.matched_entries, function(a, b)
            return a._score < b._score
        end)
    end

    for _, entry in ipairs(self._private.matched_entries) do
        if #self._private.grid.children + 1 <= self._private.max_apps_per_page then
            self._private.grid:add(create_app_widget(self, entry))
        end
    end

    self._private.apps_per_page = math.min(#self._private.matched_entries, self._private.max_apps_per_page)
    self._private.pages_count = math.ceil(math.max(1, #self._private.matched_entries) / math.max(1, self._private.apps_per_page))
    self._private.current_page = 1

    if self.try_to_keep_index_after_searching then
        if self._private.grid:get_widgets_at(pos.row, pos.col) == nil then
            local app = self._private.grid.children[#self._private.grid.children]
            if app then
                pos = self._private.grid:get_widget_position(app)
            else
                pos = {row = 1, col = 1}
            end
        end
        select_app(self, pos.row, pos.col)
    else
        select_app(self, 1, 1)
    end
end

local function page_backward(self, direction)
    local grid = self._private.active_grid or self._private.grid
    if not grid then return end
    if self._private.current_page > 1 then
        self._private.current_page = self._private.current_page - 1
    elseif self.wrap_page_scrolling and #self._private.matched_entries >= self._private.max_apps_per_page then
        self._private.current_page = self._private.pages_count
    elseif self.wrap_app_scrolling then
        local rows, columns = grid:get_dimension()
        unselect_app(self)
        select_app(self, math.min(rows, #grid.children % self.apps_per_row), columns)
        return
    else
        return
    end

    local pos = grid:get_widget_position(self._private.active_widget)
    if not pos then pos = {row = 1, col = 1} end
    grid:reset()

    local max_app_index_to_include = self._private.apps_per_page * self._private.current_page
    local min_app_index_to_include = max_app_index_to_include - self._private.apps_per_page

    for index, entry in ipairs(self._private.matched_entries) do
        if index > min_app_index_to_include and index <= max_app_index_to_include then
            grid:add(create_app_widget(self, entry))
        end
    end

    local rows, columns = grid:get_dimension()
    if self._private.current_page < self._private.pages_count then
        if direction == "up" then select_app(self, rows, columns)
        else select_app(self, pos.row, columns) end
    elseif self.wrap_page_scrolling then
        if direction == "up" then select_app(self, math.min(rows, #grid.children % self.apps_per_row), columns)
        else select_app(self, math.min(pos.row, #grid.children % self.apps_per_row), columns) end
    end
end

local function page_forward(self, direction)
    local min_app_index_to_include = 0
    local max_app_index_to_include = self._private.apps_per_page
    if self._private.current_page < self._private.pages_count then
        min_app_index_to_include = self._private.apps_per_page * self._private.current_page
        self._private.current_page = self._private.current_page + 1
        max_app_index_to_include = self._private.apps_per_page * self._private.current_page
    elseif self.wrap_page_scrolling and #self._private.matched_entries >= self._private.max_apps_per_page then
        self._private.current_page = 1
        min_app_index_to_include = 0
        max_app_index_to_include = self._private.apps_per_page
    elseif self.wrap_app_scrolling then
        unselect_app(self)
        select_app(self, 1, 1)
        return
    else
        return
    end

    local pos = self._private.grid:get_widget_position(self._private.active_widget)
    if not pos then pos = {row = 1, col = 1} end
    self._private.grid:reset()

    for index, entry in ipairs(self._private.matched_entries) do
        if index > min_app_index_to_include and index <= max_app_index_to_include then
            self._private.grid:add(create_app_widget(self, entry))
        end
    end

    if self._private.current_page > 1 or self.wrap_page_scrolling then
        if direction == "down" then
            select_app(self, 1, 1)
        else
            local last_col_max_row = math.min(pos.row, #self._private.grid.children % self.apps_per_row)
            if last_col_max_row ~= 0 then select_app(self, last_col_max_row, 1)
            else select_app(self, pos.row, 1) end
        end
    end
end

local function scroll_up(self)
    local grid = self._private.active_grid or self._private.grid
    if not grid or #grid.children < 1 then self._private.active_widget = nil return end
    local rows, columns = grid:get_dimension()
    local pos = grid:get_widget_position(self._private.active_widget)
    if not pos then pos = {row = 1, col = 1} end
    local is_bigger_than_first_app = pos.col > 1 or pos.row > 1

    if is_bigger_than_first_app then
        unselect_app(self)
        if pos.row == 1 then select_app(self, rows, pos.col - 1)
        else select_app(self, pos.row - 1, pos.col) end
    else
       page_backward(self, "up")
    end
end

local function scroll_down(self)
    local grid = self._private.active_grid or self._private.grid
    if not grid or #grid.children < 1 then self._private.active_widget = nil return end
    local rows, columns = grid:get_dimension()
    local pos = grid:get_widget_position(self._private.active_widget)
    if not pos then pos = {row = 1, col = 1} end
    local is_less_than_max_app = grid:index(self._private.active_widget) < #grid.children

    if is_less_than_max_app then
        unselect_app(self)
        if pos.row == rows then select_app(self, 1, pos.col + 1)
        else select_app(self, pos.row + 1, pos.col) end
    else
        page_forward(self, "down")
    end
end

local function scroll_left(self)
    local grid = self._private.active_grid or self._private.grid
    if not grid or #grid.children < 1 then self._private.active_widget = nil return end
    local pos = grid:get_widget_position(self._private.active_widget)
    if not pos then pos = {row = 1, col = 1} end
    if pos.col > 1 then
        unselect_app(self)
        select_app(self, pos.row, pos.col - 1)
    else
       page_backward(self, "left")
    end
end

local function scroll_right(self)
    local grid = self._private.active_grid or self._private.grid
    if not grid or #grid.children < 1 then self._private.active_widget = nil return end
    local rows, columns = grid:get_dimension()
    local pos = grid:get_widget_position(self._private.active_widget)
    if not pos then pos = {row = 1, col = 1} end

    if pos.col < columns then
        unselect_app(self)
        if grid:get_widgets_at(pos.row, pos.col + 1) == nil then
            local app = grid.children[#grid.children]
            pos = grid:get_widget_position(app)
            select_app(self, pos.row, pos.col)
        else
            select_app(self, pos.row, pos.col + 1)
        end
    else
        page_forward(self, "right")
    end
end

local function reset(self)
    self._private.grid:reset()
    self._private.matched_entries = self._private.all_entries
    self._private.apps_per_page = self._private.max_apps_per_page
    self._private.pages_count = math.ceil(#self._private.all_entries / self._private.apps_per_page)
    self._private.current_page = 1
    for index, entry in ipairs(self._private.all_entries) do
        if index <= self._private.apps_per_page then
            self._private.grid:add(create_app_widget(self, entry))
        else
            break
        end
    end
    select_app(self, 1, 1)
end

local function generate_apps(self)
    self._private.all_entries = {}
    self._private.matched_entries = {}
    local apps = Gio.AppInfo.get_all()

    table.sort(apps, function(a, b)
        local name_a = a:get_name() or ""
        local name_b = b:get_name() or ""
        local a_fav = has_value(self.favorites, name_a)
        local b_fav = has_value(self.favorites, name_b)

        if a_fav and not b_fav then return true
        elseif b_fav and not a_fav then return false end

        if self.sort_alphabetically then
            return name_a:lower() < name_b:lower()
        elseif self.reverse_sort_alphabetically then
            return name_a:lower() > name_b:lower()
        else
            return name_a:lower() < name_b:lower()
        end
    end)

    local icon_theme = nil
    local ok, mod = pcall(require, "mods.bling.helpers.icon_theme")
    if ok and mod then
        local ok2, res = pcall(mod, self.icon_theme, self.icon_size)
        if ok2 then icon_theme = res end
    end

    for _, app in ipairs(apps) do
        local success, should_show = pcall(function() return app:should_show() end)
        if success and should_show then
            local name = app:get_name() or ""
            local commandline = app:get_commandline() or ""
            local executable = app:get_executable() or ""
            
            local icon = ""
            if icon_theme then
                local gicon = app:get_icon()
                if gicon then
                    icon = icon_theme:get_gicon_path(gicon) or ""
                end
            end

            if not has_value(self.skip_names, name) and not has_value(self.skip_commands, commandline) then
                if icon ~= "" or self.skip_empty_icons == false then
                    if icon == "" then
                        if self.default_app_icon_name ~= nil and icon_theme then 
                            icon = icon_theme:get_icon_path(self.default_app_icon_name) or ""
                        elseif self.default_app_icon_path ~= nil then 
                            icon = self.default_app_icon_path
                        elseif icon_theme then 
                            icon = icon_theme:choose_icon({"application-all", "application", "application-default-icon", "app"}) or ""
                        end
                    end

                    local terminal = false
                    local generic_name = nil

                    if Gio and Gio.DesktopAppInfo then
                        local app_id = app:get_id()
                        if app_id then
                            local desktop_app_info = Gio.DesktopAppInfo.new(app_id)
                            if desktop_app_info then
                                local term_str = Gio.DesktopAppInfo.get_string(desktop_app_info, "Terminal")
                                terminal = term_str == "true"
                                generic_name = Gio.DesktopAppInfo.get_string(desktop_app_info, "GenericName")
                            end
                        end
                    end

                    table.insert(self._private.all_entries, { 
                        name = name, 
                        generic_name = generic_name, 
                        commandline = commandline, 
                        executable = executable, 
                        terminal = terminal, 
                        icon = icon 
                    })
                end
            end
        end
    end
end

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
            gtimer { timeout = 0.01, call_now = false, autostart = true, single_shot = true, callback = function() screen.app_launcher.visible = true end }
        end
        if animation.y then
            animation.y.ended:unsubscribe()
            animation.y:set(self._private.widget.goal_y)
            gtimer { timeout = 0.01, call_now = false, autostart = true, single_shot = true, callback = function() screen.app_launcher.visible = true end }
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
        local turn_off_on_anim_x_end = (anim_x_duration >= anim_y_duration) and true or false

        if turn_off_on_anim_x_end then
            animation.x.ended:subscribe(function()
                if self.reset_on_hide == true then reset(self) end
                screen.app_launcher.visible = false
                screen.app_launcher = nil
                animation.x.ended:unsubscribe()
            end)
        else
            animation.y.ended:subscribe(function()
                if self.reset_on_hide == true then reset(self) end
                screen.app_launcher.visible = false
                screen.app_launcher = nil
                animation.y.ended:unsubscribe()
            end)
        end
    else
        if self.reset_on_hide == true then reset(self) end
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

-- Status icons
local function statuses()
    -- wifi
    local wifi = wibox.widget{
        font = beautiful.icon_var .. "12",
        markup = helpers.colorize_text("󰖩 ", beautiful.fg_color),
        widget = wibox.widget.textbox,
        valign = "center",
        align = "center"
    }
    wifi:buttons(gears.table.join(awful.button({}, 1, function() awful.spawn("kitty nmtui") end)))

    -- bluetooth
    local blue = wibox.widget{
        font = beautiful.icon_var .. "12",
        markup = helpers.colorize_text("󰂲 ", beautiful.fg_color .. "99"),
        widget = wibox.widget.textbox,
        valign = "center",
        align = "center"
    }
    blue:buttons(gears.table.join(awful.button({}, 1, function() awful.spawn("kitty blueberry") end)))

    -- volume
    local volume = wibox.widget{
        font = beautiful.icon_var .. "12",
        markup = helpers.colorize_text("󰕾 ", beautiful.fg_color),
        widget = wibox.widget.textbox,
        valign = "center",
        align = "center"
    }
    local function updateVolumeIcon(volume_level)
        if volume_level >= 40 then
            volume.markup = helpers.colorize_text("󰕾 ", beautiful.fg_color)
        elseif volume_level >= 20 then
            volume.markup = helpers.colorize_text("󰖀 ", beautiful.fg_color)
        elseif volume_level >= 1 then
            volume.markup = helpers.colorize_text("󰕿 ", beautiful.fg_color)
        else
            volume.markup = helpers.colorize_text("󰖁 ", beautiful.fg_color .. "99")
        end
    end
    awful.widget.watch("amixer -D pulse sget Master", 0.5, function(_, stdout)
        local volumeLevel = tonumber(string.match(stdout, "(%d?%d?%d)%%")) or 0
        updateVolumeIcon(volumeLevel)
    end)
    awful.spawn.easy_async({"amixer", "-D", "pulse", "sget", "Master"}, function(stdout)
        local volumeLevel = tonumber(string.match(stdout, "(%d?%d?%d)%%")) or 0
        updateVolumeIcon(volumeLevel)
    end)

    -- microphone
    local mic_icon = wibox.widget{
        font = beautiful.icon_var .. "12",
        markup = helpers.colorize_text(" ", beautiful.fg_color),
        widget = wibox.widget.textbox,
        valign = "center",
        align = "center"
    }
    local function updateMicIcon(mic_level)
        if mic_level >= 1 then
            mic_icon.markup = helpers.colorize_text(" ", beautiful.fg_color)
        else
            mic_icon.markup = helpers.colorize_text(" ", beautiful.fg_color .. "99")
        end
    end
    awful.widget.watch("amixer -D pulse sget Capture", 0.5, function(_, stdout)
        local micLevel = tonumber(string.match(stdout, "(%d?%d?%d)%%")) or 0
        updateMicIcon(micLevel)
    end)
    awful.spawn.easy_async({"amixer", "-D", "pulse", "sget", "Capture"}, function(stdout)
        local micLevel = tonumber(string.match(stdout, "(%d?%d?%d)%%")) or 0
        updateMicIcon(micLevel)
    end)

    -- battery
    local battery = wibox.widget{
        widget = wibox.container.arcchart,
        max_value = 100,
        min_value = 0,
        value = 50,
        thickness = dpi(3),
        rounded_edge = true,
        bg = beautiful.green_color .. "4D",
        colors = { beautiful.green_color },
        start_angle = math.pi + math.pi / 2,
        forced_width = dpi(17),
        forced_height = dpi(17)
    }
    awesome.connect_signal("signal::battery", function(value)
        battery.value = value
    end)

    return wibox.widget{
        {
            wifi,
            blue,
            volume,
            mic_icon,
            battery,
            layout = wibox.layout.fixed.horizontal,
            spacing = dpi(10)
        },
        widget = wibox.container.margin,
        right = dpi(12)
    }
end

-- Quick settings buttons
local function quicksettings()
    local btn_size = dpi(38)

    -- Keep screen on
    local inhibit_icon = wibox.widget{
        font = beautiful.icon_var .. "12",
        markup = helpers.colorize_text(" ", beautiful.fg_color .. "4D"),
        widget = wibox.widget.textbox,
        valign = "center",
        align = "center"
    }
    local inhibit_circle = wibox.widget{
        widget = wibox.container.background,
        shape = helpers.rrect((beautiful.rounded or 4) - 3),
        bg = beautiful.accent,
        forced_width = dpi(45),
        forced_height = dpi(45),
    }
    local inhibit_anim = rubato.timed{
        pos = 0, rate = 60, intro = 0.08, duration = 0.3,
        awestore_compat = true,
        subscribed = function(pos) inhibit_circle.opacity = pos end
    }
    local inhibit_state = false
    local inhibit_btn = wibox.widget{
        {
            {
                nil,
                { inhibit_circle, layout = wibox.layout.fixed.horizontal },
                layout = wibox.layout.align.horizontal,
                expand = "none"
            },
            {
                nil,
                {
                    inhibit_icon,
                    layout = wibox.layout.fixed.vertical,
                    spacing = dpi(10)
                },
                layout = wibox.layout.align.vertical,
                expand = "none"
            },
            layout = wibox.layout.stack
        },
        shape = gears.shape.circle,
        widget = wibox.container.background,
        border_color = beautiful.fg_color .. "33",
        forced_width = btn_size,
        forced_height = btn_size,
        bg = beautiful.bg_3
    }
    inhibit_btn:buttons(gears.table.join(awful.button({}, 1, function()
        inhibit_state = not inhibit_state
        if inhibit_state then
            awful.spawn.with_shell("xset s off && xset -dpms")
        else
            awful.spawn.with_shell("xset s on && xset +dpms")
        end
        inhibit_icon.markup = helpers.colorize_text(" ", inhibit_state and beautiful.accent or beautiful.fg_color .. "4D")
        inhibit_anim.target = inhibit_state and 0.09 or 0
    end)))

    -- Night light
    local night_icon = wibox.widget{
        font = beautiful.icon_var .. "12",
        markup = helpers.colorize_text(" 󰌵 ", beautiful.fg_color .. "4D"),
        widget = wibox.widget.textbox,
        valign = "center",
        align = "center"
    }
    local night_circle = wibox.widget{
        widget = wibox.container.background,
        shape = helpers.rrect((beautiful.rounded or 4) - 3),
        bg = beautiful.accent,
        forced_width = dpi(45),
        forced_height = dpi(45),
    }
    local night_anim = rubato.timed{
        pos = 0, rate = 60, intro = 0.08, duration = 0.3,
        awestore_compat = true,
        subscribed = function(pos) night_circle.opacity = pos end
    }
    local night_state = false
    local night_btn = wibox.widget{
        {
            {
                nil,
                { night_circle, layout = wibox.layout.fixed.horizontal },
                layout = wibox.layout.align.horizontal,
                expand = "none"
            },
            {
                nil,
                {
                    night_icon,
                    layout = wibox.layout.fixed.vertical,
                    spacing = dpi(10)
                },
                layout = wibox.layout.align.vertical,
                expand = "none"
            },
            layout = wibox.layout.stack
        },
        shape = gears.shape.circle,
        widget = wibox.container.background,
        border_color = beautiful.fg_color .. "33",
        forced_width = btn_size,
        forced_height = btn_size,
        bg = beautiful.bg_3
    }
    local night_state_file = os.getenv("HOME") .. "/.config/awesome/misc/.information/blue_light_state"
    os.execute("mkdir -p " .. night_state_file:match("(.*/)"))
    local function update_night_visual()
        night_icon.markup = helpers.colorize_text(" 󰌵 ", night_state and beautiful.accent or beautiful.fg_color .. "4D")
        night_anim.target = night_state and 0.09 or 0
    end
    do
        local file = io.open(night_state_file, "r")
        if file then
            night_state = (file:read("*l") == "true")
            file:close()
            update_night_visual()
        end
    end
    night_btn:buttons(gears.table.join(awful.button({}, 1, function()
        local cmd = [[
            PID=$(pgrep -x redshift)
            if [ -n "$PID" ]; then
                redshift -x 2>/dev/null
                kill "$PID" 2>/dev/null
                echo "false"
            else
                redshift -l 0:0 -t 2400:2400 -r &>/dev/null &
                echo "true"
            fi
        ]]
        awful.spawn.easy_async({"bash", "-c", cmd}, function(stdout)
            night_state = (stdout:match("true") ~= nil)
            local f = io.open(night_state_file, "w")
            if f then f:write(tostring(night_state)) f:close() end
            update_night_visual()
        end)
    end)))

    -- Do not disturb
    local dnd_icon = wibox.widget{
        font = beautiful.icon_var .. "12",
        markup = helpers.colorize_text(" ", beautiful.fg_color .. "4D"),
        widget = wibox.widget.textbox,
        valign = "center",
        align = "center"
    }
    local dnd_circle = wibox.widget{
        widget = wibox.container.background,
        shape = helpers.rrect((beautiful.rounded or 4) - 3),
        bg = beautiful.accent,
        forced_width = dpi(45),
        forced_height = dpi(45),
    }
    local dnd_anim = rubato.timed{
        pos = 0, rate = 60, intro = 0.08, duration = 0.3,
        awestore_compat = true,
        subscribed = function(pos) dnd_circle.opacity = pos end
    }
    local dnd_state = false
    local dnd_btn = wibox.widget{
        {
            {
                nil,
                { dnd_circle, layout = wibox.layout.fixed.horizontal },
                layout = wibox.layout.align.horizontal,
                expand = "none"
            },
            {
                nil,
                {
                    dnd_icon,
                    layout = wibox.layout.fixed.vertical,
                    spacing = dpi(10)
                },
                layout = wibox.layout.align.vertical,
                expand = "none"
            },
            layout = wibox.layout.stack
        },
        shape = gears.shape.circle,
        widget = wibox.container.background,
        border_color = beautiful.fg_color .. "33",
        forced_width = btn_size,
        forced_height = btn_size,
        bg = beautiful.bg_3
    }
    local function update_dnd_visual()
        dnd_icon.markup = helpers.colorize_text(" ", dnd_state and beautiful.accent or beautiful.fg_color .. "4D")
        dnd_anim.target = dnd_state and 0.09 or 0
    end
    do
        local output = readwrite.readall("dnd_state")
        local boolconverter = { ["true"] = true, ["false"] = false }
        dnd_state = boolconverter[output] or false
        update_dnd_visual()
    end
    dnd_btn:buttons(gears.table.join(awful.button({}, 1, function()
        dnd_state = not dnd_state
        readwrite.write("dnd_state", tostring(dnd_state))
        if dnd_state then
            awful.spawn.with_shell("dunstctl set-paused true")
        else
            awful.spawn.with_shell("dunstctl set-paused false")
        end
        update_dnd_visual()
    end)))

    return wibox.widget{
        inhibit_btn,
        night_btn,
        dnd_btn,
        layout = wibox.layout.fixed.horizontal,
        spacing = dpi(10)
    }
end

-- Enhanced time widget with date and weather
local LAT = user_likes.lat or 9.099724
local LON = user_likes.lon or -94.578331
local USE_FAHRENHEIT = true

local function get_weather_emoji(code)
    code = tonumber(code)
    if not code then return "☁️" end
    local weather_map = {
        [0]  = "☀️", [1]  = "🌤️", [2]  = "⛅", [3]  = "☁️",
        [45] = "🌫️", [48] = "🌫️",
        [51] = "🌦️", [53] = "🌦️", [55] = "🌧️",
        [56] = "🌨️", [57] = "🌨️",
        [61] = "🌧️", [63] = "🌧️", [65] = "🌧️",
        [66] = "🌨️", [67] = "🌨️",
        [71] = "🌨️", [73] = "🌨️", [75] = "❄️", [77] = "❄️",
        [80] = "🌦️", [81] = "🌧️", [82] = "⛈️",
        [85] = "🌨️", [86] = "❄️",
        [95] = "⛈️", [96] = "⛈️", [99] = "⛈️",
    }
    return weather_map[code] or "❓"
end

local weather_icon = wibox.widget{
    font = beautiful.icon_var .. "12",
    markup = helpers.colorize_text("⛅", beautiful.fg_color .. "4D"),
    widget = wibox.widget.textbox,
    align = "center",
    valign = "center"
}
local weather_temp = wibox.widget{
    font = beautiful.font_var .. "Bold 12",
    markup = helpers.colorize_text("--°F", beautiful.fg_color .. "4D"),
    widget = wibox.widget.textbox,
    align = "center",
    valign = "center"
}

local function update_weather()
    local url = string.format(
        "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current_weather=true&units=metric",
        LAT, LON
    )
    awful.spawn.easy_async({"curl", "-s", url}, function(stdout)
        local temp_match = stdout:match('"temperature":%s*(-?%d+%.?%d*)')
        local code_match = stdout:match('"weathercode":%s*(%d+)')
        if not temp_match or not code_match then return end
        local temp_c = tonumber(temp_match)
        local temp_display = USE_FAHRENHEIT and math.floor(temp_c * 9 / 5 + 32) or math.floor(temp_c)
        local code = tonumber(code_match)
        local icon = get_weather_emoji(code)
        weather_icon.markup = helpers.colorize_text(icon, beautiful.fg_color)
        weather_temp.markup = helpers.colorize_text(temp_display .. (USE_FAHRENHEIT and "°F" or "°C"), beautiful.fg_color)
    end)
end

gtimer {
    timeout = 1800,
    callback = update_weather,
    autostart = true,
}
update_weather()

local time_hour = wibox.widget{
    font = "JetBrainsMono Nerd Font Bold 13",
    format = "%H:",
    widget = wibox.widget.textclock
}
local time_min = wibox.widget{
    font = "JetBrainsMono Nerd Font Bold 13",
    format = "%M",
    widget = wibox.widget.textclock
}
local time_day = wibox.widget{
    font = beautiful.font_var .. "11",
    format = "%a, ",
    widget = wibox.widget.textclock
}
local time_date = wibox.widget{
    font = beautiful.font_var .. "11",
    format = "%d ",
    widget = wibox.widget.textclock
}
local time_mon = wibox.widget{
    font = beautiful.font_var .. "11",
    format = "de %b",
    widget = wibox.widget.textclock
}

local fg = beautiful.fg_color
local fg_dim = beautiful.fg_color .. "99"

-- reliable color updates via timer instead of signals
gtimer {
    timeout = 1,
    callback = function()
        time_hour.markup = helpers.colorize_text(time_hour.text, fg)
        time_min.markup = helpers.colorize_text(time_min.text, fg)
        time_day.markup = helpers.colorize_text(time_day.text, fg_dim)
        time_date.markup = helpers.colorize_text(time_date.text, fg_dim)
        time_mon.markup = helpers.colorize_text(time_mon.text, fg_dim)
    end,
    autostart = true,
}

local weather_part = wibox.widget{
    weather_icon,
    weather_temp,
    layout = wibox.layout.fixed.horizontal,
    spacing = dpi(4)
}

local time_part = wibox.widget{
    time_hour,
    time_min,
    layout = wibox.layout.fixed.horizontal,
    spacing = dpi(1)
}

local date_part = wibox.widget{
    {
        time_day,
        time_date,
        time_mon,
        layout = wibox.layout.fixed.horizontal,
        spacing = dpi(1)
    },
    widget = wibox.container.margin,
    left = dpi(10),
    right = dpi(10)
}

local time_wid = wibox.widget{
    {
        time_part,
        date_part,
        weather_part,
        layout = wibox.layout.fixed.horizontal,
        spacing = dpi(10)
    },
    widget = wibox.container.background,
    bg = beautiful.bg_2 .. "33",
    shape = helpers.rrect(beautiful.rounded_wids or dpi(6)),
    forced_height = dpi(40)
}

local function create_clipboard_widget(self, entry)
    local icon_text = entry.is_image and "🖼️" or "📋"
    local item = wibox.widget {
        widget = wibox.container.background, id = "background", forced_height = dpi(60),
        shape = self.app_shape or gears.shape.rounded_rect, bg = self.app_normal_color or beautiful.bg_normal,
        {
            widget = wibox.container.margin, margins = { left = dpi(15), right = dpi(15) },
            {
                layout = wibox.layout.fixed.horizontal, spacing = dpi(15),
                { widget = wibox.widget.textbox, markup = string.format("<span size='large' foreground='%s'>%s</span>", self.app_name_normal_color or beautiful.fg_normal, icon_text), valign = "center" },
                { widget = wibox.widget.textbox, id = "name", text = entry.text, valign = "center", align = "left", font = self.app_name_font or beautiful.font, ellipsize = "end", forced_width = dpi(400) }
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
    item:connect_signal("button::press", function() self.clipboard_select(entry.id); self:hide() end)
    return item
end

local function render_clipboard_list(self, items)
    self._private.clipboard_grid:reset()
    self._private.clipboard_items = items
    local max_items = 10
    for i = 1, math.min(#items, max_items) do self._private.clipboard_grid:add(create_clipboard_widget(self, items[i])) end
    if #items > 0 then select_app(self, 1, 1) else unselect_app(self) end
end

local function clipboard_scroll_up(self)
    local grid = self._private.clipboard_grid
    if not grid or #grid.children < 1 then return end
    local pos = grid:get_widget_position(self._private.active_widget)
    if pos and pos.row > 1 then unselect_app(self); select_app(self, pos.row - 1, 1) end
end

local function clipboard_scroll_down(self)
    local grid = self._private.clipboard_grid
    if not grid or #grid.children < 1 then return end
    local pos = grid:get_widget_position(self._private.active_widget)
    if pos and pos.row < #grid.children then unselect_app(self); select_app(self, pos.row + 1, 1) end
end

-- Power profiles mode
local power_profiles_mode = {}
power_profiles_mode.profiles = {
    { label = "powersave",  ppd = "power-saver" },
    { label = "balanced",   ppd = "balanced" },
    { label = "performance", ppd = "performance" }
}
power_profiles_mode.current_profile_idx = 2

function power_profiles_mode.create_widget(self, forced_width, forced_height)
    local grid = wibox.widget {
        layout = wibox.layout.grid,
        orientation = "vertical",
        homogeneous = true,
        expand = true,
        spacing = dpi(8),
        forced_num_rows = 3,
        forced_num_cols = 1,
        forced_width = forced_width,
        forced_height = forced_height,
        visible = false
    }

    self._private.power_profile_buttons = {}
    self._private.power_profile_textboxes = {}
    self._private.power_profile_selected_row = power_profiles_mode.current_profile_idx

    local accent = beautiful.accent or beautiful.fg_focus or "#ffffff"
    local normal_bg = beautiful.bg_normal or beautiful.bg_2
    local normal_fg = beautiful.fg_normal or beautiful.fg_color

    for i, profile in ipairs(power_profiles_mode.profiles) do
        local btn_text = wibox.widget {
            widget = wibox.widget.textbox,
            markup = helpers.colorize_text(profile.label, i == power_profiles_mode.current_profile_idx and accent or normal_fg),
            font = beautiful.font .. " 10",
            align = "center",
            valign = "center"
        }
        local is_selected = (i == power_profiles_mode.current_profile_idx)
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
            power_profiles_mode.select_active(self)
        end)

        grid:add(btn_container)
    end

    return grid
end

function power_profiles_mode.handle_search(self, text)
    self._private.power_profile_selected_row = power_profiles_mode.current_profile_idx
    power_profiles_mode.update_highlight(self)
end

function power_profiles_mode.update_highlight(self, selected_row)
    selected_row = selected_row or self._private.power_profile_selected_row or power_profiles_mode.current_profile_idx
    local accent = beautiful.accent or beautiful.fg_focus or "#ffffff"
    local normal_bg = beautiful.bg_normal or beautiful.bg_2
    local normal_fg = beautiful.fg_normal or beautiful.fg_color
    for i = 1, #self._private.power_profile_buttons do
        local is_active = (i == selected_row)
        self._private.power_profile_textboxes[i].markup = helpers.colorize_text(power_profiles_mode.profiles[i].label, is_active and accent or normal_fg)
        self._private.power_profile_buttons[i].bg = is_active and ((#accent == 7) and (accent .. "22") or accent) or normal_bg
    end
end

function power_profiles_mode.scroll_up(self)
    local row = self._private.power_profile_selected_row or power_profiles_mode.current_profile_idx
    if row > 1 then
        self._private.power_profile_selected_row = row - 1
        power_profiles_mode.update_highlight(self)
    end
end

function power_profiles_mode.scroll_down(self)
    local row = self._private.power_profile_selected_row or power_profiles_mode.current_profile_idx
    if row < #power_profiles_mode.profiles then
        self._private.power_profile_selected_row = row + 1
        power_profiles_mode.update_highlight(self)
    end
end

function power_profiles_mode.select_active(self)
    local row = self._private.power_profile_selected_row or power_profiles_mode.current_profile_idx
    if row < 1 or row > #power_profiles_mode.profiles then return end

    power_profiles_mode.current_profile_idx = row
    power_profiles_mode.update_highlight(self)

    local profile = power_profiles_mode.profiles[row]
    if profile then
        local DBUS_NAME  = "org.freedesktop.UPower.PowerProfiles"
        local DBUS_PATH  = "/org/freedesktop/UPower/PowerProfiles"
        local DBUS_IFACE = "org.freedesktop.UPower.PowerProfiles"
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

-- Refresh rate mode
local refresh_rate_mode = {}
refresh_rate_mode.profiles = {
    { label = "60hz",  cmd = nil },
    { label = "120hz", cmd = nil },
    { label = "144hz", cmd = nil }
}
refresh_rate_mode.current_profile_idx = 1

function refresh_rate_mode.create_widget(self, forced_width, forced_height)
    local grid = wibox.widget {
        layout = wibox.layout.grid,
        orientation = "vertical",
        homogeneous = true,
        expand = true,
        spacing = dpi(8),
        forced_num_rows = 3,
        forced_num_cols = 1,
        forced_width = forced_width,
        forced_height = forced_height,
        visible = false
    }

    self._private.refresh_rate_buttons = {}
    self._private.refresh_rate_textboxes = {}
    self._private.refresh_rate_selected_row = refresh_rate_mode.current_profile_idx

    local accent = beautiful.accent or beautiful.fg_focus or "#ffffff"
    local normal_bg = beautiful.bg_normal or beautiful.bg_2
    local normal_fg = beautiful.fg_normal or beautiful.fg_color

    for i, profile in ipairs(refresh_rate_mode.profiles) do
        local btn_text = wibox.widget {
            widget = wibox.widget.textbox,
            markup = helpers.colorize_text(profile.label, i == refresh_rate_mode.current_profile_idx and accent or normal_fg),
            font = beautiful.font .. " 10",
            align = "center",
            valign = "center"
        }
        local is_selected = (i == refresh_rate_mode.current_profile_idx)
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
            refresh_rate_mode.select_active(self)
        end)

        grid:add(btn_container)
    end

    return grid
end

function refresh_rate_mode.handle_search(self, text)
    self._private.refresh_rate_selected_row = refresh_rate_mode.current_profile_idx
    refresh_rate_mode.update_highlight(self)
end

function refresh_rate_mode.update_highlight(self, selected_row)
    selected_row = selected_row or self._private.refresh_rate_selected_row or refresh_rate_mode.current_profile_idx
    local accent = beautiful.accent or beautiful.fg_focus or "#ffffff"
    local normal_bg = beautiful.bg_normal or beautiful.bg_2
    local normal_fg = beautiful.fg_normal or beautiful.fg_color
    for i = 1, #self._private.refresh_rate_buttons do
        local is_active = (i == selected_row)
        self._private.refresh_rate_textboxes[i].markup = helpers.colorize_text(refresh_rate_mode.profiles[i].label, is_active and accent or normal_fg)
        self._private.refresh_rate_buttons[i].bg = is_active and ((#accent == 7) and (accent .. "22") or accent) or normal_bg
    end
end

function refresh_rate_mode.scroll_up(self)
    local row = self._private.refresh_rate_selected_row or refresh_rate_mode.current_profile_idx
    if row > 1 then
        self._private.refresh_rate_selected_row = row - 1
        refresh_rate_mode.update_highlight(self)
    end
end

function refresh_rate_mode.scroll_down(self)
    local row = self._private.refresh_rate_selected_row or refresh_rate_mode.current_profile_idx
    if row < #refresh_rate_mode.profiles then
        self._private.refresh_rate_selected_row = row + 1
        refresh_rate_mode.update_highlight(self)
    end
end

function refresh_rate_mode.select_active(self)
    local row = self._private.refresh_rate_selected_row or refresh_rate_mode.current_profile_idx
    if row < 1 or row > #refresh_rate_mode.profiles then return end

    refresh_rate_mode.current_profile_idx = row
    refresh_rate_mode.update_highlight(self)

    local profile = refresh_rate_mode.profiles[row]
    if profile and profile.cmd then
        awful.spawn.easy_async_with_shell(profile.cmd, function(stdout, stderr)
            -- xrandr commands are fire-and-forget
        end)
    end
end

-- Notification mode
local notification_mode = {}
notification_mode.notifications = {}
notification_mode.current_index = 1
notification_mode.current_self = nil
notification_mode.forced_width = nil
notification_mode.forced_height = nil

function notification_mode.create_widget(self, forced_width, forced_height)
    notification_mode.current_self = self
    notification_mode.forced_width = forced_width
    notification_mode.forced_height = forced_height
    
    -- Container for notifications
    local notifs_container = wibox.widget {
        layout = wibox.layout.fixed.vertical,
        spacing = dpi(8)
    }
    self._private.notification_container = notifs_container
    self._private.notification_items = {}
    self._private.notification_buttons = {}
    self._private.notification_textboxes = {}
    self._private.notification_selected_row = 1
    
    -- Empty state
    local empty = wibox.widget {
        widget = wibox.widget.textbox,
        markup = helpers.colorize_text("No notifications", beautiful.fg_color .. "99"),
        font = beautiful.font_var .. "10",
        align = "center",
        valign = "center"
    }
    self._private.notification_empty = empty
    notifs_container:add(empty)
    
    -- Listen for new notifications (only once)
    if not notification_mode.signal_connected then
        naughty.connect_signal("request::display", function(n)
            if notification_mode.current_self then
                notification_mode.add_notification(notification_mode.current_self, n)
            end
        end)
        notification_mode.signal_connected = true
    end
    
    -- Main widget with forced dimensions
    local widget = wibox.widget {
        notifs_container,
        layout = wibox.layout.fixed.vertical,
        forced_width = forced_width,
        forced_height = forced_height,
        visible = false
    }
    
    return widget
end

function notification_mode.create_notification_widget(self, n)
    local time = os.date("%H:%M")
    
    -- App icon with accent background like dashboard
    local app_icon = wibox.widget {
        {
            font = beautiful.icon_var .. "11",
            markup = helpers.colorize_text("󰣆 ", beautiful.accent),
            widget = wibox.widget.textbox,
            align = "center",
            valign = "center"
        },
        bg = beautiful.accent .. "1A",
        widget = wibox.container.background,
        forced_height = dpi(20),
        forced_width = dpi(28)
    }
    
    -- Title (scrollable like dashboard)
    local title = wibox.widget {
        {
            markup = helpers.colorize_text(n.title or "Notification", beautiful.fg_color),
            font = beautiful.font_var .. " Bold 10",
            align = "left",
            valign = "center",
            widget = wibox.widget.textbox
        },
        layout = wibox.layout.align.horizontal,
        widget = wibox.container.scroll.horizontal,
        step_function = wibox.container.scroll.step_functions.waiting_nonlinear_back_and_forth,
        speed = 50
    }
    
    -- Message/body (scrollable like dashboard)
    local message = wibox.widget {
        {
            markup = helpers.colorize_text(n.message or "", beautiful.fg_color .. "CC"),
            font = beautiful.font_var .. "9",
            align = "left",
            valign = "top",
            widget = wibox.widget.textbox
        },
        layout = wibox.layout.align.horizontal,
        widget = wibox.container.scroll.horizontal,
        step_function = wibox.container.scroll.step_functions.waiting_nonlinear_back_and_forth,
        speed = 50
    }
    
    -- Time
    local time_text = wibox.widget {
        markup = helpers.colorize_text(time, beautiful.fg_color .. "99"),
        font = beautiful.font_var .. "9",
        align = "right",
        valign = "center",
        widget = wibox.widget.textbox
    }
    
    -- Notification item matching dashboard layout
    local content = wibox.widget {
        {
            {
                app_icon,
                {
                    title,
                    message,
                    layout = wibox.layout.fixed.vertical,
                    spacing = dpi(3)
                },
                layout = wibox.layout.align.horizontal,
                expand = "none"
            },
            time_text,
            layout = wibox.layout.align.horizontal,
            expand = "none"
        },
        margins = { left = dpi(12), right = dpi(12), top = dpi(10), bottom = dpi(10) },
        widget = wibox.container.margin
    }
    
    local item = wibox.widget {
        content,
        widget = wibox.container.background,
        bg = beautiful.bg_3,
        shape = helpers.rrect(beautiful.rounded),
        forced_height = dpi(60)
    }
    
    return item
end

function notification_mode.add_notification(self, n)
    -- Guard: ensure notification_items table exists
    if not self._private.notification_items then
        self._private.notification_items = {}
    end
    
    -- Remove empty state if present
    if self._private.notification_empty and self._private.notification_empty.visible then
        self._private.notification_empty.visible = false
        if self._private.notification_container then
            self._private.notification_container:remove_widgets()
        end
    end
    
    -- Create and add notification
    local item = notification_mode.create_notification_widget(self, n)
    
    -- Store reference
    table.insert(self._private.notification_items, {
        widget = item,
        notification = n
    })
    
    -- Add to container
    if self._private.notification_container then
        self._private.notification_container:add(item)
    end
    
    -- Update selection
    notification_mode.update_highlight(self, self._private.notification_selected_row)
end

function notification_mode.dismiss_notification(self, row)
    if row < 1 or row > #self._private.notification_items then return end
    
    -- Remove from list
    table.remove(self._private.notification_items, row)
    
    -- Rebuild container
    local container = self._private.notification_container
    container:reset()
    
    -- Show empty state if no notifications
    if #self._private.notification_items == 0 then
        self._private.notification_empty.visible = true
        container:add(self._private.notification_empty)
    else
        for i, item in ipairs(self._private.notification_items) do
            container:add(item.widget)
        end
    end
    
    -- Adjust selection
    local new_row = math.min(self._private.notification_selected_row, #self._private.notification_items)
    self._private.notification_selected_row = new_row
    notification_mode.update_highlight(self, new_row)
end

function notification_mode.clear_all(self)
    local container = self._private.notification_container
    container:reset()
    self._private.notification_empty.visible = true
    container:add(self._private.notification_empty)
    self._private.notification_items = {}
    self._private.notification_buttons = {}
    self._private.notification_textboxes = {}
    self._private.notification_selected_row = 1
end

function notification_mode.scroll_up(self)
    local row = self._private.notification_selected_row
    if row > 1 then
        self._private.notification_selected_row = row - 1
        notification_mode.update_highlight(self, row - 1)
    end
end

function notification_mode.scroll_down(self)
    local row = self._private.notification_selected_row
    if row < #self._private.notification_items then
        self._private.notification_selected_row = row + 1
        notification_mode.update_highlight(self, row + 1)
    end
end

function notification_mode.handle_search(self, text)
    self._private.notification_selected_row = 1
    notification_mode.update_highlight(self, 1)
end

function notification_mode.update_highlight(self, selected_row)
    selected_row = selected_row or self._private.notification_selected_row
    local accent = beautiful.accent or beautiful.fg_focus or "#ffffff"
    local normal_bg = beautiful.bg_3
    local hover_bg = beautiful.fg_color .. "0D"
    local normal_fg = beautiful.fg_color
    
    for i, item in ipairs(self._private.notification_items) do
        local is_active = (i == selected_row)
        if item.widget then
            item.widget.bg = is_active and hover_bg or normal_bg
        end
    end
end

function notification_mode.select_active(self)
    local row = self._private.notification_selected_row
    if row < 1 or row > #self._private.notification_items then return end
    
    notification_mode.dismiss_notification(self, row)
    self._private.notification_selected_row = math.min(row, #self._private.notification_items)
    notification_mode.update_highlight(self, self._private.notification_selected_row)
end

local function render_emoji_grid(self)
    self._private.emoji_grid:reset()
    local filtered = self._private.emoji_filtered or {}
    local offset = self._private.emoji_offset or 0
    local limit = math.min(#filtered - offset, 75)
    for i = 1, limit do
        local idx = offset + i
        local em = filtered[idx]
        if not em then break end
        local bg = wibox.widget {
            widget = wibox.container.background, forced_width = dpi(55), forced_height = dpi(55),
            shape = self.app_shape or gears.shape.rounded_rect, bg = self.app_normal_color or beautiful.bg_normal,
            { widget = wibox.widget.textbox, text = em.unicode, align = "center", valign = "center", font = "Noto Color Emoji 18", ellipsize = "none" }
        }
        awful.tooltip { objects = { bg }, text = em.name, mode = "outside", align = "top", preferred_positions = { "top", "bottom", "right", "left"} }
        bg:connect_signal("button::press", function()
            local copy_cmd = string.format("printf '%%s' '%s' | xclip -selection clipboard 2>/dev/null || printf '%%s' '%s' | xsel --clipboard --input 2>/dev/null || printf '%%s' '%s' | wl-copy 2>/dev/null || copyq add '%s' 2>/dev/null", em.unicode, em.unicode, em.unicode, em.unicode)
            awful.spawn.with_shell(copy_cmd); self:hide()
        end)
        bg:connect_signal("mouse::enter", function() bg.bg = beautiful.bg_focus or "#555555" end)
        bg:connect_signal("mouse::leave", function() bg.bg = beautiful.bg_normal or "#333333" end)
        self._private.emoji_grid:add(wibox.widget { widget = wibox.container.margin, margins = dpi(2), bg })
    end
end

local function new(args)
    args = args or {}
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

    args.default_app_icon_name = args.default_app_icon_name or nil
    args.default_app_icon_path = args.default_app_icon_path or nil
    args.icon_theme = args.icon_theme or nil
    args.icon_size = args.icon_size or nil

    args.type = args.type or "dock"
    args.show_on_focused_screen = args.show_on_focused_screen == nil and true or args.show_on_focused_screen
    args.screen = args.screen or capi.screen.primary
    args.placement = args.placement or awful.placement.centered
    args.rubato = args.rubato or nil
    args.shrink_width = args.shrink_width ~= nil and args.shrink_width or false
    args.shrink_height = args.shrink_height ~= nil and args.shrink_height or false
    args.background = args.background or "#000000"
    args.shape = args.shape or nil

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
    args.prompt_icon_markup = args.prompt_icon_markup or string.format("<span size='xx-large' foreground='%s'>%s</span>", args.prompt_icon_color, args.prompt_icon)
    args.prompt_text = args.prompt_text or "<b>Search</b>: "
    args.prompt_start_text = args.prompt_start_text or ""
    args.prompt_font = args.prompt_font or beautiful.font
    args.prompt_text_color = args.prompt_text_color or beautiful.bg_normal or "#000000"
    args.prompt_cursor_color = args.prompt_cursor_color or beautiful.bg_normal or "#000000"

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

    args.apps_per_row = args.apps_per_row or 5
    args.apps_per_column = args.apps_per_column or 3
    args.apps_margin = args.apps_margin or dpi(30)
    args.apps_spacing = args.apps_spacing or dpi(30)

    args.expand_apps = args.expand_apps == nil and true or args.expand_apps
    args.app_width = args.app_width or dpi(300)
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

    local ret = gobject({})
    ret._private = {}
    ret._private.text = ""
    ret._private.emoji_offset = 0

    gtable.crush(ret, app_launcher)
    gtable.crush(ret, args)

    local grid_width = ret.shrink_width == false and dpi((ret.app_width * ret.apps_per_column) + ((ret.apps_per_column - 1) * ret.apps_spacing)) or nil
    local grid_height = ret.shrink_height == false and dpi((ret.app_height * ret.apps_per_row) + ((ret.apps_per_row - 1) * ret.apps_spacing)) or nil

    ret._private.emoji_mode = false
    ret._private.clipboard_mode = false
    ret._private.power_profile_mode = false
    ret._private.refresh_rate_mode = false
    ret._private.notification_mode = false
    ret._private.active_grid = ret._private.grid

    ret._private.prompt = prompt {
        prompt = ret.prompt_text, text = ret.prompt_start_text, font = ret.prompt_font,
        reset_on_stop = ret.reset_on_hide, bg_cursor = ret.prompt_cursor_color,
        history_path = ret.save_history == true and gfilesystem.get_cache_dir() .. "/history" or nil,
        
        changed_callback = function(text)
            if text == ret._private.text then return end
            local is_emoji = text:match("^:")
            local is_clipboard = text:match("^;")
            local is_math = text:match("^=")
            local is_power_profile = text:match("^`")
            local is_refresh_rate = text:match("^~")
            local is_notification = text:match("^!")
            
            ret._private.emoji_mode = is_emoji
            ret._private.clipboard_mode = is_clipboard
            ret._private.math_mode = is_math
            ret._private.power_profile_mode = is_power_profile
            ret._private.refresh_rate_mode = is_refresh_rate
            ret._private.notification_mode = is_notification

            if is_math then
                ret._private.grid.visible = false; ret._private.emoji_grid.visible = false; ret._private.clipboard_grid.visible = false; ret._private.math_widget.visible = true
                ret._private.power_profiles_widget.visible = false; ret._private.refresh_rate_widget.visible = false
                ret._private.active_grid = nil
                evaluate_math(text, function(result)
                    local result_widget = ret._private.math_widget:get_children_by_id("math_result")[1]
                    if result_widget then
                        local color_res = result:lower():match("error") and beautiful.fg_urgent or (ret.app_name_normal_color or beautiful.fg_normal)
                        result_widget.markup = string.format("<span foreground='%s'>= %s</span>", color_res, result)
                    end
                end)
            elseif is_clipboard then
                ret._private.grid.visible = false; ret._private.emoji_grid.visible = false; ret._private.clipboard_grid.visible = true
                ret._private.power_profiles_widget.visible = false; ret._private.refresh_rate_widget.visible = false; ret._private.math_widget.visible = false
                ret._private.active_grid = ret._private.clipboard_grid
                local query = text:sub(2):lower()
                
                local function process_items(items)
                    local filtered = {}
                    for _, item in ipairs(items) do
                        if query == "" or item.text:lower():find(query, 1, true) then
                            table.insert(filtered, item)
                        end
                    end
                    render_clipboard_list(ret, filtered)
                end

                if not ret._private.clipboard_items_cache then
                    ret.clipboard_fetch(function(items)
                        ret._private.clipboard_items_cache = items
                        process_items(items)
                    end)
                else
                    process_items(ret._private.clipboard_items_cache)
                end
            elseif is_power_profile then
                ret._private.grid.visible = false; ret._private.emoji_grid.visible = false; ret._private.clipboard_grid.visible = false; ret._private.math_widget.visible = false
                ret._private.refresh_rate_widget.visible = false
                ret._private.power_profiles_widget.visible = true
                ret._private.active_grid = nil
                power_profiles_mode.handle_search(ret, text)
            elseif is_refresh_rate then
                ret._private.grid.visible = false; ret._private.emoji_grid.visible = false; ret._private.clipboard_grid.visible = false; ret._private.math_widget.visible = false
                ret._private.power_profiles_widget.visible = false
                ret._private.refresh_rate_widget.visible = true
                ret._private.active_grid = nil
                refresh_rate_mode.handle_search(ret, text)
            elseif is_notification then
                ret._private.grid.visible = false; ret._private.emoji_grid.visible = false; ret._private.clipboard_grid.visible = false; ret._private.math_widget.visible = false
                ret._private.power_profiles_widget.visible = false; ret._private.refresh_rate_widget.visible = false
                ret._private.notification_widget.visible = true
                ret._private.active_grid = nil
                notification_mode.handle_search(ret, text)
            elseif is_emoji then
                ret._private.grid.visible = false; ret._private.emoji_grid.visible = true; ret._private.clipboard_grid.visible = false
                ret._private.power_profiles_widget.visible = false; ret._private.refresh_rate_widget.visible = false; ret._private.math_widget.visible = false
                ret._private.active_grid = ret._private.emoji_grid
                ret._private.emoji_filtered = emoji.filter_emojis(emoji.emojis, text:sub(2):lower())
                ret._private.emoji_offset = 0
                render_emoji_grid(ret)
            else
                ret._private.grid.visible = true; ret._private.emoji_grid.visible = false; ret._private.clipboard_grid.visible = false; ret._private.math_widget.visible = false
                ret._private.power_profiles_widget.visible = false; ret._private.refresh_rate_widget.visible = false; ret._private.notification_widget.visible = false
                ret._private.active_grid = ret._private.grid
                search(ret, text)
            end
            ret._private.text = text
        end,

        keypressed_callback = function(mod, key, cmd)
            if key == "Escape" then ret:hide(); return true end
            
            if key == "Return" or key == "KP_Enter" then
                if ret._private.math_mode then
                    local result_widget = ret._private.math_widget:get_children_by_id("math_result")[1]
                    if result_widget and not result_widget.text:match("Error") and not result_widget.text:match("%.%.%.") then
                        local clean_result = result_widget.text:gsub("^=%s*", "")
                        awful.spawn.with_shell(string.format("printf '%%s' '%s' | xclip -selection clipboard 2>/dev/null || printf '%%s' '%s' | wl-copy 2>/dev/null", clean_result, clean_result))
                        ret:hide()
                    end
                    return true
                elseif ret._private.emoji_mode then
                    local offset = ret._private.emoji_offset or 0
                    local first_emoji = ret._private.emoji_filtered and ret._private.emoji_filtered[offset + 1]
                    if first_emoji then
                        local copy_cmd = string.format("printf '%%s' '%s' | xclip -selection clipboard 2>/dev/null || printf '%%s' '%s' | xsel --clipboard --input 2>/dev/null || printf '%%s' '%s' | wl-copy 2>/dev/null || copyq add '%s' 2>/dev/null", first_emoji.unicode, first_emoji.unicode, first_emoji.unicode, first_emoji.unicode)
                        awful.spawn.with_shell(copy_cmd)
                        ret:hide()
                    end
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
                elseif ret._private.power_profile_mode then
                    power_profiles_mode.select_active(ret)
                    ret:hide()
                    return true
                elseif ret._private.refresh_rate_mode then
                    refresh_rate_mode.select_active(ret)
                    ret:hide()
                    return true
                elseif ret._private.notification_mode then
                    notification_mode.select_active(ret)
                    ret:hide()
                    return true
                else
                    if ret._private.active_widget then ret._private.active_widget.spawn() end
                    return true
                end
            end
            
            if ret._private.clipboard_mode then
                if key == "Up" then clipboard_scroll_up(ret) end
                if key == "Down" then clipboard_scroll_down(ret) end
            elseif ret._private.power_profile_mode then
                if key == "Up" then power_profiles_mode.scroll_up(ret) end
                if key == "Down" then power_profiles_mode.scroll_down(ret) end
            elseif ret._private.refresh_rate_mode then
                if key == "Up" then refresh_rate_mode.scroll_up(ret) end
                if key == "Down" then refresh_rate_mode.scroll_down(ret) end
            elseif ret._private.notification_mode then
                if key == "Up" then notification_mode.scroll_up(ret) end
                if key == "Down" then notification_mode.scroll_down(ret) end
            elseif not ret._private.emoji_mode then
                if key == "Up" then scroll_up(ret) end
                if key == "Down" then scroll_down(ret) end
                if key == "Left" then scroll_left(ret) end
                if key == "Right" then scroll_right(ret) end
                if key == "Print" then awful.spawn(os.getenv("HOME") .. "/.scripts/ss full", false) end
            end
            return false
        end
    }

    ret._private.grid = wibox.widget {
        layout = wibox.layout.grid, forced_width = grid_width, forced_height = grid_height, orientation = "horizontal",
        homogeneous = true, expand = ret.expand_apps, spacing = ret.apps_spacing, forced_num_rows = ret.apps_per_row,
        buttons = { awful.button({}, 4, function() scroll_up(ret) end), awful.button({}, 5, function() scroll_down(ret) end) }
    }

    ret._private.emoji_grid = wibox.widget {
        layout = wibox.layout.grid, orientation = "vertical", homogeneous = true, expand = true, spacing = dpi(8),
        forced_num_rows = 15, forced_num_cols = 5, forced_width = grid_width, forced_height = grid_height, visible = false,
        buttons = {
            awful.button({}, 4, function() ret._private.emoji_offset = math.max(0, (ret._private.emoji_offset or 0) - 15); render_emoji_grid(ret) end),
            awful.button({}, 5, function() local max_offset = math.max(0, #ret._private.emoji_filtered - 75); ret._private.emoji_offset = math.min(max_offset, (ret._private.emoji_offset or 0) + 15); render_emoji_grid(ret) end)
        }
    }

    ret._private.clipboard_grid = wibox.widget {
        layout = wibox.layout.grid, forced_width = grid_width, forced_height = grid_height, orientation = "vertical",
        homogeneous = true, expand = false, spacing = dpi(4), forced_num_cols = 1, visible = false,
        buttons = { awful.button({}, 4, function() clipboard_scroll_up(ret) end), awful.button({}, 5, function() clipboard_scroll_down(ret) end) }
    }

    -- Power profiles widget (hidden by default)
    ret._private.power_profiles_widget = power_profiles_mode.create_widget(ret, grid_width, grid_height)

    -- Refresh rate widget (hidden by default)
    ret._private.refresh_rate_widget = refresh_rate_mode.create_widget(ret, grid_width, grid_height)

    -- Notification widget (hidden by default)
    ret._private.notification_widget = notification_mode.create_widget(ret, grid_width, grid_height)

    ret._private.math_widget = wibox.widget {
        widget = wibox.container.background, forced_height = ret.app_height, shape = ret.app_shape or gears.shape.rounded_rect,
        bg = ret.app_normal_color or beautiful.bg_normal, visible = false,
        { widget = wibox.container.margin, margins = ret.app_content_padding or dpi(10),
            { widget = wibox.widget.textbox, id = "math_result", font = ret.app_name_font or beautiful.font, align = "center", valign = "center",
              markup = string.format("<span foreground='%s'>= ...</span>", ret.app_name_normal_color or beautiful.fg_normal) } }
    }

    ret._private.math_widget:connect_signal("button::press", function()
        local result_widget = ret._private.math_widget:get_children_by_id("math_result")[1]
        if result_widget and not result_widget.text:lower():match("error") and not result_widget.text:match("%.%.%.") then
            local clean_result = result_widget.text:gsub("^=%s*", "")
            awful.spawn.with_shell(string.format("printf '%%s' '%s' | xclip -selection clipboard 2>/dev/null || printf '%%s' '%s' | wl-copy 2>/dev/null", clean_result, clean_result))
            ret:hide()
        end
    end)

    ret._private.widget = awful.popup {
        type = args.type, visible = false, ontop = true,
        placement = ret.placement,
        shape = ret.shape, bg = ret.background,
        widget = {
            {
                {
                    {
                        quicksettings(),
                        time_wid, statuses(), layout = wibox.layout.align.horizontal, expand = "none"
                    },
                    margins = {left = dpi(15), right = dpi(15), top = dpi(20), bottom = dpi(20)}, widget = wibox.container.margin
                },
                widget = wibox.container.background, bg = beautiful.bg_2, forced_height = dpi(70)
            },
            {
                layout = wibox.layout.fixed.vertical,
                {
                    widget = wibox.container.margin, margins = ret.prompt_margins,
                    {
                        widget = wibox.container.background, forced_height = ret.prompt_height, shape = ret.prompt_shape,
                        bg = ret.prompt_color, fg = ret.prompt_text_color, border_width = ret.prompt_border_width, border_color = ret.prompt_border_color,
                        {
                            widget = wibox.container.margin, margins = ret.prompt_paddings,
                            {
                                widget = wibox.container.place, halign = ret.prompt_text_halign, valign = ret.prompt_text_valign,
                                {
                                    layout = wibox.layout.fixed.horizontal, spacing = ret.prompt_icon_text_spacing,
                                    { widget = wibox.widget.textbox, font = ret.prompt_icon_font, markup = ret.prompt_icon_markup },
                                    ret._private.prompt.textbox
                                }
                            }
                        }
                    }
                },
                {
                    widget = wibox.container.margin, margins = ret.apps_margin,
                    { layout = wibox.layout.stack, ret._private.grid, ret._private.emoji_grid, ret._private.clipboard_grid, ret._private.power_profiles_widget, ret._private.refresh_rate_widget, ret._private.notification_widget, ret._private.math_widget }
                }
            },
            layout = wibox.layout.fixed.vertical
        }
    }

    ret._private.max_apps_per_page = ret.apps_per_column * ret.apps_per_row
    ret._private.apps_per_page = ret._private.max_apps_per_page
    ret._private.pages_count = 0
    ret._private.current_page = 1

    generate_apps(ret)
    reset(ret)

    if ret.rubato and ret.rubato.x then ret.rubato.x:subscribe(function(pos) ret._private.widget.x = pos end) end
    if ret.rubato and ret.rubato.y then ret.rubato.y:subscribe(function(pos) ret._private.widget.y = pos end) end

    if ret.hide_on_left_clicked_outside then
        awful.mouse.append_client_mousebinding(awful.button({}, 1, function (c) ret:hide() end))
        awful.mouse.append_global_mousebinding(awful.button({}, 1, function (c) ret:hide() end))
    end
    if ret.hide_on_right_clicked_outside then
        awful.mouse.append_client_mousebinding(awful.button({}, 3, function (c) ret:hide() end))
        awful.mouse.append_global_mousebinding(awful.button({}, 3, function (c) ret:hide() end))
    end

    local kill_old_inotify_process_script = [[ ps x | grep "inotifywait -e modify /usr/share/applications" | grep -v grep | awk '{print $1}' | xargs kill ]]
    local subscribe_script = [[ bash -c "while (inotifywait -e modify /usr/share/applications -qq) do echo; done" ]]
    awful.spawn.easy_async_with_shell(kill_old_inotify_process_script, function()
        awful.spawn.with_line_callback(subscribe_script, {stdout = function(_) generate_apps(ret) end})
    end)

    return ret
end

function app_launcher.text(args)
    args = args or {}
    args.prompt_height = args.prompt_height or dpi(50)
    args.prompt_margins = args.prompt_margins or dpi(30)
    args.prompt_paddings = args.prompt_paddings or dpi(15)
    args.app_width = args.app_width or dpi(300)
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