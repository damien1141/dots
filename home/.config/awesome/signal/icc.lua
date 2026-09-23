-- signal/icc.lua
-- ICC profile loader. Provides gamut management (primaries + white point)
-- for color-aware applications via the _ICC_PROFILE RandR atom.
--
-- The profile is MATRIX-ONLY (no VideoLUT/gamma curves). Nightlight and
-- brightness own the gamma LUT entirely -- nightlight via sct on
-- every mode change, brightness via the periodic tick for self-heal.
--
-- Why dispwin -I (not xcalib):
--   * xcalib requires a vcgt tag to set the _ICC_PROFILE atom, but our
--     matrix-only profile has no vcgt. dispwin -I can install a profile
--     without touching the LUT (good for our use case).
--   * dispwin sets the _ICC_PROFILE atom that color-aware apps and the
--     screenshot pipeline use.
--   * dispwin -I is idempotent and safe to call repeatedly.
--
-- When ICC reloads:
--   * Reload on discrete nightlight events: toggle, set_temp, init, off,
--     brightness-bridge re-assert, dip preview. These change the gamma LUT
--     in a way that clobbers the _ICC_PROFILE atom.
--   * Do NOT reload on auto-curve periodic ticks ("day", "dusk ramp", etc.)
--     -- those are gradual transitions where the LUT changes slowly and
--     ICC re-application would cause flicker.
-- ---------------------------------------------------------------------------

local awful = require("awful")
local gears = require("gears")
local naughty = require("naughty")

local M = {}

-- Profiles keyed by RandR output name. The user can extend this table.
local PROFILES = {
    ["eDP-1"]  = "/home/solis/icc/B160ZAN01_U_matrix.icm",
    ["eDP"]    = "/home/solis/icc/B160ZAN01_U_matrix.icm",
    ["LVDS-1"] = "/home/solis/icc/B160ZAN01_U_matrix.icm",
    ["LVDS"]   = "/home/solis/icc/B160ZAN01_U_matrix.icm",
}

local RELOAD_DEBOUNCE = 0.40     -- collapse bursts of nightlight re-applies
local STARTUP_DELAY   = 2.0      -- let nightlight's first apply land first

-- ---------------------------------------------------------------------------
-- Logging
-- ---------------------------------------------------------------------------

local function log(msg)
    io.stderr:write(("[icc %s] %s\n"):format(os.date("%H:%M:%S"), msg))
end

-- ---------------------------------------------------------------------------
-- Apply one profile to one RandR output via dispwin -I
-- ---------------------------------------------------------------------------

local function apply_profile(out, profile)
    -- Validate the file exists before shelling out.
    awful.spawn.easy_async_with_shell(
        string.format("test -r '%s' && echo ok || echo missing", profile),
        function(stdout)
            if not stdout:match("ok") then
                log(string.format("%s: profile missing or unreadable: %s", out, profile))
                return
            end
            -- dispwin -I installs the profile's _ICC_PROFILE atom without touching
            -- the VideoLUT (since our profile has identity/no TRC curves).
            -- -d 0 targets the primary display.
            awful.spawn.easy_async_with_shell(
                string.format("dispwin -I '%s' 2>&1; echo exit=$?", profile),
                function(out2, _, _, exit_code)
                    local exit_str = out2:match("exit=(%d+)")
                    local exit = tonumber(exit_str) or -1
                    if exit == 0 then
                        log(string.format("%s: dispwin -I installed (%s)", out, profile))
                    else
                        -- dispwin often returns 0 even with warnings, check for actual errors
                        if out2:match("Error") or out2:match("error") then
                            log(string.format("%s: dispwin failed -- output: %s",
                                out, out2:gsub("\n", " "):sub(1, 200)))
                        else
                            log(string.format("%s: dispwin -I installed (%s)", out, profile))
                        end
                    end
                end)
        end)
end

-- ---------------------------------------------------------------------------
-- Master reload: iterate connected outputs, apply each known profile
-- ---------------------------------------------------------------------------

local function reload_all(why)
    log("reload triggered (" .. (why or "?") .. ")")
    awful.spawn.easy_async_with_shell(
        "xrandr | awk '/ connected/{print $1}'",
        function(stdout)
            local applied = 0
            for out in stdout:gmatch("[^\r\n]+") do
                local profile = PROFILES[out]
                if profile then
                    applied = applied + 1
                    apply_profile(out, profile)
                end
            end
            if applied == 0 then
                log("no connected outputs matched any known profile")
            end
        end)
end

-- ---------------------------------------------------------------------------
-- Debounced entry point
-- ---------------------------------------------------------------------------

local _reload_timer = nil
local function schedule_reload(why)
    if not _reload_timer then
        _reload_timer = gears.timer({
            timeout = RELOAD_DEBOUNCE,
            single_shot = true,
            autostart   = false,
            callback    = function() reload_all(_reload_timer._last_why or "?") end,
        })
    end
    _reload_timer._last_why = why
    _reload_timer:again()
end

-- Public API
function M.reload(why)
    schedule_reload(why or "manual")
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

-- Deferred initial load: 2s after require() so nightlight's first apply
-- lands first. The calibration composes on top of the temperature curve
-- rather than getting clobbered by it.
gears.timer.start_new(STARTUP_DELAY, function()
    log("initial load (delayed " .. STARTUP_DELAY .. "s)")
    reload_all("startup")
end)

-- Hotplug
awesome.connect_signal("screen::connect", function()
    schedule_reload("screen::connect")
end)

-- ---------------------------------------------------------------------------
-- Nightlight signal wiring
-- ---------------------------------------------------------------------------

-- Which `apply()` why values indicate a discrete state change (toggle,
-- set_temp, init, off, re-assert, dip) vs a gradual auto-curve tick?
-- Auto-curve reasons are emitted every tick (~60s) and every slew step
-- (~0.1s) during transitions -- reloading ICC on each would cause flicker.
local DISCRETE_WHYS = {
    ["off"]          = true,
    ["manual"]       = true,
    ["manual hold"]  = true,
    ["re-assert"]    = true,
    ["preview"]      = true,
}

local function is_discrete(why)
    return DISCRETE_WHYS[why or ""] == true
end

-- Reload ICC when nightlight mode changes to off.
awesome.connect_signal("nightlight::mode_changed", function(why)
    schedule_reload("nightlight::" .. tostring(why))
end)

-- Reload ICC on discrete nightlight events: toggle, set_temp, init,
-- brightness-bridge re-assert, dip preview.  NOT on auto-curve periodic
-- ticks (day, dusk ramp, evening ramp, night, sunrise ramp) -- that would
-- cause flicker during active use.  nightlight::applied carries the
-- `why` reason as its first argument.
awesome.connect_signal("nightlight::applied", function(k_int, why)
    if is_discrete(why) then
        schedule_reload("nightlight::applied:" .. tostring(why))
    end
end)

-- NOTE: The layering is
--   1. ICC sets the hardware calibration baseline once (per output, per
--      screen hotplug, per manual reload, per mode change). Idempotent.
--   2. sct adjusts color temperature on top.
--      Self-heals via the periodic tick and brightness bridge.

return M