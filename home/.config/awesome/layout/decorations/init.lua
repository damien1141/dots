-- ncmpcpp / mpd awesome titlebar — v2
-- top: volume + music icon | left: album art | bottom: seek, meta, transport, pos, views

local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local ruled = require("ruled")
local wibox = require("wibox")
local xresources = require("beautiful.xresources")
local dpi = xresources.apply_dpi

-- knobs ----------------------------------------------------------------
local SHOW_TOPBAR = true
local TOPBAR_SIZE = dpi(40)
local SIDEBAR_WIDTH = dpi(200)
local SIDEBAR_TINT_ALPHA = "26" -- accent alpha over music_bg. "00" = plain bg, "ff" = old slab
local MUSIC_DIR = os.getenv("HOME") .. "/Música/artists/"
-------------------------------------------------------------------------

local ok_helpers, helpers = pcall(require, "helpers")
if not ok_helpers then helpers = {} end

local playerctl_daemon
do
    local ok, mod = pcall(require, "signal.playerctl")
    if ok and mod and mod.connect_signal then
        playerctl_daemon = mod
    else
        local ok_bling, bling = pcall(require, "mods.bling")
        if ok_bling and bling and bling.signal and bling.signal.playerctl then
            playerctl_daemon = bling.signal.playerctl.lib()
        end
    end
end

if not playerctl_daemon then
    playerctl_daemon = { connect_signal = function() end }
end

-- theme fallbacks
local function str(v, fallback)
    return (type(v) == "string" and v or fallback)
end

local accent = str(beautiful.accent, "#89b4fa")
local fg = str(beautiful.fg_color or beautiful.fg_normal, "#dddddd")
local white = str(beautiful.white, "#f8f8f2")
local muted = str(beautiful.ext_light_fg or beautiful.color8, fg .. "99")

local music_bg = str(beautiful.music_bg, beautiful.bg_2 or beautiful.bg_normal or "#111112")
local music_bg_accent = str(beautiful.music_bg_accent, beautiful.ext_light_bg_2 or beautiful.bg_1 or "#1b1b1f")
local transparent = str(beautiful.transparent, "#00000000")

local radius = beautiful.border_radius or beautiful.rounded or dpi(10)
local album_placeholder = beautiful.music or (beautiful.images and beautiful.images.album_art)

local function font_sp(f)
    f = tostring(f or "")
    if f == "" then return "" end
    if f:sub(-1) ~= " " then return f .. " " end
    return f
end

local icon_font = font_sp(beautiful.icon_font or beautiful.icon_var or "Material Icons")
local icon_round_font = font_sp(beautiful.icon_font_round or icon_font)
local font_name = font_sp(beautiful.font_name or beautiful.font_var or "Sans")

-- markup / shape helpers
local function escape_markup(text)
    return tostring(text or "")
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
end

local function colorize(text, color)
    return "<span foreground='" .. tostring(color or fg) .. "'>" .. escape_markup(text) .. "</span>"
end

local function rrect(r)
    return function(cr, w, h)
        gears.shape.rounded_rect(cr, w, h, r)
    end
end

local function prrect(r, tl, tr, br, bl)
    return function(cr, w, h)
        gears.shape.partially_rounded_rect(cr, w, h, tl, tr, br, bl, r)
    end
end

local function horizontal_pad(width)
    return wibox.widget({
        left = width,
        right = width,
        widget = wibox.container.margin,
    })
end

local function send_key(c, key)
    if helpers.misc and helpers.misc.send_key then
        return helpers.misc.send_key(c, key)
    end

    if c and c.window then
        awful.spawn.with_shell("xdotool key --window " .. tostring(c.window) .. " " .. tostring(key))
    end
end

local function fmt_time(sec)
    sec = math.floor(tonumber(sec) or 0)
    return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

-- widgets
local title_now = wibox.widget({
    font = font_name .. "Bold 12",
    valign = "center",
    widget = wibox.widget.textbox,
})

local artist_now = wibox.widget({
    font = font_name .. "Medium 10",
    valign = "center",
    widget = wibox.widget.textbox,
})

local music_pos = wibox.widget({
    font = font_name .. "Medium 10",
    valign = "center",
    widget = wibox.widget.textbox,
})

local music_bar = wibox.widget({
    max_value = 100,
    value = 0,
    background_color = accent .. "44",
    color = accent,
    forced_height = dpi(4),
    widget = wibox.widget.progressbar,
})

music_bar:connect_signal("button::press", function(_, lx, _, button, _, w)
    if button ~= 1 then return end

    local geo = (type(w) == "table" and w) or mouse.current_widget_geometry
    local width = geo and geo.width or 0

    if width > 0 then
        awful.spawn.with_shell("mpc seek " .. math.ceil(lx * 100 / width) .. "%")
    end
end)

title_now:set_markup_silently(colorize("未在播放", accent))
artist_now:set_markup_silently(colorize("未在播放", white))
music_pos:set_markup_silently(colorize("00:00", white) .. colorize(" / 00:00", muted))

-- album art
local art_size = SIDEBAR_WIDTH - dpi(50)

local function make_album_art(size)
    return wibox.widget({
        image = album_placeholder,
        resize = true,
        clip_shape = rrect(radius),
        forced_width = size,
        forced_height = size,
        widget = wibox.widget.imagebox,
    })
end

local album_art_sidebar = make_album_art(art_size)
local album_art_toolbar = make_album_art(dpi(40))

local function apply_surface(surface)
    album_art_sidebar:set_image(surface)
    album_art_toolbar:set_image(surface)
end

local function set_album_art(path)
    if path == nil or path == "" then
        path = album_placeholder
    end

    if path == nil then
        apply_surface(nil)
        return
    end

    if type(path) ~= "string" then
        apply_surface(path)
        return
    end

    local ok, surface = pcall(gears.surface.load_uncached, path)
    if ok and surface then
        apply_surface(surface)
    else
        apply_surface(album_placeholder)
    end
end

-- cover lookup: mpd file path -> cover/folder/front/art in the track dir
local function cover_from_mpd()
    awful.spawn.easy_async_with_shell("mpc -f %file% current", function(out)
        local file = (out or ""):match("^[^\n]*")
        if not file or file == "" then return end

        local dir = file:match("^(.*/)") or ""
        local base = (MUSIC_DIR .. "/" .. dir):gsub('"', '\\"')

        local cmd = string.format(
            [[sh -c 'b="$1"; for f in cover.jpg cover.png cover.jpeg folder.jpg folder.png front.jpg art.png; do [ -f "$b/$f" ] && printf "%%s" "$b/$f" && exit 0; done; find "$b" -maxdepth 1 -type f \( -iname "cover.*" -o -iname "folder.*" -o -iname "front.*" -o -iname "art.*" \) -print -quit' _ "%s"]],
            base
        )

        awful.spawn.easy_async_with_shell(cmd, function(found)
            found = (found or ""):gsub("%s+$", "")
            if found ~= "" then
                set_album_art(found)
            end
        end)
    end)
end

-- button factory
local function icon_button(args)
    args = args or {}

    local text = args.text or ""
    local font = args.font or icon_round_font
    local size = args.size or 12

    local text_color = args.text_color or white
    local active_text_color = args.active_text_color or music_bg

    local bg_normal = args.bg or music_bg_accent
    local bg_active = args.active_bg or accent
    local bg_hover = args.hover_bg or bg_active
    local bg_press = args.press_bg or bg_active

    local shape = args.shape or rrect(dpi(8))
    local active = false

    local icon = wibox.widget({
        widget = wibox.widget.textbox,
        align = "center",
        valign = "center",
        font = font .. tostring(size),
        markup = colorize(text, text_color),
    })

    local bg = wibox.widget({
        {
            {
                icon,
                margins = dpi(args.padding or 5),
                widget = wibox.container.margin,
            },
            margins = dpi(1),
            widget = wibox.container.margin,
        },
        widget = wibox.container.background,
        bg = bg_normal,
        shape = shape,
    })

    local widget = wibox.widget({
        bg,
        widget = wibox.container.background,
        bg = transparent,
    })

    local function redraw()
        bg.bg = active and bg_active or bg_normal
        icon.markup = colorize(text, active and active_text_color or text_color)
    end

    function widget:set_text(new_text, new_color)
        text = new_text or text
        if new_color then text_color = new_color end
        redraw()
    end

    function widget:set_active(state)
        active = state and true or false
        redraw()
    end

    widget:buttons(gears.table.join(
        awful.button({}, 1, function()
            if args.on_release then args.on_release() end
        end)
    ))

    widget:connect_signal("mouse::enter", function()
        if not active then bg.bg = bg_hover end
    end)

    widget:connect_signal("mouse::leave", function()
        bg.bg = active and bg_active or bg_normal
    end)

    widget:connect_signal("button::press", function()
        bg.bg = bg_press
    end)

    widget:connect_signal("button::release", function()
        bg.bg = active and bg_active or bg_hover
    end)

    redraw()
    return widget
end

-- mpc state / transport
local mpc

local shuffle_button = icon_button({
    text = "",
    size = 12,
    on_release = function()
        if mpc then mpc("random") end
    end,
})

local loop_button = icon_button({
    text = "",
    size = 12,
    on_release = function()
        if mpc then mpc("repeat") end
    end,
})

local prev_button = icon_button({
    text = "",
    size = 12,
    on_release = function()
        if mpc then mpc("prev") end
    end,
})

local next_button = icon_button({
    text = "",
    size = 12,
    on_release = function()
        if mpc then mpc("next") end
    end,
})

local play_button = icon_button({
    text = "",
    size = 14,
    font = icon_font,
    text_color = music_bg,
    active_text_color = music_bg,
    bg = accent,
    active_bg = accent,
    hover_bg = accent,
    press_bg = accent,
    padding = 6,
    on_release = function()
        if mpc then mpc("toggle") end
    end,
})

local function parse_mpc_status(stdout)
    stdout = tostring(stdout or "")

    local shuffle_on = stdout:match("random:%s*on") ~= nil
    local loop_on = stdout:match("repeat:%s*on") ~= nil

    shuffle_button:set_active(shuffle_on)
    shuffle_button:set_text(shuffle_on and "" or "")

    loop_button:set_active(loop_on)
    loop_button:set_text(loop_on and "" or "")

    play_button:set_text(stdout:match("%[playing%]") and "" or "")
end

mpc = function(cmd)
    awful.spawn.easy_async_with_shell(
        "mpc " .. cmd .. " >/dev/null 2>&1; mpc status",
        function(stdout)
            parse_mpc_status(stdout)
        end
    )
end

local function update_mpc_status()
    awful.spawn.easy_async_with_shell("mpc status", function(stdout)
        parse_mpc_status(stdout)
    end)
end

update_mpc_status()

-- volume
local function volume_control()
    local volume_bar = wibox.widget({
        max_value = 100,
        value = 50,
        margins = {
            top = dpi(12),
            bottom = dpi(12),
            left = dpi(5),
            right = dpi(5),
        },
        forced_width = dpi(80),
        shape = gears.shape.rounded_bar,
        bar_shape = gears.shape.rounded_bar,
        color = accent,
        background_color = white .. "11",
        border_width = 0,
        widget = wibox.widget.progressbar,
    })

    local function volume_info()
        awful.spawn.easy_async_with_shell(
            "mpc volume | awk '{print substr($2, 1, length($2)-1)}'",
            function(stdout)
                local volume = tonumber(stdout)
                volume_bar.value = math.max(0, math.min(100, volume or 0))
            end
        )
    end

    volume_info()

    local mpd_volume_script = [[
        sh -c "mpc idleloop mixer | sed -u '1~2d'"
    ]]

    awful.spawn.easy_async_with_shell(
        "ps x | grep 'mpc idleloop mixer' | grep -v grep | awk '{print $1}' | xargs -r kill",
        function()
            awful.spawn.with_line_callback(mpd_volume_script, {
                stdout = function()
                    volume_info()
                end,
            })
        end
    )

    volume_bar:connect_signal("button::press", function(_, lx, _, button)
        if button == 1 then
            local width = volume_bar.forced_width or dpi(80)
            local level = math.max(0, math.min(100, math.ceil(lx * 100 / width)))
            awful.spawn.easy_async_with_shell("mpc volume " .. level, function()
                volume_info()
            end)
        end
    end)

    local volume = wibox.widget({
        {
            align = "left",
            font = icon_round_font .. "16",
            markup = colorize("", accent),
            widget = wibox.widget.textbox,
        },
        horizontal_pad(dpi(3)),
        volume_bar,
        horizontal_pad(dpi(2)),
        layout = wibox.layout.fixed.horizontal,
    })

    volume:buttons(gears.table.join(
        awful.button({}, 4, function()
            awful.spawn.easy_async_with_shell("mpc volume +5", function()
                volume_info()
            end)
        end),
        awful.button({}, 5, function()
            awful.spawn.easy_async_with_shell("mpc volume -5", function()
                volume_info()
            end)
        end)
    ))

    return volume
end

-- top music icon
local function music_icon()
    local big_music_icon = wibox.widget({
        align = "center",
        font = icon_round_font .. "15",
        markup = colorize("", accent),
        widget = wibox.widget.textbox,
    })

    local small_music_icon = wibox.widget({
        align = "center",
        font = icon_round_font .. "11",
        markup = colorize("", white),
        widget = wibox.widget.textbox,
    })

    local container_music_icon = wibox.widget({
        big_music_icon,
        {
            small_music_icon,
            top = dpi(11),
            widget = wibox.container.margin,
        },
        spacing = dpi(-9),
        layout = wibox.layout.fixed.horizontal,
    })

    return wibox.widget({
        nil,
        {
            container_music_icon,
            spacing = dpi(14),
            layout = wibox.layout.fixed.horizontal,
        },
        expand = "none",
        layout = wibox.layout.align.horizontal,
    })
end

-- ncmpcpp view buttons
local function playlist(c)
    return icon_button({
        text = "",
        size = 14,
        on_release = function()
            send_key(c, "1")
        end,
    })
end

local function visualizer(c)
    return icon_button({
        text = "",
        size = 14,
        on_release = function()
            send_key(c, "8")
        end,
    })
end

-- playerctl signals
local function is_mpd(player_name)
    if player_name == nil then return true end

    local p = tostring(player_name):lower()
    return p == "mpd" or p:find("mpd", 1, true) ~= nil
end

local last_meta_key = nil

playerctl_daemon:connect_signal("metadata", function(_, title, artist, album_path, _, _, player_name)
    if not is_mpd(player_name) then return end

    title = title or ""
    artist = artist or ""

    if title == "" then title = "未在播放" end
    if artist == "" then artist = "未在播放" end

    title_now:set_markup_silently(colorize(string.upper(title), accent))
    artist_now:set_markup_silently(colorize(artist, white))

    local key = title .. "::" .. artist
    if key == last_meta_key then return end
    last_meta_key = key

    if album_path and album_path ~= "" then
        set_album_art(album_path)
    else
        cover_from_mpd()
    end
end)

playerctl_daemon:connect_signal("position", function(_, interval_sec, length_sec, player_name)
    if not is_mpd(player_name) then return end

    interval_sec = tonumber(interval_sec) or 0
    length_sec = tonumber(length_sec) or 0

    music_pos:set_markup_silently(
        colorize(fmt_time(interval_sec), white) ..
        colorize(" / " .. fmt_time(length_sec), muted)
    )

    if length_sec > 0 then
        music_bar.value = math.max(0, math.min(100, (interval_sec / length_sec) * 100))
    else
        music_bar.value = 0
    end
end)

playerctl_daemon:connect_signal("playback_status", function(_, playing, player_name)
    if not is_mpd(player_name) then return end
    play_button:set_text(playing and "" or "")
end)

playerctl_daemon:connect_signal("shuffle", function(_, state, player_name)
    if not is_mpd(player_name) then return end
    shuffle_button:set_active(state)
    shuffle_button:set_text(state and "" or "")
end)

playerctl_daemon:connect_signal("loop", function(_, state, player_name)
    if not is_mpd(player_name) then return end
    loop_button:set_active(state)
    loop_button:set_text(state and "" or "")
end)

-- decoration
local music_create_decoration = function(c)
    awful.titlebar.hide(c, beautiful.titlebar_pos or "top")

    if SHOW_TOPBAR then
        awful.titlebar(c, { position = "top", size = TOPBAR_SIZE, bg = transparent }):setup({
            {
                {
                    {
                        volume_control(),
                        forced_width = dpi(160),
                        widget = wibox.container.constraint,
                    },
                    music_icon(),
                    layout = wibox.layout.align.horizontal,
                },
                left = dpi(10),
                right = dpi(10),
                widget = wibox.container.margin,
            },
            bg = music_bg,
            shape = prrect(radius, true, true, false, false),
            widget = wibox.container.background,
        })
    end

    awful.titlebar(c, { position = "left", size = SIDEBAR_WIDTH, bg = transparent }):setup({
        {
            nil,
            {
                album_art_sidebar,
                bottom = dpi(20),
                left = dpi(25),
                right = dpi(25),
                widget = wibox.container.margin,
            },
            nil,
            expand = "none",
            layout = wibox.layout.align.vertical,
        },
        bg = accent .. SIDEBAR_TINT_ALPHA,
        shape = prrect(radius * 2, false, true, false, false),
        widget = wibox.container.background,
    })

    awful.titlebar(c, { position = "bottom", size = dpi(70), bg = transparent }):setup({
        {
            music_bar,
            {
                {
                    layout = wibox.layout.align.horizontal,
                    expand = "none",
                    {
                        album_art_toolbar,
                        {
                            {
                                step_function = wibox.container.scroll.step_functions.waiting_nonlinear_back_and_forth,
                                fps = 60,
                                speed = 75,
                                title_now,
                                forced_width = dpi(150),
                                widget = wibox.container.scroll.horizontal,
                            },
                            {
                                step_function = wibox.container.scroll.step_functions.waiting_nonlinear_back_and_forth,
                                fps = 60,
                                speed = 75,
                                artist_now,
                                forced_width = dpi(150),
                                widget = wibox.container.scroll.horizontal,
                            },
                            spacing = dpi(2),
                            layout = wibox.layout.flex.vertical,
                        },
                        spacing = dpi(10),
                        layout = wibox.layout.fixed.horizontal,
                    },
                    {
                        shuffle_button,
                        prev_button,
                        play_button,
                        next_button,
                        loop_button,
                        spacing = dpi(10),
                        layout = wibox.layout.fixed.horizontal,
                    },
                    {
                        music_pos,
                        {
                            playlist(c),
                            visualizer(c),
                            spacing = dpi(5),
                            layout = wibox.layout.fixed.horizontal,
                        },
                        spacing = dpi(10),
                        layout = wibox.layout.fixed.horizontal,
                    },
                },
                top = dpi(15),
                bottom = dpi(15),
                left = dpi(25),
                right = dpi(25),
                widget = wibox.container.margin,
            },
            layout = wibox.layout.align.vertical,
        },
        bg = music_bg_accent,
        shape = prrect(radius, false, false, true, true),
        widget = wibox.container.background,
    })

    c.custom_decoration = { top = SHOW_TOPBAR, left = true, bottom = true }
end

ruled.client.connect_signal("request::rules", function()
    ruled.client.append_rule({
        id = "music",
        rule = { instance = "music" },
        callback = music_create_decoration,
    })
end)
