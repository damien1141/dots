-- resetwave.lua
-- Ambient 3.5px bar widget for hydration reminders, fitness, posture, and LLM status/feedback
-- Upgraded with smooth Cairo gradients and eased animations.

local wibox = require("wibox")
local gears = require("gears")
local lgi = require("lgi")
local cairo = lgi.cairo
local GLib = lgi.GLib
local awful = require("awful")
local math = math

-- Configuration
local EVENT_DURATION = 50
local PULSE_SPEED = 2
local PULSE_INTERVAL = 30 * 60
local LINE_HEIGHT = 3.5
local LLM_POLL_INTERVAL = 5
local LLM_PORT = (user_likes and user_likes.llm_port) or 5001

-- Health reminder intervals (seconds)
local HEALTH_WATER_MIN   = 30 * 60
local HEALTH_WATER_MAX   = 90 * 60
local HEALTH_POSTURE_MIN = 20 * 60
local HEALTH_POSTURE_MAX = 60 * 60
local HEALTH_G2G_INTERVAL = 2 * 60 * 60

-- Simplified, Brighter Colors
local COLORS = {
    IDLE       = { r = 88/255,  g = 178/255, b = 220/255 }, -- 空 (SORA) sky blue
    DONE       = { r = 93/255,  g = 172/255, b = 129/255 }, -- 若竹 (WAKATAKE) medium green
    CHAT       = { r = 168/255, g = 216/255, b = 185/255 }, -- 白緑 (BYAKUROKU) pale mint
    RESEARCH   = { r = 139/255, g = 129/255, b = 195/255 }, -- 藤 (FUJI) light periwinkle
    WHITE      = { r = 252/255, g = 250/255, b = 242/255 }, -- 白練 (SHIRONERI) off-white
    RED        = { r = 203/255, g = 27/255,  b = 69/255  }, -- 紅 (KURENAI) crimson

    -- Health reminder colors
    WATER      = { r = 129/255, g = 199/255, b = 212/255 }, -- 水 (MIZU) light cyan blue
    FITNESS    = { r = 255/255, g = 177/255, b = 27/255  }, -- 山吹 (YAMABUKI) golden yellow
    POSTURE    = { r = 220/255, g = 159/255, b = 180/255 }, -- 撫子 (NADESHIKO) soft pink
}

-- State Machine
local STATE = {
    IDLE = 0,
    BLUE_PULSING = 1,
    RESEARCH_GENERATING = 2,
    CHAT_GENERATING = 3,
    DONE_FLASH = 4,
    SINGLE_BLINK = 5,
    RED_TRIPLE = 6,
    READY_RIPPLE = 7,
    -- Health reminder states
    WATER_REMIND   = 10,
    FITNESS_REMIND = 11,
    POSTURE_REMIND = 12,
}

-- State Variables
local current_state = STATE.IDLE
local current_r, current_g, current_b = COLORS.IDLE.r, COLORS.IDLE.g, COLORS.IDLE.b
local current_alpha = 0.2

local llm_was_active = false
local current_llm_mode = nil
local llm_current_color = COLORS.WHITE

local blue_pulse_start = 0
local done_flash_start = 0
local single_blink_start = 0
local single_blink_color = COLORS.WHITE
local red_triple_start = 0
local ready_ripple_start = 0

-- Health reminder timers
local water_remind_start = 0
local fitness_remind_start = 0
local posture_remind_start = 0
local HEALTH_REMIND_DURATION = 8 -- seconds to show reminder

local resetwave = wibox.widget.base.make_widget()

local function get_time()
    return GLib.get_monotonic_time() / 1000000
end

function resetwave:fit(context, width, height)
    return LINE_HEIGHT, height
end

-- ==========================================
-- DRAWING LOGIC (Wider & Brighter Gradients)
-- ==========================================
function resetwave:draw(context, cr, width, height)
    if width <= 0 or height <= 0 then return end

    cr:set_operator(cairo.Operator.CLEAR)
    cr:paint()
    cr:set_operator(cairo.Operator.OVER)

    if current_state == STATE.RESEARCH_GENERATING or current_state == STATE.CHAT_GENERATING then
        -- TRAVELING SCANNER GLOW (vertical)
        local c = (current_state == STATE.RESEARCH_GENERATING) and COLORS.RESEARCH or COLORS.CHAT
        local t = get_time()

        cr:set_source_rgba(c.r, c.g, c.b, 0.35)
        cr:rectangle(0, 0, width, height)
        cr:fill()

        local speed = 350
        local glow_height = height * 0.6
        local pos = (t * speed) % (height + glow_height * 2) - glow_height

        local pat = cairo.Pattern.create_linear(0, pos, 0, pos + glow_height)
        pat:add_color_stop_rgba(0.0, c.r, c.g, c.b, 0.0)
        pat:add_color_stop_rgba(0.3, c.r, c.g, c.b, 0.8)
        pat:add_color_stop_rgba(0.5, c.r, c.g, c.b, 1.0)
        pat:add_color_stop_rgba(0.7, c.r, c.g, c.b, 0.8)
        pat:add_color_stop_rgba(1.0, c.r, c.g, c.b, 0.0)

        cr:set_source(pat)
        cr:rectangle(0, 0, width, height)
        cr:fill()

    elseif current_state == STATE.READY_RIPPLE then
        -- EXPANDING RIPPLE (vertical, uses central LLM color state)
        local t = get_time()
        local elapsed = t - ready_ripple_start
        local duration = 1.0
        local progress = math.min(elapsed / duration, 1.0)

        local c = llm_current_color

        local center = height / 2
        local expand = progress * height
        local alpha = 1.0 - progress

        if expand > 1 then
            local pat = cairo.Pattern.create_linear(0, center - expand, 0, center + expand)
            pat:add_color_stop_rgba(0.0, c.r, c.g, c.b, 0.0)
            pat:add_color_stop_rgba(0.2, c.r, c.g, c.b, alpha * 0.4)
            pat:add_color_stop_rgba(0.5, c.r, c.g, c.b, alpha)
            pat:add_color_stop_rgba(0.8, c.r, c.g, c.b, alpha * 0.4)
            pat:add_color_stop_rgba(1.0, c.r, c.g, c.b, 0.0)

            cr:set_source(pat)
            cr:rectangle(0, 0, width, height)
            cr:fill()
        end

    elseif current_state == STATE.DONE_FLASH then
        -- COMET SWEEP FLASH (vertical)
        local t = get_time()
        local elapsed = t - done_flash_start
        local duration = 0.8
        local progress = elapsed / duration

        if progress < 1.0 then
            local c = COLORS.DONE
            local bg_alpha = (1.0 - progress) * 0.6

            cr:set_source_rgba(c.r, c.g, c.b, bg_alpha)
            cr:rectangle(0, 0, width, height)
            cr:fill()

            local sweep_height = height * 1.2
            local sweep_pos = progress * (height + sweep_height) - (sweep_height / 2)

            local pat = cairo.Pattern.create_linear(0, sweep_pos, 0, sweep_pos + sweep_height)
            pat:add_color_stop_rgba(0.0, c.r, c.g, c.b, 0.0)
            pat:add_color_stop_rgba(0.5, c.r, c.g, c.b, 1.0 - (progress * 0.5))
            pat:add_color_stop_rgba(1.0, c.r, c.g, c.b, 0.0)

            cr:set_source(pat)
            cr:rectangle(0, 0, width, height)
            cr:fill()
        end

    elseif current_state == STATE.WATER_REMIND or current_state == STATE.FITNESS_REMIND or current_state == STATE.POSTURE_REMIND then
        -- Health reminder: pulsing solid color with fade out
        local t = get_time()
        local start_time, color
        if current_state == STATE.WATER_REMIND then
            start_time = water_remind_start
            color = COLORS.WATER
        elseif current_state == STATE.FITNESS_REMIND then
            start_time = fitness_remind_start
            color = COLORS.FITNESS
        else
            start_time = posture_remind_start
            color = COLORS.POSTURE
        end

        local elapsed = t - start_time
        if elapsed < HEALTH_REMIND_DURATION then
            local progress = elapsed / HEALTH_REMIND_DURATION
            -- Pulse while fading
            local pulse = (math.sin(elapsed * 8) + 1) / 2
            local alpha = (1.0 - progress) * (0.4 + pulse * 0.4)

            local pat = cairo.Pattern.create_linear(0, 0, 0, height)
            pat:add_color_stop_rgba(0.0, color.r, color.g, color.b, alpha * 0.6)
            pat:add_color_stop_rgba(0.5, color.r, color.g, color.b, alpha)
            pat:add_color_stop_rgba(1.0, color.r, color.g, color.b, alpha * 0.6)

            cr:set_source(pat)
            cr:rectangle(0, 0, width, height)
            cr:fill()
        end

    else
        -- Fallback for solid colors (IDLE, PULSING, BLINKS) — vertical gradient
        local pat = cairo.Pattern.create_linear(0, 0, 0, height)
        local a = current_alpha
        pat:add_color_stop_rgba(0.0, current_r, current_g, current_b, a * 0.6)
        pat:add_color_stop_rgba(0.5, current_r, current_g, current_b, a)
        pat:add_color_stop_rgba(1.0, current_r, current_g, current_b, a * 0.6)

        cr:set_source(pat)
        cr:rectangle(0, 0, width, height)
        cr:fill()
    end
end

-- ==========================================
-- ANIMATION TIMER (Smoothed Math)
-- ==========================================
local anim_timer = gears.timer { timeout = 0.03 }

anim_timer:connect_signal("timeout", function()
    local t = get_time()

    if current_state == STATE.BLUE_PULSING then
        local elapsed = t - blue_pulse_start
        if elapsed >= EVENT_DURATION then
            current_state = llm_was_active and (current_llm_mode == "research" and STATE.RESEARCH_GENERATING or STATE.CHAT_GENERATING) or STATE.IDLE
            current_alpha = 0.2
        else
            local wave = (math.sin(elapsed * (2 * math.pi / PULSE_SPEED)) + 1) / 2
            current_alpha = 0.2 + (wave * 0.6)
            current_r, current_g, current_b = COLORS.IDLE.r, COLORS.IDLE.g, COLORS.IDLE.b
        end

    elseif current_state == STATE.DONE_FLASH then
        local elapsed = t - done_flash_start
        if elapsed >= 0.8 then
            current_state = STATE.IDLE
            current_alpha = 0.2
            current_r, current_g, current_b = COLORS.IDLE.r, COLORS.IDLE.g, COLORS.IDLE.b
        end

    elseif current_state == STATE.SINGLE_BLINK then
        local elapsed = t - single_blink_start
        local cycle_duration = 0.6
        if elapsed >= cycle_duration then
            current_state = llm_was_active and (current_llm_mode == "research" and STATE.RESEARCH_GENERATING or STATE.CHAT_GENERATING) or STATE.IDLE
            current_alpha = 0.2
        else
            local progress = elapsed / cycle_duration
            current_alpha = 0.2 + ((1 - progress) * 0.8)
            current_r, current_g, current_b = single_blink_color.r, single_blink_color.g, single_blink_color.b
        end

    elseif current_state == STATE.RED_TRIPLE then
        local elapsed = t - red_triple_start
        local cycle_duration = 0.3
        if elapsed >= (cycle_duration * 3) then
            current_state = STATE.IDLE
            current_alpha = 0.2
            current_r, current_g, current_b = COLORS.IDLE.r, COLORS.IDLE.g, COLORS.IDLE.b
        else
            local pulse_progress = (elapsed % cycle_duration) / cycle_duration
            local alpha
            if pulse_progress < 0.1 then
                alpha = pulse_progress / 0.1
            elseif pulse_progress < 0.3 then
                alpha = 1.0
            else
                alpha = 1.0 - ((pulse_progress - 0.3) / 0.7)
            end
            current_alpha = math.max(0, alpha)
            current_r, current_g, current_b = COLORS.RED.r, COLORS.RED.g, COLORS.RED.b
        end

    elseif current_state == STATE.READY_RIPPLE then
        local elapsed = t - ready_ripple_start
        if elapsed >= 1.0 then
            current_state = STATE.IDLE
            current_alpha = 0.2
            current_r, current_g, current_b = COLORS.IDLE.r, COLORS.IDLE.g, COLORS.IDLE.b
        end

    elseif current_state == STATE.WATER_REMIND then
        local elapsed = t - water_remind_start
        if elapsed >= HEALTH_REMIND_DURATION then
            current_state = STATE.IDLE
            current_alpha = 0.2
            current_r, current_g, current_b = COLORS.IDLE.r, COLORS.IDLE.g, COLORS.IDLE.b
        end

    elseif current_state == STATE.FITNESS_REMIND then
        local elapsed = t - fitness_remind_start
        if elapsed >= HEALTH_REMIND_DURATION then
            current_state = STATE.IDLE
            current_alpha = 0.2
            current_r, current_g, current_b = COLORS.IDLE.r, COLORS.IDLE.g, COLORS.IDLE.b
        end

    elseif current_state == STATE.POSTURE_REMIND then
        local elapsed = t - posture_remind_start
        if elapsed >= HEALTH_REMIND_DURATION then
            current_state = STATE.IDLE
            current_alpha = 0.2
            current_r, current_g, current_b = COLORS.IDLE.r, COLORS.IDLE.g, COLORS.IDLE.b
        end

    elseif current_state == STATE.RESEARCH_GENERATING or current_state == STATE.CHAT_GENERATING then
        -- Keep timer alive for animation

    else
        current_alpha = 0.2
        current_r, current_g, current_b = COLORS.IDLE.r, COLORS.IDLE.g, COLORS.IDLE.b
        anim_timer:stop()
    end

    resetwave:emit_signal("widget::updated")
end)

-- ==========================================
-- SIGNAL LISTENERS
-- ==========================================
awesome.connect_signal("llm::mode", function(mode)
    current_llm_mode = mode
    if mode == "research" then llm_current_color = COLORS.RESEARCH
    elseif mode == "chat" then llm_current_color = COLORS.CHAT
    else llm_current_color = COLORS.WHITE end
end)

awesome.connect_signal("llm::blink", function(color_name)
    local color_map = {
        white = llm_current_color,
        red = COLORS.RED,
        chat = COLORS.CHAT,
        research = COLORS.RESEARCH
    }

    if color_name == "red" then
        current_state = STATE.RED_TRIPLE
        red_triple_start = get_time()
        llm_was_active = false
        current_llm_mode = nil
        llm_current_color = COLORS.WHITE
    else
        single_blink_color = color_map[color_name] or COLORS.WHITE
        single_blink_start = get_time()
        current_state = STATE.SINGLE_BLINK
    end

    if not anim_timer.started then anim_timer:start() end
end)

awesome.connect_signal("llm::ready", function(mode)
    current_llm_mode = mode
    if mode == "research" then llm_current_color = COLORS.RESEARCH
    elseif mode == "chat" then llm_current_color = COLORS.CHAT
    end
    ready_ripple_start = get_time()
    current_state = STATE.READY_RIPPLE
    if not anim_timer.started then anim_timer:start() end
end)

-- Health reminder signals
awesome.connect_signal("health::water", function()
    water_remind_start = get_time()
    current_state = STATE.WATER_REMIND
    if not anim_timer.started then anim_timer:start() end
end)

awesome.connect_signal("health::fitness", function()
    fitness_remind_start = get_time()
    current_state = STATE.FITNESS_REMIND
    if not anim_timer.started then anim_timer:start() end
end)

awesome.connect_signal("health::posture", function()
    posture_remind_start = get_time()
    current_state = STATE.POSTURE_REMIND
    if not anim_timer.started then anim_timer:start() end
end)

function resetwave:pulse()
    blue_pulse_start = get_time()
    current_state = STATE.BLUE_PULSING
    if not anim_timer.started then anim_timer:start() end
end

-- ==========================================
-- LLM POLLER
-- ==========================================
local llm_poll_timer = gears.timer {
    timeout = LLM_POLL_INTERVAL,
    call_now = true,
    callback = function()
        awful.spawn.easy_async(
            string.format("curl -s -o /dev/null -w '%%{http_code}' --max-time 2 http://localhost:%d/health?fail_on_no_slot=1", LLM_PORT),
            function(stdout)
                if not stdout then stdout = "" end
                local clean_stdout = stdout:gsub("%s+", "")
                local status = tonumber(clean_stdout)

                local server_is_running = (status ~= nil and status > 0)
                local server_is_generating = (status == 503)

                if current_state == STATE.BLUE_PULSING then
                    llm_was_active = server_is_generating
                    return
                end

                if server_is_generating and not llm_was_active then
                    if current_llm_mode == "research" then
                        current_state = STATE.RESEARCH_GENERATING
                        llm_current_color = COLORS.RESEARCH
                    else
                        current_state = STATE.CHAT_GENERATING
                        llm_current_color = COLORS.CHAT
                    end
                    if not anim_timer.started then anim_timer:start() end

                elseif not server_is_generating and llm_was_active then
                    if server_is_running then
                        current_state = STATE.DONE_FLASH
                        done_flash_start = get_time()
                        if not anim_timer.started then anim_timer:start() end
                    else
                        current_llm_mode = nil
                        llm_current_color = COLORS.WHITE
                        current_state = STATE.IDLE
                        current_alpha = 0.2
                        current_r, current_g, current_b = COLORS.IDLE.r, COLORS.IDLE.g, COLORS.IDLE.b
                        resetwave:emit_signal("widget::updated")
                    end
                end

                llm_was_active = server_is_generating
            end
        )
    end,
}

-- ==========================================
-- HEALTH REMINDER TIMERS
-- ==========================================
local function rand_interval(min_s, max_s)
    return min_s + math.random() * (max_s - min_s)
end

local function schedule_water()
    if not (user_likes and user_likes.health and user_likes.health.water == false) then
        local delay = rand_interval(HEALTH_WATER_MIN, HEALTH_WATER_MAX)
        gears.timer.start_new(delay, function()
            awesome.emit_signal("health::water")
            schedule_water()
        end)
    end
end

local function schedule_posture()
    if not (user_likes and user_likes.health and user_likes.health.posture == false) then
        local delay = rand_interval(HEALTH_POSTURE_MIN, HEALTH_POSTURE_MAX)
        gears.timer.start_new(delay, function()
            awesome.emit_signal("health::posture")
            schedule_posture()
        end)
    end
end

local function schedule_fitness()
    if not (user_likes and user_likes.health and user_likes.health.g2g == false) then
        gears.timer.start_new(HEALTH_G2G_INTERVAL, function()
            awesome.emit_signal("health::fitness")
            schedule_fitness()
        end)
    end
end

-- ==========================================
-- LIFECYCLE & TIMERS
-- ==========================================
local main_timer = gears.timer {
    timeout = PULSE_INTERVAL,
    call_now = false,
    callback = function() resetwave:pulse() end,
}

math.randomseed(os.time())
main_timer:start()
llm_poll_timer:start()

-- Start health reminder timers
schedule_water()
schedule_posture()
schedule_fitness()

awesome.connect_signal("exit", function()
    anim_timer:stop()
    llm_poll_timer:stop()
    main_timer:stop()
end)

return resetwave
