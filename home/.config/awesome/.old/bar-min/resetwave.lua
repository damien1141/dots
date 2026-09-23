-- resetwave.lua
-- Ambient 2px bar widget for hydration reminders and LLM status/feedback
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
local LINE_HEIGHT = 2
local LLM_POLL_INTERVAL = 5
local LLM_PORT = (user_likes and user_likes.llm_port) or 5001

-- Simplified, Brighter Colors
local COLORS = {
    IDLE       = { r = 30/255, g = 58/255, b = 138/255 }, -- Dim Blue
    DONE       = { r = 66/255, g = 220/255, b = 120/255 }, -- Bright Green
    CHAT       = { r = 152/255, g = 240/255, b = 200/255 }, -- Mint Green
    RESEARCH   = { r = 180/255, g = 140/255, b = 255/255 }, -- Bright Purple
    WHITE      = { r = 255/255, g = 255/255, b = 255/255 },
    RED        = { r = 255/255, g = 80/255,  b = 80/255  },
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
    READY_RIPPLE = 7
}

-- State Variables
local current_state = STATE.IDLE
local current_r, current_g, current_b = COLORS.IDLE.r, COLORS.IDLE.g, COLORS.IDLE.b
local current_alpha = 0.2

local llm_was_active = false
local current_llm_mode = nil 
local llm_current_color = COLORS.WHITE -- Central color state

local blue_pulse_start = 0
local done_flash_start = 0
local single_blink_start = 0
local single_blink_color = COLORS.WHITE
local red_triple_start = 0
local ready_ripple_start = 0

local resetwave = wibox.widget.base.make_widget()

local function get_time()
    return GLib.get_monotonic_time() / 1000000
end

function resetwave:fit(context, width, height)
    return width, LINE_HEIGHT
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
        -- TRAVELING SCANNER GLOW
        local c = (current_state == STATE.RESEARCH_GENERATING) and COLORS.RESEARCH or COLORS.CHAT
        local t = get_time()
        
        -- Brighter background fill
        cr:set_source_rgba(c.r, c.g, c.b, 0.35)
        cr:rectangle(0, 0, width, height)
        cr:fill()
        
        -- Wider scanner with broad bright peak
        local speed = 350
        local glow_width = width * 0.6
        local pos = (t * speed) % (width + glow_width * 2) - glow_width
        
        local pat = cairo.Pattern.create_linear(pos, 0, pos + glow_width, 0)
        pat:add_color_stop_rgba(0.0, c.r, c.g, c.b, 0.0)
        pat:add_color_stop_rgba(0.3, c.r, c.g, c.b, 0.8)
        pat:add_color_stop_rgba(0.5, c.r, c.g, c.b, 1.0)
        pat:add_color_stop_rgba(0.7, c.r, c.g, c.b, 0.8)
        pat:add_color_stop_rgba(1.0, c.r, c.g, c.b, 0.0)
        
        cr:set_source(pat)
        cr:rectangle(0, 0, width, height)
        cr:fill()

    elseif current_state == STATE.READY_RIPPLE then
        -- EXPANDING RIPPLE (Uses central LLM color state)
        local t = get_time()
        local elapsed = t - ready_ripple_start
        local duration = 1.0
        local progress = math.min(elapsed / duration, 1.0)
        
        local c = llm_current_color 
        
        local center = width / 2
        local expand = progress * width 
        local alpha = 1.0 - progress 
        
        if expand > 1 then
            local pat = cairo.Pattern.create_linear(center - expand, 0, center + expand, 0)
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
        -- COMET SWEEP FLASH
        local t = get_time()
        local elapsed = t - done_flash_start
        local duration = 0.8
        local progress = elapsed / duration
        
        if progress < 1.0 then
            local c = COLORS.DONE
            local bg_alpha = (1.0 - progress) * 0.6
            
            -- Fading background
            cr:set_source_rgba(c.r, c.g, c.b, bg_alpha)
            cr:rectangle(0, 0, width, height)
            cr:fill()
            
            -- Sweeping bright comet
            local sweep_width = width * 1.2 
            local sweep_pos = progress * (width + sweep_width) - (sweep_width / 2)
            
            local pat = cairo.Pattern.create_linear(sweep_pos, 0, sweep_pos + sweep_width, 0)
            pat:add_color_stop_rgba(0.0, c.r, c.g, c.b, 0.0)
            pat:add_color_stop_rgba(0.5, c.r, c.g, c.b, 1.0 - (progress * 0.5))
            pat:add_color_stop_rgba(1.0, c.r, c.g, c.b, 0.0)
            
            cr:set_source(pat)
            cr:rectangle(0, 0, width, height)
            cr:fill()
        end

    else
        -- Fallback for solid colors (IDLE, PULSING, BLINKS)
        local pat = cairo.Pattern.create_linear(0, 0, width, 0)
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
            -- Check pulse uses central LLM color state
            current_r, current_g, current_b = llm_current_color.r, llm_current_color.g, llm_current_color.b
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
            current_alpha = 0.2 + (math.sin(progress * math.pi) * 0.8) 
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
        white = llm_current_color, -- Uses central state
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
                        -- Server died, clear central color state to white
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
-- LIFECYCLE & TIMERS
-- ==========================================
local main_timer = gears.timer {
    timeout = PULSE_INTERVAL,
    call_now = false,
    callback = function() resetwave:pulse() end,
}

main_timer:start()
llm_poll_timer:start()

awesome.connect_signal("exit", function()
    anim_timer:stop()
    llm_poll_timer:stop()
    main_timer:stop()
end)

return resetwave