-- ghost number: centered desktop overlay "45,000"
-- ------------------------------------------------

local wibox = require("wibox")
local xresources = require("beautiful.xresources")
local dpi = xresources.apply_dpi


-- config
----------
local FONT = "JetBrains Mono 96"
local TEXT = "45,000"
local OPACITY_ALPHA = "2A" -- ~10% opacity (26/255)
local W, H = dpi(512), dpi(256)
local LOG = "/tmp/ghost.log"


-- widget
----------
local text = wibox.widget{
    markup = "<span color=\"#ffffff" .. OPACITY_ALPHA .. "\">" .. TEXT .. "</span>",
    font   = FONT,
    align  = "center",
    valign = "center",
    widget = wibox.widget.textbox,
}

local widget = wibox.widget{
    {
        nil,
        {
            nil,
            text,
            nil,
            layout = wibox.layout.align.vertical,
        },
        nil,
        layout = wibox.layout.align.horizontal,
    },
    widget  = wibox.container.margin,
    margins = { left = dpi(12), right = dpi(12), top = dpi(6), bottom = dpi(6) },
}


-- build
---------
local function usable(wb)
    if not wb then return false end
    local ok = pcall(function() return wb.x, wb.width end)
    return ok
end

local function build()
    local s = screen.primary
    local args = {
        type   = "splash",
        bg     = "#00000000",
        input  = false,
        widget = widget,
    }

    -- your awesome build lacks at least one constructor form; try all,
    -- first usable object wins, name gets logged.
    local ctors = {
        { "wibox.new",    function(a) return wibox.new(a) end },
        { "wibox.__call", function(a) return wibox(a)     end },
    }
    local wb, ctor
    for _, c in ipairs(ctors) do
        local ok, r = pcall(c[2], args)
        if ok and usable(r) then wb, ctor = r, c[1] break end
    end
    if not wb then error("no working wibox constructor in this build") end

    local function center()
        local g = s.geometry
        wb.screen = s
        wb.width  = W
        wb.height = H
        wb.x = g.x + (g.width  - W) / 2
        wb.y = g.y + (g.height - H) / 2
        wb.visible = true   -- setter, post-construction: the only reliable path
    end
    center()

    screen.connect_signal("property::geometry", function(scr)
        if scr == s then center() end
    end)

    wb.class = "ghost_number"
    wb.name  = "ghost_number"
    return wb, ctor
end

local ok, result, ctor = pcall(build)

local f = io.open(LOG, "w")
if f then
    if ok then
        local g = result:geometry()
        f:write(string.format("OK ctor=%s geo=%d,%d %dx%d visible=%s screen=%s\n",
            tostring(ctor), g.x, g.y, g.width, g.height,
            tostring(result.visible), tostring(result.screen)))
    else
        f:write("FAIL " .. tostring(result) .. "\n")
    end
    f:close()
end

if not ok then return nil end

ghost_number = result -- GC anchor + awesome-client handle; do not delete
return result
