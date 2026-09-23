-- control center music widget — album art + playback status only
-- no player controls

local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local dpi = beautiful.xresources.apply_dpi
local helpers = require("helpers")
local wibox = require("wibox")

-- album art — same method as layout/decorations/init.lua
----------------------------------
local ART_SIZE = dpi(270)

local album_placeholder = beautiful.images and beautiful.images.album_art

local function make_album_art(size)
    return wibox.widget({
        image = album_placeholder,
        resize = true,
        clip_shape = helpers.rrect(beautiful.rounded),
        forced_width = size,
        forced_height = size,
        widget = wibox.widget.imagebox,
    })
end

local album_art = make_album_art(ART_SIZE)

local function apply_surface(surface)
    album_art:set_image(surface or album_placeholder)
end

local function set_album_art(path)
    if path == nil or path == "" then
        apply_surface(album_placeholder)
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
local MUSIC_DIR = os.getenv("HOME") .. "/Music/artists/"

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

-- playback status — Spanish text, no glyphs
-------------------------------------------
local status_txt = wibox.widget{
    widget = wibox.widget.textbox,
    markup = helpers.colorize_text("已暂停", beautiful.fg_color .. "99"),
    font = beautiful.font_var .. "9",
    align = "left",
    valign = "center"
}

local function set_status(playing)
    if playing then
        status_txt.markup = helpers.colorize_text("正在播放", beautiful.accent)
    else
        status_txt.markup = helpers.colorize_text("已暂停", beautiful.fg_color .. "99")
    end
end

set_status(false)

-- darkening frost mask — same as before
local album_mask = wibox.widget{
    {
        bg = beautiful.bg_frost_2,
        forced_height = ART_SIZE,
        forced_width = ART_SIZE,
        shape = helpers.rrect(beautiful.rounded),
        widget = wibox.container.background
    },
    direction = "east",
    widget = wibox.container.rotate
}

local album_art_framed = wibox.widget{
    album_art,
    album_mask,
    layout = wibox.layout.stack
}

-- playerctl
-----------
local playerctl = require("mods.bling").signal.playerctl.lib()

playerctl:connect_signal("metadata", function(_, __, ___, album_path, __, ___, ____)
    if album_path == "" then
        cover_from_mpd()
    else
        set_album_art(album_path)
    end
end)

playerctl:connect_signal("playback_status", function(_, playing, __)
    set_status(playing and true or false)
end)


-- assemble (single card) — same container positioning as before
----------------------------------------------------------------
local inner = wibox.widget{
    {
        album_art_framed,
        widget = wibox.container.place,
        halign = "center"
    },
    {
        status_txt,
        layout = wibox.layout.fixed.vertical,
        spacing = dpi(3)
    },
    layout = wibox.layout.fixed.vertical,
    spacing = dpi(16)
}

return wibox.widget({
    {
        inner,
        widget = wibox.container.margin,
        margins = dpi(20)
    },
    widget = wibox.container.background,
    bg = beautiful.bg_frost_2,
    shape = helpers.rrect(beautiful.rounded),
    shape_border_width = dpi(1),
    shape_border_color = beautiful.fg_color .. "14",
})
