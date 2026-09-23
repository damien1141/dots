-- Fingerprint Authentication Module
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Uses fprintd to authenticate fingerprints asynchronously
local awful = require("awful")
local gears = require("gears")
local fprint = {}
local listener_timer = nil
local is_active = false

-- Start listening for fingerprint sensor activity asynchronously
fprint.start_listener = function(on_success, on_fail)
    is_active = true
    -- Clear any existing timer to prevent overlapping processes
    if listener_timer then
        listener_timer:stop()
        listener_timer = nil
    end

    local function try_verify()
        if not is_active then return end
        
        -- FIX: Use fprintd-verify (modern standard) instead of legacy fprint-verify
        awful.spawn.easy_async("fprintd-verify", function(stdout, stderr, reason, exit_code)
            if not is_active then return end
            
            if exit_code == 0 then
                -- Verification successful
                if on_success then on_success() end
            else
                -- Verification failed or timed out
                if on_fail then on_fail() end
                
                -- Retry after a short delay to prevent CPU spinning
                if is_active then
                    listener_timer = gears.timer {
                        timeout = 1.5,
                        autostart = true,
                        single_shot = true,
                        callback = try_verify
                    }
                end
            end
        end)
    end

    try_verify()
end

-- Stop the fingerprint listener (call this when unlocking)
fprint.stop_listener = function()
    is_active = false
    if listener_timer then
        listener_timer:stop()
        listener_timer = nil
    end
    -- FIX: Use pkill -x to match the EXACT process name to avoid killing random stuff
    awful.spawn.with_shell("pkill -x fprintd-verify")
end

-- Check if fingerprint is enrolled
fprint.is_enrolled = function()
    -- Note: Because async checks are tricky for immediate UI, we assume enrolled
    -- if the module is loaded. Replace with cached state if needed.
    return true
end

-- Register fingerprint
fprint.enroll = function()
    awful.spawn("fprintd-enroll")
end

return fprint