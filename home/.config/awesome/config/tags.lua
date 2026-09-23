-- tags / layouts
-- ~~~~~~~~~~~~~~
local awful  = require("awful")
local brrr   = require("mods.layout-brrr")

-- 📐 Layout reference
local layouts = {
    brrr     = brrr,
}

-- ️ Tag configuration table
-- Define defaults once, override per-tag if needed.
local tag_defaults = {
    gap               = 3,
    gap_single_client = true,
}

local tag_list = {
    { name = "1", layout = layouts.brrr },
    { name = "2", layout = layouts.brrr },
    { name = "3", layout = layouts.brrr },
    { name = "4", layout = layouts.brrr },
    { name = "5", layout = layouts.brrr },
    { name = "6", layout = layouts.brrr },
    { name = "7", layout = layouts.brrr },
    { name = "8", layout = layouts.brrr },
    { name = "9", layout = layouts.brrr },
    { name = "0", layout = layouts.brrr },
}

-- 🖥️ Create tags on each screen (multi-monitor safe)
screen.connect_signal("request::desktop_decoration", function(s)
    -- Remove default padding; we control spacing via gaps
    s.padding = { left = 0, right = 0, top = 0, bottom = 0 }

    local first_tag = nil

    for i, conf in ipairs(tag_list) do
        local t = awful.tag.add(conf.name, {
            layout            = conf.layout,
            screen            = s,
            gap               = tag_defaults.gap,
            gap_single_client = tag_defaults.gap_single_client,
        })
        
        -- Capture the very first tag so we can focus it
        if i == 1 then first_tag = t end
    end

    -- Auto-focus first tag on startup safely
    if first_tag then
        first_tag:view_only()
    end
end)