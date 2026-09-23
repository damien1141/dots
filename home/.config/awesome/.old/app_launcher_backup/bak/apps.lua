---------------------------------------------------------------------------
-- App grid: discovery, widget construction, selection, scrolling, search.
-- Every function takes the launcher `self` as its first argument so this
-- module stays stateless on its own.
---------------------------------------------------------------------------

local Gio = require("lgi").Gio
local awful = require("awful")
local wibox = require("wibox")
local gstring = require("gears.string")
local utils = require("mods.app_launcher.utils")

local math = math
local ipairs = ipairs
local pairs = pairs
local table = table
local string = string
local capi = { mouse = mouse }

local apps = {}

------------------------------------------------------------------
-- Selection
------------------------------------------------------------------

function apps.select_app(self, x, y)
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
                name_widget.markup = string.format("<span foreground='%s'>%s</span>",
                    self.app_name_selected_color, gstring.xml_escape(name_widget.text))
            end

            local generic_name_widget = self._private.active_widget:get_children_by_id("generic_name")[1]
            if generic_name_widget then
                generic_name_widget.markup = string.format("<i><span weight='300' foreground='%s'>%s</span></i>",
                    self.app_name_selected_color, gstring.xml_escape(generic_name_widget.text))
            end
        end
    end
end

function apps.unselect_app(self)
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
            name_widget.markup = string.format("<span foreground='%s'>%s</span>",
                self.app_name_normal_color, gstring.xml_escape(name_widget.text))
        end

        local generic_name_widget = self._private.active_widget:get_children_by_id("generic_name")[1]
        if generic_name_widget then
            generic_name_widget.markup = string.format("<i><span weight='300' foreground='%s'>%s</span></i>",
                self.app_name_normal_color, gstring.xml_escape(generic_name_widget.text))
        end

        self._private.active_widget = nil
    end
end

------------------------------------------------------------------
-- Widget construction
------------------------------------------------------------------

function apps.create_app_widget(self, entry)
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
            markup = entry.generic_name ~= "" and
                "<span weight='300'><i>(" .. gstring.xml_escape(entry.generic_name) .. ")</i></span>" or ""
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
                local terminal_command = utils.terminal_commands_lookup[self.terminal] or self.terminal
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
                apps.unselect_app(self)
                local pos = self._private.grid:get_widget_position(_self)
                apps.select_app(self, pos.row, pos.col)
            end
        end
    end)

    return app
end

------------------------------------------------------------------
-- Search
------------------------------------------------------------------

function apps.search(self, text)
    apps.unselect_app(self)
    local pos = self._private.active_widget and
        self._private.grid:get_widget_position(self._private.active_widget) or {row = 1, col = 1}

    self._private.matched_entries = {}
    self._private.grid:reset()

    if text == "" then
        self._private.matched_entries = self._private.all_entries
    else
        for _, entry in ipairs(self._private.all_entries) do
            local score = utils.get_match_score(text, entry.name)
            if self.search_commands then
                local cmd_score = utils.get_match_score(text, entry.commandline)
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
        table.sort(self._private.matched_entries, function(a, b) return a._score < b._score end)
    end

    for _, entry in ipairs(self._private.matched_entries) do
        if #self._private.grid.children + 1 <= self._private.max_apps_per_page then
            self._private.grid:add(apps.create_app_widget(self, entry))
        end
    end

    self._private.apps_per_page = math.min(#self._private.matched_entries, self._private.max_apps_per_page)
    self._private.pages_count = math.ceil(math.max(1, #self._private.matched_entries) / math.max(1, self._private.apps_per_page))
    self._private.current_page = 1

    if self.try_to_keep_index_after_searching then
        if self._private.grid:get_widgets_at(pos.row, pos.col) == nil then
            local app_widget = self._private.grid.children[#self._private.grid.children]
            if app_widget then
                pos = self._private.grid:get_widget_position(app_widget)
            else
                pos = {row = 1, col = 1}
            end
        end
        apps.select_app(self, pos.row, pos.col)
    else
        apps.select_app(self, 1, 1)
    end
end

------------------------------------------------------------------
-- Pagination + scrolling
------------------------------------------------------------------

function apps.page_backward(self, direction)
    local grid = self._private.active_grid or self._private.grid
    if not grid then return end
    if self._private.current_page > 1 then
        self._private.current_page = self._private.current_page - 1
    elseif self.wrap_page_scrolling and #self._private.matched_entries >= self._private.max_apps_per_page then
        self._private.current_page = self._private.pages_count
    elseif self.wrap_app_scrolling then
        local rows, columns = grid:get_dimension()
        apps.unselect_app(self)
        apps.select_app(self, math.min(rows, #grid.children % self.apps_per_row), columns)
        return
    else
        return
    end

    local pos = grid:get_widget_position(self._private.active_widget)
    if not pos then pos = {row = 1, col = 1} end
    grid:reset()

    local max_app_index = self._private.apps_per_page * self._private.current_page
    local min_app_index = max_app_index - self._private.apps_per_page

    for index, entry in ipairs(self._private.matched_entries) do
        if index > min_app_index and index <= max_app_index then
            grid:add(apps.create_app_widget(self, entry))
        end
    end

    local rows, columns = grid:get_dimension()
    if self._private.current_page < self._private.pages_count then
        if direction == "up" then apps.select_app(self, rows, columns)
        else apps.select_app(self, pos.row, columns) end
    elseif self.wrap_page_scrolling then
        if direction == "up" then apps.select_app(self, math.min(rows, #grid.children % self.apps_per_row), columns)
        else apps.select_app(self, math.min(pos.row, #grid.children % self.apps_per_row), columns) end
    end
end

function apps.page_forward(self, direction)
    local min_app_index = 0
    local max_app_index = self._private.apps_per_page
    if self._private.current_page < self._private.pages_count then
        min_app_index = self._private.apps_per_page * self._private.current_page
        self._private.current_page = self._private.current_page + 1
        max_app_index = self._private.apps_per_page * self._private.current_page
    elseif self.wrap_page_scrolling and #self._private.matched_entries >= self._private.max_apps_per_page then
        self._private.current_page = 1
        min_app_index = 0
        max_app_index = self._private.apps_per_page
    elseif self.wrap_app_scrolling then
        apps.unselect_app(self)
        apps.select_app(self, 1, 1)
        return
    else
        return
    end

    local pos = self._private.grid:get_widget_position(self._private.active_widget)
    if not pos then pos = {row = 1, col = 1} end
    self._private.grid:reset()

    for index, entry in ipairs(self._private.matched_entries) do
        if index > min_app_index and index <= max_app_index then
            self._private.grid:add(apps.create_app_widget(self, entry))
        end
    end

    if self._private.current_page > 1 or self.wrap_page_scrolling then
        if direction == "down" then
            apps.select_app(self, 1, 1)
        else
            local last_col_max_row = math.min(pos.row, #self._private.grid.children % self.apps_per_row)
            if last_col_max_row ~= 0 then apps.select_app(self, last_col_max_row, 1)
            else apps.select_app(self, pos.row, 1) end
        end
    end
end

function apps.scroll_up(self)
    local grid = self._private.active_grid or self._private.grid
    if not grid or #grid.children < 1 then self._private.active_widget = nil return end
    local rows, columns = grid:get_dimension()
    local pos = grid:get_widget_position(self._private.active_widget)
    if not pos then pos = {row = 1, col = 1} end
    if pos.col > 1 or pos.row > 1 then
        apps.unselect_app(self)
        if pos.row == 1 then apps.select_app(self, rows, pos.col - 1)
        else apps.select_app(self, pos.row - 1, pos.col) end
    else
        apps.page_backward(self, "up")
    end
end

function apps.scroll_down(self)
    local grid = self._private.active_grid or self._private.grid
    if not grid or #grid.children < 1 then self._private.active_widget = nil return end
    local rows, columns = grid:get_dimension()
    local pos = grid:get_widget_position(self._private.active_widget)
    if not pos then pos = {row = 1, col = 1} end
    if grid:index(self._private.active_widget) < #grid.children then
        apps.unselect_app(self)
        if pos.row == rows then apps.select_app(self, 1, pos.col + 1)
        else apps.select_app(self, pos.row + 1, pos.col) end
    else
        apps.page_forward(self, "down")
    end
end

function apps.scroll_left(self)
    local grid = self._private.active_grid or self._private.grid
    if not grid or #grid.children < 1 then self._private.active_widget = nil return end
    local pos = grid:get_widget_position(self._private.active_widget)
    if not pos then pos = {row = 1, col = 1} end
    if pos.col > 1 then
        apps.unselect_app(self)
        apps.select_app(self, pos.row, pos.col - 1)
    else
        apps.page_backward(self, "left")
    end
end

function apps.scroll_right(self)
    local grid = self._private.active_grid or self._private.grid
    if not grid or #grid.children < 1 then self._private.active_widget = nil return end
    local rows, columns = grid:get_dimension()
    local pos = grid:get_widget_position(self._private.active_widget)
    if not pos then pos = {row = 1, col = 1} end
    if pos.col < columns then
        apps.unselect_app(self)
        if grid:get_widgets_at(pos.row, pos.col + 1) == nil then
            local app_widget = grid.children[#grid.children]
            pos = grid:get_widget_position(app_widget)
            apps.select_app(self, pos.row, pos.col)
        else
            apps.select_app(self, pos.row, pos.col + 1)
        end
    else
        apps.page_forward(self, "right")
    end
end

------------------------------------------------------------------
-- Reset + generation
------------------------------------------------------------------

function apps.reset(self)
    self._private.grid:reset()
    self._private.matched_entries = self._private.all_entries
    self._private.apps_per_page = self._private.max_apps_per_page
    self._private.pages_count = math.ceil(#self._private.all_entries / self._private.apps_per_page)
    self._private.current_page = 1
    for index, entry in ipairs(self._private.all_entries) do
        if index <= self._private.apps_per_page then
            self._private.grid:add(apps.create_app_widget(self, entry))
        else
            break
        end
    end
    apps.select_app(self, 1, 1)
end

function apps.generate_apps(self)
    self._private.all_entries = {}
    self._private.matched_entries = {}
    local gio_apps = Gio.AppInfo.get_all()

    table.sort(gio_apps, function(a, b)
        local name_a = a:get_name() or ""
        local name_b = b:get_name() or ""
        local a_fav = utils.has_value(self.favorites, name_a)
        local b_fav = utils.has_value(self.favorites, name_b)

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

    for _, app in ipairs(gio_apps) do
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

            if not utils.has_value(self.skip_names, name) and
               not utils.has_value(self.skip_commands, commandline) then
                if icon ~= "" or self.skip_empty_icons == false then
                    if icon == "" then
                        if self.default_app_icon_name ~= nil and icon_theme then
                            icon = icon_theme:get_icon_path(self.default_app_icon_name) or ""
                        elseif self.default_app_icon_path ~= nil then
                            icon = self.default_app_icon_path
                        elseif icon_theme then
                            icon = icon_theme:choose_icon(
                                {"application-all", "application", "application-default-icon", "app"}) or ""
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

return apps