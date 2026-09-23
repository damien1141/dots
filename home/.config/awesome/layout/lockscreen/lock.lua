-- Lockscreen
-- ~~~~~~~~~~~~~~~~~~~~
-- Redesigned for transparency (Picom blur compatibility) and stability
local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local helpers = require("helpers") -- Ensure this exists in your config
local dpi = beautiful.xresources.apply_dpi
local fprint = require("layout.lockscreen.fprint")

-- Set Spanish locale for time formatting
os.setlocale("es_ES.UTF-8")

-- misc/vars
local lock_screen_symbol = ""
local lock_screen_fail_symbol = ""
local fingerprint_icon = ""

-- Widgets
local profile_image = wibox.widget {
    {
        image = beautiful.images and beautiful.images.profile or beautiful.theme_assets.default_icon,
        upscale = true,
        downscale = true,
        forced_width = dpi(140),
        forced_height = dpi(140),
        clip_shape = gears.shape.square,
        widget = wibox.widget.imagebox,
    },
    widget = wibox.container.background,
    -- No border properties = clean square look
}

local username = wibox.widget {
    widget = wibox.widget.textbox,
    markup = user_likes and user_likes.username or "User",
    font = beautiful.font_var and (beautiful.font_var .. " 18") or "Sans 18",
    align = "center",
    valign = "center"
}

local profile_section = wibox.widget {
    {
        profile_image,
        username,
        spacing = dpi(20),
        layout = wibox.layout.fixed.vertical,
    },
    widget = wibox.container.place,
    halign = "center",
    valign = "center"
}

-- Clock (Cleaned up layout)
local clock_widget = wibox.widget {
    {
        font = beautiful.font_var and (beautiful.font_var .. " Bold 64") or "Sans Bold 64",
        format = "%H:%M",
        widget = wibox.widget.textclock,
        align = "center",
        valign = "center"
    },
    {
        font = beautiful.font_var and (beautiful.font_var .. " 16") or "Sans 16",
        format = "%A, %d de %B",
        widget = wibox.widget.textclock,
        align = "center",
        valign = "center"
    },
    layout = wibox.layout.fixed.vertical,
    spacing = dpi(0)
}

-- Password prompt
local promptbox = wibox.widget {
    widget = wibox.widget.textbox,
    markup = "",
    font = beautiful.icon_var and (beautiful.icon_var .. " 16") or "Sans 16",
    align = "center",
    valign = "center"
}

local promptbox_container = wibox.widget {
    {
        promptbox,
        margins = { left = dpi(20), right = dpi(20) },
        widget = wibox.container.margin
    },
    widget = wibox.container.background,
    bg = "#FFFFFF11", -- Subtle glass input field
    forced_width = dpi(300),
    forced_height = dpi(45),
    shape = function(cr, w, h) gears.shape.rounded_rect(cr, w, h, 8) end,
    border_width = dpi(1),
    border_color = "#FFFFFF22"
}

-- Fingerprint status text
local fingerprint_text = wibox.widget {
    widget = wibox.widget.textbox,
    markup = "触摸指纹传感器",
    font = beautiful.font_var and (beautiful.font_var .. " 12") or "Sans 12",
    align = "center",
    valign = "center"
}

-- Dummy textbox for awful.prompt
local some_textbox = wibox.widget.textbox()

-- Create the main lock screen wibox (FULLY TRANSPARENT for Picom blur)
local lock_screen_box = wibox({
    visible = false,
    ontop = true,
    type = "splash",
    bg = "#00000000", -- Fully transparent! Picom will blur what's behind this.
    fg = beautiful.fg_color or "#FFFFFF",
    screen = screen.primary
})

-- Create the lock screen wibox (extra for multi-monitor)
local function create_extender(s)
    local lock_screen_box_ext = wibox({
        visible = false,
        ontop = true,
        type = "splash",
        bg = "#00000000", -- Fully transparent
        fg = beautiful.fg_color or "#FFFFFF",
        screen = s
    })
    awful.placement.maximize(lock_screen_box_ext)
    return lock_screen_box_ext
end

awful.placement.maximize(lock_screen_box)

-- Add lockscreen to each screen
awful.screen.connect_for_each_screen(function(s)
    if s.index == 2 then
        s.mylockscreenext = create_extender(s)
        s.mylockscreen = lock_screen_box
    else
        s.mylockscreen = lock_screen_box
    end
end)

local function set_visibility(v)
    for s in screen do
        if s.mylockscreen then s.mylockscreen.visible = v end
        if s.mylockscreenext then s.mylockscreenext.visible = v end
    end
end

-- Lock helper functions
local characters_entered = 0
local function reset()
    characters_entered = 0
    promptbox.markup = ""
    fingerprint_text.markup = "触摸指纹传感器"
end

local function fail()
    characters_entered = 0
    promptbox.markup = helpers.colorize_text("错误", beautiful.red_3 or "#FF5555")
    fingerprint_text.markup = helpers.colorize_text("指纹未识别", beautiful.red_3 or "#FF5555")
    -- Reset after 1.5 seconds
    gears.timer {
        timeout = 1.5,
        autostart = true,
        single_shot = true,
        callback = reset
    }
end

-- user input
local function grab_password()
    awful.prompt.run {
        hooks = {
            {{}, 'Escape', function(_) reset() grab_password() end},
            {{'Control'}, 'Delete', function() reset() grab_password() end}
        },
        keypressed_callback = function(mod, key, cmd)
            if #key == 1 then
                characters_entered = characters_entered + 1
                promptbox.markup = string.rep("•", characters_entered)
            elseif key == "BackSpace" then
                if characters_entered > 0 then
                    characters_entered = characters_entered - 1
                end
                promptbox.markup = string.rep("•", characters_entered)
            end
        end,
        exe_callback = function(input)
            -- Use the init.lua authenticate function
            if require("layout.lockscreen").authenticate(input) then
                fprint.stop_listener()
                reset()
                set_visibility(false)
            else
                fail()
                grab_password()
            end
        end,
        textbox = some_textbox,
    }
end

-- Fingerprint listener wrapper
local function start_fingerprint_listener()
    fingerprint_text.markup = "正在扫描指纹..."
    fprint.start_listener(
        function()
            -- Success callback
            reset()
            set_visibility(false)
        end,
        function()
            -- Fail/Timeout callback (optional visual feedback)
        end
    )
end

-- show lockscreen func
function lock_screen_show()
    set_visibility(true)
    reset()
    grab_password()
    start_fingerprint_listener()
end

-- Hide lockscreen func (useful for external unlock triggers)
function lock_screen_hide()
    fprint.stop_listener()
    set_visibility(false)
end

-- Glassmorphism Card Container (Sits on top of Picom's blur)
local glass_card = {
    {
        {
            clock_widget,
            {
                profile_section,
                {
                    promptbox_container,
                    {
                        fingerprint_text,
                        margins = { top = dpi(10) },
                        widget = wibox.container.margin
                    },
                    layout = wibox.layout.fixed.vertical,
                    spacing = dpi(15)
                },
                layout = wibox.layout.fixed.vertical,
                spacing = dpi(30)
            },
            layout = wibox.layout.fixed.vertical,
            spacing = dpi(40)
        },
        widget = wibox.container.margin,
        margins = dpi(40) -- Padding inside the glass card
    },
    widget = wibox.container.background,
    bg = "#1A1A244D", -- Semi-transparent dark grey/blue for frosted glass effect
    shape = function(cr, w, h) gears.shape.rounded_rect(cr, w, h, 24) end,
    border_width = dpi(1),
    border_color = "#FFFFFF1A" -- Subtle glass edge reflection
}

-- Extract UI Setup into a shared table to fix multi-monitor cloning bugs
local main_layout = {
    glass_card,
    widget = wibox.container.place,
    halign = "center",
    valign = "center"
}

-- init UI setup
lock_screen_box:setup(main_layout)

-- Apply same setup to extender if it exists
awful.screen.connect_for_each_screen(function(s)
    if s.mylockscreenext and s.mylockscreenext.setup then
        s.mylockscreenext:setup(main_layout)
    end
end)