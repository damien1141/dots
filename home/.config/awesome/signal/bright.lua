-- signal/bright.lua
-- ============================================================
-- SOURCE OF TRUTH for all brightness control in the rice.
-- ============================================================
-- Every keybind, slider, and popup should go through this module.
--   * Keys:     XF86MonBrightnessUp/Down  ->  brightness.up() / .down()
--   * Control-center slider drag        ->  brightness.set_hw(val)
--   * Bar slider drag / scroll wheel    ->  brightness.set(val) (see bar-min/sliders.lua)
--
-- Slider value model (0-100, unified):
--   0  - 50  : software dim zone (overlay wibox opacity; hardware stays at 0%)
--   51 - 100 : hardware zone  (xrandr gamma untouched, hardware brightnessctl)
--
-- Edit constants below to tune behaviour. Do NOT fork per-callsite.
-- ============================================================
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local beautiful = require("beautiful")

local M = {}

local min_sw = 20   -- max gamma dim (20% opacity)
local step = 5      -- step size
local state = {
    current = 100,  -- unified 0-100 slider value
    hw = 100,       -- hardware percentage
    sw = 100        -- software overlay (100 = invisible)
}

-- Flag to prevent feedback loops when dragging the slider
local ignore_hw_update = false
local ignore_hw_timer = gears.timer({
    timeout = 0.5,
    single_shot = true,
    callback = function() ignore_hw_update = false end
})

-- (ICC profile loading moved to signal/icc.lua -- it composes with
-- nightlight's gamma writes and must be ordered after them.)

-- ==========================================
-- 1. SOFTWARE DIMMER OVERLAY (Picom)
-- ==========================================
local overlays = {}
for s in screen do
    local w = wibox({
        screen = s, bg = "#000000", visible = false, ontop = true, opacity = 0,
        type = "splash", input_passthrough = true,
        x = s.geometry.x, y = s.geometry.y,
        width = s.geometry.width, height = s.geometry.height,
    })
    overlays[s] = w
end

screen.connect_signal("property::geometry", function(s)
    if overlays[s] then
        overlays[s].x = s.geometry.x
        overlays[s].y = s.geometry.y
        overlays[s].width = s.geometry.width
        overlays[s].height = s.geometry.height
    end
end)

local function apply_sw_dim()
    local max_dim = 1.0 - (min_sw / 100.0)
    local opacity = 0
    if state.sw < 100 then
        opacity = ((100 - state.sw) / (100 - min_sw)) * max_dim
    end
    
    for s, w in pairs(overlays) do
        if opacity > 0 then
            w.opacity = opacity
            w.visible = true
        else
            w.visible = false
        end
    end
end

-- ==========================================
-- 2. HARDWARE BRIGHTNESS SYNC
-- ==========================================
-- inotify on /sys/class/backlight fires for every brightnessctl write, and
-- can also fire for non-user reasons (suspend/resume, AC events, etc.).
-- Before the fix, every kernel write caused update_hw() to emit
-- signal::brightness, which nightlight's bridge consumed by re-applying
-- sct. The cascade produced a visible red flash whenever the slider
-- was dragged during the night curve. We now keep state.hw in sync but
-- only emit when the unified slider value actually changes.
local last_emitted_slider = state.current

local function emit_if_changed(val)
    if val ~= last_emitted_slider then
        last_emitted_slider = val
        awesome.emit_signal("signal::brightness", val)
    end
end

local function update_hw()
    awful.spawn.easy_async("brightnessctl i | grep -oP '\\(\\K[^%\\)]+'", function(out)
        local p = math.floor(tonumber(out) or 0)

        -- If we just moved the slider, ignore this feedback
        if ignore_hw_update then return end

        -- If we are in gamma zone and hardware bounces around 0-1%, ignore it
        if state.current <= 50 and p <= 1 then
            state.hw = p
            return
        end

        state.hw = p
        if p > 1 then
            local slider_val = math.floor(50 + (p / 2))
            if slider_val > 100 then slider_val = 100 end
            state.current = slider_val
            state.sw = 100
            apply_sw_dim()
            emit_if_changed(slider_val)
        else
            if state.current > 50 then
                state.current = 50
                state.sw = 100
                apply_sw_dim()
                emit_if_changed(50)
            end
        end
    end)
end

awful.spawn.with_line_callback(
    "bash -c 'while inotifywait -e modify /sys/class/backlight/?*/brightness -qq; do echo; done'",
    { stdout = function(_) update_hw() end }
)

-- ==========================================
-- 3. EXPOSED CONTROL FUNCTIONS
-- ==========================================
function M.set(val)
    val = math.max(0, math.min(100, math.floor(val)))
    state.current = val
    
    -- Engage ignore flag and reset it 500ms later
    ignore_hw_update = true
    ignore_hw_timer:again()

    if val > 50 then
        -- Hardware Zone (51-100)
        state.sw = 100
        apply_sw_dim()

        local hw_val = math.floor((val - 50) * 2)
        if hw_val == 0 then hw_val = 1 end
        state.hw = hw_val
        awful.spawn("brightnessctl set " .. hw_val .. "%", false)
    else
        -- Gamma Zone (0-50)
        if state.hw > 1 then
            state.hw = 0
            awful.spawn("brightnessctl set 0%", false)
        end

        local sw_range = 100 - min_sw
        local sw_val = math.floor(min_sw + (val / 50) * sw_range)
        state.sw = sw_val
        apply_sw_dim()
    end

    emit_if_changed(val)
end

function M.up()
    M.set(state.current + step)
end

function M.down()
    M.set(state.current - step)
end

function M.set_hw(val)
    M.set(val)
end

update_hw()

return M