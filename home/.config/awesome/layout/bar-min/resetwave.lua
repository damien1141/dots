-- resetwave.lua
-- Ambient thin bar widget for a VERTICAL bar: hydration pulses, health
-- reminders (water/posture/g2g), and LLM status/feedback.
--
-- LISTENS:
--   health::water, health::posture, health::g2g
--   health::fitness                                 (legacy alias -> g2g)
--   health::test, "kind"
--   llm::mode / llm::blink / llm::ready
--
-- EMITS:
--   health::water / health::posture / health::g2g (+ health::fitness)
--
-- CONFIG (rc.lua, all optional):
--   user_likes.llm_port = 5001
--   user_likes.resetwave_width = 3.5
--   user_likes.health = {
--       water   = true,
--       posture = true,
--       g2g     = true, -- false disables schedule
--   }
--   user_likes.resetwave_debug = true
--   user_likes.resetwave_idle_breath = false

local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")
local lgi   = require("lgi")
local cairo = lgi.cairo
local GLib  = lgi.GLib
local math  = math

-- =====================================================================
-- DEBUG LOG CONFIG
-- =====================================================================
-- false = no debug file writes
-- true  = append to ~/.config/awesome/debug.txt
local RESETWAVE_DEBUG = false

local LOG_PATH = (function()
    local ok, gfs = pcall(require, "gears.filesystem")
    if ok and gfs and gfs.get_configuration_dir then
        return gfs.get_configuration_dir() .. "debug.txt"
    end
    return (os.getenv("HOME") or "/tmp") .. "/.config/awesome/debug.txt"
end)()

local function log(msg)
    if not RESETWAVE_DEBUG then return end
    pcall(function()
        local f = io.open(LOG_PATH, "a")
        if f then
            f:write(os.date("%Y-%m-%d %H:%M:%S") .. " resetwave: " .. tostring(msg) .. "\n")
            f:close()
        end
    end)
end

log("module loaded")

-- =====================================================================
-- CONFIG
-- =====================================================================
local EVENT_DURATION    = 80
local PULSE_SPEED       = 3
local PULSE_INTERVAL    = 30 * 60
local LINE_HEIGHT       = (user_likes and user_likes.resetwave_width) or 3.5
local LLM_POLL_INTERVAL = 5
local LLM_PORT          = (user_likes and user_likes.llm_port) or 5001

local DONE_DURATION     = 1.5
local RIPPLE_DURATION   = 1.2

local ACTIVE_RATE       = 1 / 25
local IDLE_RATE         = 0.12
local IDLE_BREATH       = not ((user_likes and user_likes.resetwave_idle_breath) == false)
local DEBUG             = (user_likes and user_likes.resetwave_debug) == true

local function dbg(msg)
    if DEBUG then log(msg) end
end

log("module loaded")

local MOTION = {
    scanner_wave  = 8,
    scanner_wave2 = 12,
    water_drop    = { 13, 9, 17, 11 },
    water_tide    = 7,
    posture_climb = 5,
    posture_rest  = 1.5,
    g2g_leg       = 2.2,
    g2g_ebb       = 9,
    pulse_sheen   = 10,
}

local HEALTH_INTERVALS = {
    water   = { 30 * 60, 90 * 60 },
    posture = { 20 * 60, 60 * 60 },
}

-- =====================================================================
-- COLORS
-- =====================================================================
local COLORS = {
    IDLE     = { r = 88/255,  g = 178/255, b = 220/255 },
    DONE     = { r = 93/255,  g = 172/255, b = 129/255 },
    CHAT     = { r = 168/255, g = 216/255, b = 185/255 },
    RESEARCH = { r = 139/255, g = 129/255, b = 195/255 },
    WHITE    = { r = 252/255, g = 250/255, b = 242/255 },
    RED      = { r = 203/255, g = 27/255,  b = 69/255  },
    WATER    = { r = 129/255, g = 199/255, b = 212/255 },
    FITNESS  = { r = 255/255, g = 177/255, b = 27/255  },
    POSTURE  = { r = 220/255, g = 159/255, b = 180/255 },
}

-- =====================================================================
-- STATE
-- =====================================================================
local STATE = {
    IDLE                = 0,
    BLUE_PULSING        = 1,
    RESEARCH_GENERATING = 2,
    CHAT_GENERATING     = 3,
    DONE_FLASH          = 4,
    SINGLE_BLINK        = 5,
    RED_TRIPLE          = 6,
    READY_RIPPLE        = 7,
    HEALTH_REMIND       = 10,
}

local HEALTH_KINDS = {
    water   = { color = COLORS.WATER   },
    posture = { color = COLORS.POSTURE },
    g2g     = { color = COLORS.FITNESS },
    fitness = { color = COLORS.FITNESS },
}

local current_state = STATE.IDLE
local current_r, current_g, current_b = COLORS.IDLE.r, COLORS.IDLE.g, COLORS.IDLE.b
local current_alpha = 0.2

local llm_was_active    = false
local current_llm_mode  = nil
local llm_current_color = COLORS.WHITE

local blue_pulse_start   = 0
local done_flash_start   = 0
local single_blink_start = 0
local single_blink_color = COLORS.WHITE
local red_triple_start   = 0
local ready_ripple_start = 0

local health_active = nil
local health_start  = 0
local health_resume = nil

local resetwave = wibox.widget.base.make_widget()

-- =====================================================================
-- HELPERS
-- =====================================================================
local function get_time()
    return GLib.get_monotonic_time() / 1000000
end

local function clamp01(v)
    if v < 0 then return 0 elseif v > 1 then return 1 end
    return v
end

local function ease_out(t)     return 1 - (1 - t) ^ 3 end
local function ease_in_out(t) return t < 0.5 and 4 * t ^ 3 or 1 - ((-2 * t + 2) ^ 3) / 2 end
local function ease_out_back(t)
    local c1, c3 = 1.70158, 2.70158
    return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local function request_redraw()
    resetwave:emit_signal("widget::redraw_needed")
    resetwave:emit_signal("widget::updated")
end

function resetwave:fit(context, width, height)
    return LINE_HEIGHT, height
end

local function vfill(cr, width, height, c, a)
    if a <= 0 then return end
    local pat = cairo.Pattern.create_linear(0, 0, 0, height)
    pat:add_color_stop_rgba(0.0, c.r, c.g, c.b, a * 0.85)
    pat:add_color_stop_rgba(0.5, c.r, c.g, c.b, a)
    pat:add_color_stop_rgba(1.0, c.r, c.g, c.b, a * 0.85)
    cr:set_source(pat)
    cr:rectangle(0, 0, width, height)
    cr:fill()
end

local function blob(cr, width, c, y, sz, peak)
    if sz <= 0 or peak <= 0 then return end
    local pat = cairo.Pattern.create_linear(0, y - sz, 0, y + sz)
    pat:add_color_stop_rgba(0.0, c.r, c.g, c.b, 0.0)
    pat:add_color_stop_rgba(0.5, c.r, c.g, c.b, clamp01(peak))
    pat:add_color_stop_rgba(1.0, c.r, c.g, c.b, 0.0)
    cr:set_source(pat)
    cr:rectangle(0, y - sz, width, sz * 2)
    cr:fill()
end

local function comet(cr, width, height, c, y, tail, peak, dir)
    if tail <= 0 or peak <= 0 then return end
    local ty = y + dir * tail
    local pat = cairo.Pattern.create_linear(0, y, 0, ty)
    pat:add_color_stop_rgba(0.00, c.r, c.g, c.b, clamp01(peak))
    pat:add_color_stop_rgba(0.25, c.r, c.g, c.b, peak * 0.60)
    pat:add_color_stop_rgba(0.60, c.r, c.g, c.b, peak * 0.22)
    pat:add_color_stop_rgba(1.00, c.r, c.g, c.b, 0.0)
    cr:set_source(pat)
    cr:rectangle(0, math.min(y, ty), width, math.abs(ty - y))
    cr:fill()
    local cap = math.min(tail * 0.35, height * 0.25)
    blob(cr, width, c, y, cap, peak * 0.8)
end

-- =====================================================================
-- DRAWING
-- =====================================================================
local function draw_scanner(cr, width, height, t, c)
    local flick = 0.92 + 0.08 * math.sin(t * 5.1) * math.sin(t * 2.3)
    vfill(cr, width, height, c, 0.35 * flick)

    local waves = {
        { period = MOTION.scanner_wave,  glow = 0.50, amp = 0.85, off = 0.00, up = false },
        { period = MOTION.scanner_wave2, glow = 0.80, amp = 0.35, off = 0.50, up = true  },
    }

    for _, wv in ipairs(waves) do
        local glow = wv.glow * height
        local cycle = height + 2 * glow
        local frac = (t / wv.period + wv.off) % 1
        if wv.up then frac = 1 - frac end
        local pos = frac * cycle - glow

        local pat = cairo.Pattern.create_linear(0, pos, 0, pos + glow)
        pat:add_color_stop_rgba(0.00, c.r, c.g, c.b, 0.0)
        pat:add_color_stop_rgba(0.35, c.r, c.g, c.b, 0.55 * wv.amp)
        pat:add_color_stop_rgba(0.55, c.r, c.g, c.b, wv.amp)
        pat:add_color_stop_rgba(1.00, c.r, c.g, c.b, 0.0)
        cr:set_source(pat)
        cr:rectangle(0, 0, width, height)
        cr:fill()
    end
end

local function draw_ripple(cr, width, height, elapsed)
    local c = llm_current_color
    local progress = clamp01(elapsed / RIPPLE_DURATION)
    local e = ease_out_back(progress)
    local alpha = (1 - progress) ^ 1.5
    local center = height / 2
    local expand = math.max(0, e) * height + 1

    local pat = cairo.Pattern.create_linear(0, center - expand, 0, center + expand)
    pat:add_color_stop_rgba(0.00, c.r, c.g, c.b, 0.0)
    pat:add_color_stop_rgba(0.35, c.r, c.g, c.b, alpha * 0.5)
    pat:add_color_stop_rgba(0.50, c.r, c.g, c.b, alpha)
    pat:add_color_stop_rgba(0.65, c.r, c.g, c.b, alpha * 0.5)
    pat:add_color_stop_rgba(1.00, c.r, c.g, c.b, 0.0)
    cr:set_source(pat)
    cr:rectangle(0, 0, width, height)
    cr:fill()
end

local function draw_done(cr, width, height, elapsed)
    local c = COLORS.DONE
    local progress = clamp01(elapsed / DONE_DURATION)
    local e = ease_in_out(progress)

    vfill(cr, width, height, c, (1 - progress) * 0.5)
    local sweep = height * 1.4
    local y = e * (height + sweep) - sweep * 0.5

    comet(cr, width, height, c, y, sweep * 0.8, 1 - progress * 0.55, -1)
    comet(cr, width, height, c, y - height * 0.35, sweep * 0.6, (1 - progress) * 0.3, -1)
end

local function draw_health(cr, width, height, t, elapsed)
    local kind = health_active or "water"
    local c = (HEALTH_KINDS[kind] or HEALTH_KINDS.water).color
    local progress = clamp01(elapsed / EVENT_DURATION)
    local env = (1 - progress) ^ 1.4

    if kind == "water" then
        local tide = 0.5 + 0.5 * math.sin(elapsed * 2 * math.pi / MOTION.water_tide)
        vfill(cr, width, height, c, (0.12 + 0.12 * tide) * env)

        local sizes  = { 0.24, 0.16, 0.30, 0.20 }
        local phases = { 0.00, 0.35, 0.60, 0.82 }

        for i, period in ipairs(MOTION.water_drop) do
            local sz = sizes[i] * height
            local cycle = height + 2 * sz
            local y = ((t / period + phases[i]) % 1) * cycle - sz
            local shimmer = 0.75 + 0.25 * math.sin(t * 1.5 + i * 2.1)
            blob(cr, width, c, y, sz, 0.65 * env * shimmer)
        end

    elseif kind == "posture" then
        local base = 0.5 + 0.5 * math.sin(elapsed * 1.1)
        vfill(cr, width, height, c, (0.08 + 0.10 * base) * env)

        local period = MOTION.posture_climb + MOTION.posture_rest
        local p = elapsed % period

        if p < MOTION.posture_climb then
            local cp = p / MOTION.posture_climb
            local head = (1 - ease_out(cp)) * height
            local attack  = clamp01(p / 0.5)
            local release = clamp01((MOTION.posture_climb - p) / 0.6)
            comet(cr, width, height, c, head, height * 0.85, 0.9 * env * attack * release, 1)
        end

    else
        local burst = 0.5 + 0.5 * math.sin(elapsed * 2 * math.pi / MOTION.g2g_ebb)
        local beat = 0.5 + 0.5 * math.sin(elapsed * 4.0)
        vfill(cr, width, height, c, (0.10 + 0.12 * beat) * env)

        local u = (elapsed / MOTION.g2g_leg) % 2
        local peak = 0.85 * env * (0.35 + 0.65 * burst)

        if u < 1 then
            comet(cr, width, height, c, ease_in_out(u) * height, height * 0.8, peak, -1)
        else
            comet(cr, width, height, c, (1 - ease_in_out(u - 1)) * height, height * 0.8, peak, 1)
        end
    end
end

function resetwave:draw(context, cr, width, height)
    if width <= 0 or height <= 0 then return end

    cr:set_operator(cairo.Operator.CLEAR)
    cr:paint()
    cr:set_operator(cairo.Operator.OVER)

    local t = get_time()
    local s = current_state

    if s == STATE.RESEARCH_GENERATING or s == STATE.CHAT_GENERATING then
        draw_scanner(cr, width, height, t,
                     s == STATE.RESEARCH_GENERATING and COLORS.RESEARCH or COLORS.CHAT)

    elseif s == STATE.READY_RIPPLE then
        draw_ripple(cr, width, height, t - ready_ripple_start)

    elseif s == STATE.DONE_FLASH then
        draw_done(cr, width, height, t - done_flash_start)

    elseif s == STATE.HEALTH_REMIND then
        draw_health(cr, width, height, t, t - health_start)

    else
        vfill(cr, width, height,
              { r = current_r, g = current_g, b = current_b }, current_alpha)

        if s == STATE.BLUE_PULSING then
            local sz = height * 0.45
            local cycle = height + 2 * sz
            local y = ((t / MOTION.pulse_sheen) % 1) * cycle - sz
            blob(cr, width, COLORS.IDLE, y, sz, 0.45)
        end
    end
end

-- =====================================================================
-- ANIMATION TIMER
-- =====================================================================
local anim_timer = gears.timer { timeout = ACTIVE_RATE }
local last_tick = 0

local function start_timer(rate)
    anim_timer:stop()
    anim_timer.timeout = rate
    anim_timer:start()
end

local function set_cadence(rate)
    if anim_timer.timeout ~= rate then
        start_timer(rate)
    end
end

local function ensure_anim()
    start_timer(ACTIVE_RATE)
end

anim_timer:connect_signal("timeout", function()
    local t = get_time()
    local dt = t - last_tick
    if last_tick == 0 or dt <= 0 or dt > 0.5 then dt = ACTIVE_RATE end
    last_tick = t

    local s = current_state

    if s == STATE.BLUE_PULSING then
        local elapsed = t - blue_pulse_start
        if elapsed >= EVENT_DURATION then
            current_state = llm_was_active
                and (current_llm_mode == "research" and STATE.RESEARCH_GENERATING or STATE.CHAT_GENERATING)
                or STATE.IDLE
            current_alpha = 0.2
        else
            local wave = 0.5 + 0.5 * math.sin(elapsed * (2 * math.pi / PULSE_SPEED))
            current_alpha = 0.2 + wave * 0.6
            current_r, current_g, current_b = COLORS.IDLE.r, COLORS.IDLE.g, COLORS.IDLE.b
        end

    elseif s == STATE.DONE_FLASH then
        if t - done_flash_start >= DONE_DURATION then current_state = STATE.IDLE end

    elseif s == STATE.SINGLE_BLINK then
        local elapsed = t - single_blink_start
        local cycle = 0.6
        if elapsed >= cycle then
            current_state = llm_was_active
                and (current_llm_mode == "research" and STATE.RESEARCH_GENERATING or STATE.CHAT_GENERATING)
                or STATE.IDLE
            current_alpha = 0.2
        else
            local p = elapsed / cycle
            current_alpha = 0.2 + (1 - p) ^ 2 * 0.8
            current_r, current_g, current_b = single_blink_color.r, single_blink_color.g, single_blink_color.b
        end

    elseif s == STATE.RED_TRIPLE then
        local elapsed = t - red_triple_start
        local cycle, count = 0.3, 3
        if elapsed >= cycle * count then
            current_state = STATE.IDLE
        else
            local phase = (elapsed % cycle) / cycle
            current_alpha = math.max(0, math.sin(math.pi * phase))
            current_r, current_g, current_b = COLORS.RED.r, COLORS.RED.g, COLORS.RED.b
        end

    elseif s == STATE.READY_RIPPLE then
        if t - ready_ripple_start >= RIPPLE_DURATION then current_state = STATE.IDLE end

    elseif s == STATE.HEALTH_REMIND then
        if t - health_start >= EVENT_DURATION then
            current_state = health_resume or STATE.IDLE
            health_active, health_resume = nil, nil
            current_alpha = 0.2
        end

    elseif s == STATE.RESEARCH_GENERATING or s == STATE.CHAT_GENERATING then
        -- keep alive

    else
        local target_a = IDLE_BREATH and (0.15 + 0.05 * (0.5 + 0.5 * math.sin(t * 1.26))) or 0.2
        local k = clamp01(dt * 5)

        current_r = current_r + (COLORS.IDLE.r - current_r) * k
        current_g = current_g + (COLORS.IDLE.g - current_g) * k
        current_b = current_b + (COLORS.IDLE.b - current_b) * k
        current_alpha = current_alpha + (target_a - current_alpha) * k

        if IDLE_BREATH then
            set_cadence(IDLE_RATE)
        else
            local settled = math.abs(current_r - COLORS.IDLE.r) < 0.01
                and math.abs(current_g - COLORS.IDLE.g) < 0.01
                and math.abs(current_b - COLORS.IDLE.b) < 0.01
                and math.abs(current_alpha - 0.2) < 0.01
            if settled then anim_timer:stop() end
        end
    end

    request_redraw()
end)

-- =====================================================================
-- LLM SIGNALS
-- =====================================================================
awesome.connect_signal("llm::mode", function(mode)
    current_llm_mode = mode
    if mode == "research" then llm_current_color = COLORS.RESEARCH
    elseif mode == "chat" then llm_current_color = COLORS.CHAT
    else llm_current_color = COLORS.WHITE end
end)

awesome.connect_signal("llm::blink", function(color_name)
    dbg("llm blink: " .. tostring(color_name))

    local c = COLORS.WHITE
    if llm_was_active or current_llm_mode then
        local color_map = {
            white    = llm_current_color,
            red      = COLORS.RED,
            chat     = COLORS.CHAT,
            research = COLORS.RESEARCH,
        }
        c = color_map[color_name] or COLORS.WHITE
    end

    if color_name == "red" then
        current_state = STATE.RED_TRIPLE
        red_triple_start = get_time()
        llm_was_active = false
        current_llm_mode = nil
        llm_current_color = COLORS.WHITE
    else
        single_blink_color = c
        single_blink_start = get_time()
        current_state = STATE.SINGLE_BLINK
    end

    ensure_anim()
end)

awesome.connect_signal("llm::ready", function(mode)
    current_llm_mode = mode
    if mode == "research" then llm_current_color = COLORS.RESEARCH
    elseif mode == "chat" then llm_current_color = COLORS.CHAT end

    ready_ripple_start = get_time()
    current_state = STATE.READY_RIPPLE
    ensure_anim()
end)

-- =====================================================================
-- HEALTH SIGNALS
-- =====================================================================
local function trigger_health(kind)
    if not HEALTH_KINDS[kind] then
        log("unknown health kind: " .. tostring(kind))
        return
    end

    log("health reminder triggered: " .. kind)

    if current_state == STATE.RESEARCH_GENERATING or current_state == STATE.CHAT_GENERATING then
        health_resume = current_state
    elseif current_state ~= STATE.HEALTH_REMIND then
        health_resume = nil
    end

    health_active = kind
    health_start = get_time()
    current_state = STATE.HEALTH_REMIND
    ensure_anim()
end

for _, name in ipairs({ "water", "posture", "g2g" }) do
    local captured_name = name
    awesome.connect_signal("health::" .. name, function()
        trigger_health(captured_name)
    end)
end

awesome.connect_signal("health::fitness", function() trigger_health("g2g") end)
awesome.connect_signal("health::test", function(kind) trigger_health(tostring(kind)) end)

-- =====================================================================
-- PUBLIC API
-- =====================================================================
function resetwave:pulse()
    blue_pulse_start = get_time()
    current_state = STATE.BLUE_PULSING
    ensure_anim()
end

function resetwave:remind(kind)
    trigger_health(kind)
end

resetwave.test = resetwave.remind

-- =====================================================================
-- LLM POLLER
-- =====================================================================
local llm_poll_timer = gears.timer {
    timeout = LLM_POLL_INTERVAL,
    call_now = true,
    callback = function()
        awful.spawn.easy_async(
            string.format("curl -s -o /dev/null -w '%%{http_code}' --max-time 2 http://localhost:%d/health?fail_on_no_slot=1", LLM_PORT),
            function(stdout)
                stdout = stdout or ""
                local clean_stdout = stdout:gsub("%s+", "")
                local status = tonumber(clean_stdout)
                local server_is_running = (status ~= nil and status > 0)
                local server_is_generating = (status == 503)

                if current_state == STATE.BLUE_PULSING then
                    llm_was_active = server_is_generating
                    return
                end

                if server_is_generating and not llm_was_active then
                    local target
                    if current_llm_mode == "research" then
                        target = STATE.RESEARCH_GENERATING
                        llm_current_color = COLORS.RESEARCH
                    else
                        target = STATE.CHAT_GENERATING
                        llm_current_color = COLORS.CHAT
                    end

                    if current_state == STATE.HEALTH_REMIND then
                        health_resume = target
                    else
                        current_state = target
                    end

                    ensure_anim()
                    dbg("llm: generation started (" .. (current_llm_mode or "chat") .. ")")

                elseif not server_is_generating and llm_was_active then
                    if server_is_running then
                        if current_state == STATE.HEALTH_REMIND then
                            health_resume = nil
                            dbg("llm: generation finished (health reminder still active)")
                        else
                            current_state = STATE.DONE_FLASH
                            done_flash_start = get_time()
                            ensure_anim()
                            dbg("llm: generation finished")
                        end
                    else
                        if current_state == STATE.HEALTH_REMIND then
                            health_resume = nil
                            dbg("llm: server gone (health reminder still active)")
                        else
                            current_llm_mode = nil
                            llm_current_color = COLORS.WHITE
                            current_state = STATE.IDLE
                            current_alpha = 0.2
                            current_r, current_g, current_b = COLORS.IDLE.r, COLORS.IDLE.g, COLORS.IDLE.b
                        end
                        request_redraw()
                        dbg("llm: server gone")
                    end
                end

                llm_was_active = server_is_generating
            end
        )
    end,
}

-- =====================================================================
-- HEALTH SCHEDULER
-- =====================================================================
math.randomseed(os.time())

local function rand_interval(min_s, max_s)
    return min_s + math.random() * (max_s - min_s)
end

local function health_interval(kind)
    local h = user_likes and user_likes.health
    local v = h and h[kind]

    if v == false then return nil end
    if type(v) == "number" then return { v, v } end

    if type(v) == "table" then
        if v.interval then return { v.interval, v.interval } end
        local mn = v.min or 60
        return { mn, v.max or mn }
    end

    local d = HEALTH_INTERVALS[kind] or { 60, 300 }
    return { d[1], d[2] }
end

local health_next = {
    water = nil,
    posture = nil,
}

local scheduler_armed = false

local function fmt_ts(ts)
    if not ts then return "off" end
    return os.date("%H:%M:%S", math.floor(ts))
end

local function arm_water()
    local iv = health_interval("water")
    if not iv then
        health_next.water = nil
        log("water disabled")
        return
    end

    local now = os.time()
    health_next.water = math.floor(now + rand_interval(iv[1], iv[2]))
    log(string.format("water armed: %s (in %.1f min)", fmt_ts(health_next.water), (health_next.water - now) / 60))
end

local function arm_posture()
    local iv = health_interval("posture")
    if not iv then
        health_next.posture = nil
        log("posture disabled")
        return
    end

    local now = os.time()
    local offset = rand_interval(10 * 60, 25 * 60)
    health_next.posture = math.floor(now + offset + rand_interval(iv[1], iv[2]))
    log(string.format("posture armed: %s (in %.1f min)", fmt_ts(health_next.posture), (health_next.posture - now) / 60))
end

local function safe_emit_health(kind)
    local ok, err = pcall(function()
        awesome.emit_signal("health::" .. kind)
        if kind == "g2g" then
            awesome.emit_signal("health::fitness")
        end
    end)

    if not ok then
        log("emit error for " .. kind .. ": " .. tostring(err))
    end
end

local function fire_water()
    log("water FIRED")
    safe_emit_health("water")
    arm_water()
end

local function fire_posture()
    log("posture FIRED")
    safe_emit_health("posture")
    arm_posture()
end

-- g2g fixed schedule
local G2G_SCHEDULE = {
    { hour = 11, min = 30 },
    { hour = 13, min = 30 },
    { hour = 15, min = 30 },
    { hour = 17, min = 30 },
    { hour = 19, min = 30 },
}

local G2G_CATCH_WINDOW = 5 -- minutes

local g2g_fired_date = nil
local g2g_fired_slots = {}

local function g2g_enabled()
    local h = user_likes and user_likes.health
    return not (h and h.g2g == false)
end

local function check_g2g_schedule()
    if not g2g_enabled() then return end

    local now = os.date("*t")
    local today = string.format("%04d-%02d-%02d", now.year, now.month, now.day)

    if g2g_fired_date ~= today then
        g2g_fired_date = today
        g2g_fired_slots = {}
        log("g2g day reset: " .. today)
    end

    local now_m = now.hour * 60 + now.min

    for _, slot in ipairs(G2G_SCHEDULE) do
        local key = slot.hour * 100 + slot.min
        local slot_m = slot.hour * 60 + slot.min

        if not g2g_fired_slots[key] then
            if now_m >= slot_m and now_m <= slot_m + G2G_CATCH_WINDOW then
                g2g_fired_slots[key] = true
                log(string.format("g2g FIRED %02d:%02d (now %02d:%02d)", slot.hour, slot.min, now.hour, now.min))
                safe_emit_health("g2g")
                return
            elseif now_m > slot_m + G2G_CATCH_WINDOW then
                g2g_fired_slots[key] = true
                log(string.format("g2g skipped old slot %02d:%02d (now %02d:%02d)", slot.hour, slot.min, now.hour, now.min))
            end
        end
    end
end

local function health_tick()
    if not scheduler_armed then
        arm_water()
        arm_posture()
        scheduler_armed = true
        log("scheduler armed")
    end

    local now = os.time()

    log(string.format(
        "tick now=%s water=%s posture=%s g2g_enabled=%s",
        os.date("%H:%M:%S"),
        fmt_ts(health_next.water),
        fmt_ts(health_next.posture),
        tostring(g2g_enabled())
    ))

    if health_next.water and health_next.water <= now then
        fire_water()
    end

    if health_next.posture and health_next.posture <= now then
        fire_posture()
    end

    check_g2g_schedule()
end

local health_check_timer = gears.timer { timeout = 30 }

health_check_timer:connect_signal("timeout", function()
    local ok, err = pcall(health_tick)
    if not ok then
        log("health_check error: " .. tostring(err))
    end
end)

health_check_timer:start()

-- immediate first run
do
    local ok, err = pcall(health_tick)
    if not ok then
        log("initial health_tick error: " .. tostring(err))
    end
end

-- re-arm shortly after startup so user_likes defined later in rc.lua is visible
local boot_rearm = gears.timer.start_new(0.5, function()
    local ok, err = pcall(function()
        arm_water()
        arm_posture()
        scheduler_armed = true
        log(string.format(
            "re-armed after startup delay: water=%s posture=%s g2g_enabled=%s",
            fmt_ts(health_next.water),
            fmt_ts(health_next.posture),
            tostring(g2g_enabled())
        ))
    end)

    if not ok then
        log("boot_rearm error: " .. tostring(err))
    end
end)

-- =====================================================================
-- LIFECYCLE
-- =====================================================================
local main_timer = gears.timer {
    timeout = PULSE_INTERVAL,
    call_now = false,
    callback = function() resetwave:pulse() end,
}

main_timer:start()
llm_poll_timer:start()

if IDLE_BREATH then
    anim_timer.timeout = IDLE_RATE
    anim_timer:start()
end

awesome.connect_signal("exit", function()
    anim_timer:stop()
    llm_poll_timer:stop()
    main_timer:stop()
    health_check_timer:stop()
    boot_rearm:stop()
end)

return resetwave
