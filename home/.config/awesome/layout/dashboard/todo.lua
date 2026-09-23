local awful = require("awful")
local wibox = require("wibox")
local beautiful = require("beautiful")
local bling = require("mods.bling")
local gears = require("gears")
local dpi = beautiful.xresources.apply_dpi
local helpers = require("helpers")

local notes_file = os.getenv("HOME") .. "/.config/awesome/todo"

-- Create notes file if it doesn't exist
local f = io.open(notes_file, "r")
if not f then
    local fw = io.open(notes_file, "w")
    fw:write("# 🧠 Brain Dump\n\n")
    fw:write("## 🚀 Hyperfocus Tasks\n")
    fw:write("- [ ] Fix AwesomeWM rice\n")
    fw:write("- [x] Add gamma slider for 4am Anime\n")
    fw:write("- [ ] Touch grass\n\n")
    fw:write("## 📝 Quick Notes\n")
    fw:write("Remember: Sleep is for nerds.\n")
    fw:close()
else
    f:close()
end

-- ============== BLING SCRATCHPAD ==============
local notes_scratch = bling.module.scratchpad {
    command = "kitty --class notes -e $EDITOR ~/.config/awesome/todo",
    rule = { instance = "notes" },
    sticky = true,
    autoclose = false,
    floating = true,
    geometry = {x=360, y=90, height=900, width=1200},
    reapply = true,
    dont_focus_before_close = false,
}

local main_widget = wibox.widget {
    layout = wibox.layout.fixed.vertical,
    spacing = dpi(20), -- More breathing room between sections
}

-- Standardized margin to match notifs (dpi(15))
local side_margin = dpi(2)

-- ============== QUICK NOTES ==============
local notes_content_widget = wibox.widget {
    markup = "",
    widget = wibox.widget.textbox,
}

local notes_scroll = wibox.widget {
    notes_content_widget,
    widget = wibox.container.scroll.vertical,
    step_size = 15,
}

local function update_notes()
    local f = io.open(notes_file, "r")
    if f then
        local content = f:read("*all")
        f:close()
        content = content:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
        
        notes_content_widget.markup = string.format(
            "<span size='small' font='monospace' foreground='%s'>%s</span>",
            beautiful.fg_color or "#cdd6f4", content
        )
    end
end

-- Edit button with consistent margins
local edit_notes_btn = wibox.widget {
    {
        markup = string.format("<span foreground='%s'>编辑</span>", beautiful.accent or "#89b4fa"),
        font = "Sans 9",
        widget = wibox.widget.textbox,
    },
    widget = wibox.container.margin,
    margins = { left = dpi(10), right = side_margin },
}

edit_notes_btn:buttons(gears.table.join(
    awful.button({}, 1, function()
        if notes_scratch then
            notes_scratch:toggle()
        else
            awful.spawn.with_shell((os.getenv("TERMINAL") or "kitty") .. " -e $EDITOR " .. notes_file)
        end
    end)
))

-- Header aligned with content
local notes_header = wibox.widget {
    {
        markup = string.format("<span weight='bold' foreground='%s'>快速笔记</span>", beautiful.accent or "#89b4fa"),
        widget = wibox.widget.textbox,
    },
    wibox.widget.textbox(""), -- Spacer
    edit_notes_btn,
    layout = wibox.layout.align.horizontal,
}

local notes_widget = wibox.widget {
    {
        notes_header,
        margins = { left = side_margin, right = side_margin, bottom = dpi(8) },
        widget = wibox.container.margin,
    },
    {
        {
            notes_scroll,
            bg = beautiful.bg_frost_3,
            shape = helpers.rrect(6),
            widget = wibox.container.background,
        },
        margins = { left = side_margin, right = side_margin, bottom = dpi(10) },
        widget = wibox.container.margin,
    },
    layout = wibox.layout.fixed.vertical,
}

-- ============== NETWORK I/O SPARKLINE ==============
local spark_chars = {"▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}
local rx_history = {}
local tx_history = {}
local max_hist = 25
local prev_rx = 0
local prev_tx = 0

local function get_sparkline(history, max_val)
    local s = ""
    for _, v in ipairs(history) do
        local idx = 1
        if max_val > 0 then
            idx = math.max(1, math.min(8, math.ceil((v / max_val) * 7) + 1))
        end
        s = s .. spark_chars[idx]
    end
    return s
end

local rx_spark = wibox.widget { markup = "", widget = wibox.widget.textbox }
local tx_spark = wibox.widget { markup = "", widget = wibox.widget.textbox }

local rx_speed_txt = wibox.widget {
    markup = "<span font='monospace' size='x-small'>0 B/s</span>",
    widget = wibox.widget.textbox,
    forced_width = dpi(75),
    align = "right",
}
local tx_speed_txt = wibox.widget {
    markup = "<span font='monospace' size='x-small'>0 B/s</span>",
    widget = wibox.widget.textbox,
    forced_width = dpi(75),
    align = "right",
}

local function format_speed(bytes)
    if bytes < 1024 then return string.format("%d B/s", bytes) end
    if bytes < 1048576 then return string.format("%.1f KB/s", bytes / 1024) end
    return string.format("%.1f MB/s", bytes / 1048576)
end

local function update_network()
    awful.spawn.easy_async_with_shell("cat /proc/net/dev | awk 'NR>2 {rx+=$2; tx+=$10} END {print rx, tx}'", function(stdout)
        local rx, tx = stdout:match("(%d+)%s+(%d+)")
        rx, tx = tonumber(rx) or 0, tonumber(tx) or 0

        local rx_diff = rx - prev_rx
        local tx_diff = tx - prev_tx
        if prev_rx == 0 then rx_diff = 0 end
        if prev_tx == 0 then tx_diff = 0 end

        prev_rx, prev_tx = rx, tx

        table.insert(rx_history, rx_diff)
        table.insert(tx_history, tx_diff)
        if #rx_history > max_hist then table.remove(rx_history, 1) end
        if #tx_history > max_hist then table.remove(tx_history, 1) end

        local max_rx = 1
        for _, v in ipairs(rx_history) do if v > max_rx then max_rx = v end end
        local max_tx = 1
        for _, v in ipairs(tx_history) do if v > max_tx then max_tx = v end end

        rx_spark:set_markup(string.format("<span font='monospace' size='small' foreground='%s'>%s</span>", beautiful.green_color or "#a6e3a1", get_sparkline(rx_history, max_rx)))
        tx_spark:set_markup(string.format("<span font='monospace' size='small' foreground='%s'>%s</span>", beautiful.blue_color or "#89b4fa", get_sparkline(tx_history, max_tx)))

        rx_speed_txt:set_markup(string.format("<span font='monospace' size='x-small' foreground='%s'>%s</span>", beautiful.fg_color or "#cdd6f4", format_speed(rx_diff)))
        tx_speed_txt:set_markup(string.format("<span font='monospace' size='x-small' foreground='%s'>%s</span>", beautiful.fg_color or "#cdd6f4", format_speed(tx_diff)))
    end)
end

local network_widget = wibox.widget {
    {
        {
            markup = string.format("<span weight='bold' foreground='%s'>网络流量</span>", beautiful.yellow_color or "#f9e2af"),
            widget = wibox.widget.textbox
        },
        margins = { left = side_margin, right = side_margin, bottom = dpi(8) },
        widget = wibox.container.margin,
    },
    {
        {
            {
                {
                    markup = string.format("<span font='monospace' size='small' weight='bold' foreground='%s'>RX</span>", beautiful.green_color or "#a6e3a1"),
                    widget = wibox.widget.textbox,
                    forced_width = dpi(25),
                },
                rx_spark,
                rx_speed_txt,
                layout = wibox.layout.align.horizontal,
            },
            {
                {
                    markup = string.format("<span font='monospace' size='small' weight='bold' foreground='%s'>TX</span>", beautiful.blue_color or "#89b4fa"),
                    widget = wibox.widget.textbox,
                    forced_width = dpi(25),
                },
                tx_spark,
                tx_speed_txt,
                layout = wibox.layout.align.horizontal,
            },
            layout = wibox.layout.fixed.vertical,
            spacing = dpi(10),
        },
        margins = dpi(12),
        widget = wibox.container.margin,
    },
    layout = wibox.layout.fixed.vertical,
    spacing = dpi(8),
}

local net_outer = wibox.widget {
    network_widget,
    margins = { left = side_margin, right = side_margin, bottom = dpi(10) },
    widget = wibox.container.margin,
}

-- Wrap the inner content in a background like the notes widget
network_widget.children[2].bg = beautiful.bg_frost_3
network_widget.children[2].shape = helpers.rrect(6)

-- ============== SYSTEM HEALTH & MAINTENANCE ==============
local updates_txt = wibox.widget {
    markup = string.format("<span font='monospace' weight='bold' size='small' foreground='%s'>0</span>", beautiful.fg_color or "#cdd6f4"),
    widget = wibox.widget.textbox,
}

local updates_btn = wibox.widget {
    {
        updates_txt,
        widget = wibox.container.margin,
        margins = { left = dpi(8), right = dpi(8), top = dpi(4), bottom = dpi(4) },
    },
    bg = beautiful.bg_frost_3,
    shape = helpers.rrect(6),
    widget = wibox.container.background,
}

updates_btn:buttons(gears.table.join(
    awful.button({}, 1, function()
        awful.spawn.with_shell((os.getenv("TERMINAL") or "kitty") .. " -e aura -Syu")
    end)
))

local log_content = wibox.widget {
    markup = "",
    widget = wibox.widget.textbox,
}

local log_scroll = wibox.widget {
    log_content,
    widget = wibox.container.scroll.vertical,
    step_size = 10,
}

local log_box = wibox.widget {
    log_scroll,
    widget = wibox.container.background,
    bg = beautiful.bg_frost_3,
    shape = helpers.rrect(6),
}

local health_widget = wibox.widget {
    -- Header with title and update badge
    {
        {
            markup = string.format("<span weight='bold' foreground='%s'>系统健康</span>", beautiful.red_color or "#f38ba8"),
            widget = wibox.widget.textbox
        },
        wibox.widget.textbox(""), -- Spacer
        updates_btn,
        layout = wibox.layout.align.horizontal,
    },
    margins = { left = side_margin, right = side_margin, bottom = dpi(8) },
    widget = wibox.container.margin,
    -- Full-width log content
    {
        log_box,
        margins = { left = side_margin, right = side_margin, bottom = dpi(10) },
        widget = wibox.container.margin,
    },
    layout = wibox.layout.fixed.vertical,
    spacing = dpi(10),
}

local function update_health()
    -- 1. Check Updates
    awful.spawn.easy_async_with_shell("checkupdates 2>/dev/null | wc -l", function(updates)
        local count = tonumber(updates:match("%d+")) or 0
        local color = count > 0 and (beautiful.yellow_color or "#f9e2af") or (beautiful.green_color or "#a6e3a1")
        updates_txt:set_markup(string.format("<span font='monospace' weight='bold' size='small' foreground='%s'>%d</span>", color, count))
    end)

    -- 2. Check System Errors
    local cmd = "systemctl --failed --no-legend | head -n 5; echo '---'; journalctl -b -p 3 -n 5 --no-pager -o cat | head -n 5"
    awful.spawn.easy_async_with_shell(cmd, function(stdout)
        local content = stdout:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
        
        if #content < 15 then
            log_content:set_markup(string.format(
                "<span font='monospace' size='x-small' foreground='%s'>✔ 无系统错误。\n所有服务运行正常。</span>",
                beautiful.green_color or "#a6e3a1"
            ))
        else
            log_content:set_markup(string.format(
                "<span font='monospace' size='x-small' foreground='%s'>%s</span>",
                beautiful.red_color or "#f38ba8", content
            ))
        end
    end)
end

-- ============== ASSEMBLE ==============
main_widget:add(notes_widget)
main_widget:add(net_outer)       -- From the network sparkline code
main_widget:add(health_widget)   -- The new health widget

-- ============== TIMERS ==============
gears.timer { timeout = 2, autostart = true, callback = update_notes }
gears.timer { timeout = 1, autostart = true, callback = update_network }

-- Update health every 5 minutes (300s), but run once on startup
gears.timer { timeout = 300, autostart = true, callback = update_health }

update_notes()
update_network()

gears.timer.delayed_call(function()
    update_health()
end)

return wibox.widget {
    {
        main_widget,
        margins = dpi(20),
        widget = wibox.container.margin
    },
    widget = wibox.container.background,
    bg = beautiful.bg_frost_2,
    shape = helpers.rrect(beautiful.rounded)
}
