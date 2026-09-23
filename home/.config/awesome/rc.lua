-- A random rice. i guess.
-- source: https://github.com/saimoomedits/dotfiles |-| Copyleft © 2022 Saimoomedits
------------------------------------------------------------------------------------
-- Include necessary libraries
local awful = require("awful")
local awesome = awesome

pcall (require, "luarocks.loader")

--package.loaded["naughty.dbus"] = {}

-- home variable 🏠
home_var        = os.getenv("HOME")

-- Debug logging: capture all AwesomeWM errors (including notifications) to debug.txt
local debug_path = home_var .. "/.config/awesome/debug.txt"
awesome.connect_signal("debug::error", function(err)
    local f = io.open(debug_path, "a")
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. tostring(err) .. "\n")
        f:close()
    end
end)


-- user preferences ⚙️
user_likes      = {

    -- aplications
    term        = "kitty",
    editor      = "gram",
    code        = "gram",
    web         = "librewolf",
    discord     = "discord",
    steam       = "kitty jaiba",
    music    = "kitty --class 'music' ncmpcpp ",
    files       =  "thunar",
    llm_port    = 5001, -- Default LLM server port (Ollama/llama.cpp)

    -- coordinates (latitude, longitude) - used by weather and nightlight
    lat = 39.099724,
    lon = -94.578331,

    -- temperature display preference (falsefor celsius)
    use_fahrenheit = true,

    -- nightlight: solar-anchored color temperature via sct.
    -- lat/lon default to user_likes.lat/lon above. Set cap_hour = 24
    -- to disable the 21:00 sunset cap (rarely wanted; see SCIENCE NOTES
    -- in nightlight/init.lua). tick = seconds between re-applies.
    nightlight = {
        day       = 6500,
        pre_dawn  = 3400,
        dusk      = 2700,
        deep      = 1900,
        cap_hour  = 21,
        tick      = 60,
    },

    -- health reminders (set any to false to disable)
    health = {
        water   = true,  -- random 30-90 min
        posture = true,  -- random 20-60 min
        g2g     = true,  -- every 2 hours (grease the groove)
    },

    -- your profile
    username = os.getenv("USER"):gsub("^%l", string.upper),
    userdesc = "@AwesomeWM"
}

-- theme 🖌️
-- Force a fresh load: a poisoned package.loaded cache (left by an earlier
-- crash) can make require("theme") return a stale boolean and skip the
-- theme entirely, leaving beautiful at defaults.
package.loaded["theme"] = nil
require("theme")

-- configs ⚙️
require("config")

-- miscallenous ✨
require("misc")

-- signals 📶
require("signal")

-- ui elements 💻
local layout = require("layout")
local ghost_number = require("layout.ghost-number")

-- nightlight: solar-anchored color temperature.
-- Started after user_likes is defined and after theme/config have settled,
-- so its notifications and signal hooks cooperate with the rest of the WM.
local nightlight = require("nightlight")
nightlight.start()

local CrosshairOverlay = require("layout.crosshair")

-- Create once. Pass a Valorant code here if you want a permanent default,
-- or leave empty for the module defaults.
local crosshair = CrosshairOverlay("0;P;h;0;f;0;0t;1;0l;3;0o;1;0a;1;0f;0;1b;0")

awful.spawn.with_shell("$HOME/.config/awesome/misc/scripts/autorun.sh")
