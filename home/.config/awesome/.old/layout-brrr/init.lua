-- accordion-brrr.lua
-- Hybrid Spatial: 2 Windows = 55/45 Accordion. 3+ Windows = Spatial Grid.
-- Powered by a Fixed-Step, Critically-Damped Spring Engine (Optimized).

local awful = require("awful")
local gears = require("gears")
local beautiful = require("beautiful")
local math = math
local capi = { client = client }

-- Localize math functions for maximum loop performance
local floor, max, abs, ceil = math.floor, math.max, math.abs, math.ceil

-- ==========================================
-- 1. PHYSICS ENGINE CONFIGURATION
-- ==========================================
local layout = { name = "accordion-brrr" }
local gap_size = 7

-- Spring Physics
local stiffness = 350.0
local damping = 38.0
local precision = 1.5
local max_fps = 60
local fixed_dt = 1 / max_fps

-- ==========================================
-- 2. THE OPTIMIZED SPRING ANIMATION ENGINE
-- ==========================================
local anim_timer = nil
local animating_clients = {}

-- Pre-allocate a single geometry table to prevent Garbage Collection (GC) spikes
local geo_update = {}

local function update_momentum(cur, vel, new_target)
    if (new_target - cur) * vel < 0 then
        return vel * 0.2
    end
    return vel
end

local function animate()
    local still_animating = false

    for c, data in pairs(animating_clients) do
        local valid = c.valid
        local visible = false
        if valid ~= false then
            visible = c:isvisible()
        end
        
        if valid == false or not visible then
            animating_clients[c] = nil
        else
            local force_x = -stiffness * (data.cur_x - data.target_x) - damping * data.vel_x
            local force_y = -stiffness * (data.cur_y - data.target_y) - damping * data.vel_y
            local force_w = -stiffness * (data.cur_w - data.target_w) - damping * data.vel_w
            local force_h = -stiffness * (data.cur_h - data.target_h) - damping * data.vel_h

            data.vel_x = data.vel_x + force_x * fixed_dt
            data.vel_y = data.vel_y + force_y * fixed_dt
            data.vel_w = data.vel_w + force_w * fixed_dt
            data.vel_h = data.vel_h + force_h * fixed_dt

            if data.vel_x > 4000 then data.vel_x = 4000 elseif data.vel_x < -4000 then data.vel_x = -4000 end
            if data.vel_y > 4000 then data.vel_y = 4000 elseif data.vel_y < -4000 then data.vel_y = -4000 end
            if data.vel_w > 4000 then data.vel_w = 4000 elseif data.vel_w < -4000 then data.vel_w = -4000 end
            if data.vel_h > 4000 then data.vel_h = 4000 elseif data.vel_h < -4000 then data.vel_h = -4000 end

            data.cur_x = data.cur_x + data.vel_x * fixed_dt
            data.cur_y = data.cur_y + data.vel_y * fixed_dt
            data.cur_w = data.cur_w + data.vel_w * fixed_dt
            data.cur_h = data.cur_h + data.vel_h * fixed_dt

            local settled = abs(data.cur_x - data.target_x) < precision and
                            abs(data.cur_y - data.target_y) < precision and
                            abs(data.cur_w - data.target_w) < precision and
                            abs(data.cur_h - data.target_h) < precision and
                            abs(data.vel_x) < precision and
                            abs(data.vel_y) < precision and
                            abs(data.vel_w) < precision and
                            abs(data.vel_h) < precision

            local bw = c.border_width or beautiful.border_width or 0

            geo_update.x = floor(data.cur_x + bw + 0.5)
            geo_update.y = floor(data.cur_y + bw + 0.5)
            geo_update.width = max(1, floor(data.cur_w - (bw * 2) + 0.5))
            geo_update.height = max(1, floor(data.cur_h - (bw * 2) + 0.5))

            if settled then
                geo_update.x = floor(data.target_x + bw + 0.5)
                geo_update.y = floor(data.target_y + bw + 0.5)
                geo_update.width = max(1, floor(data.target_w - (bw * 2) + 0.5))
                geo_update.height = max(1, floor(data.target_h - (bw * 2) + 0.5))

                if data.last_x ~= geo_update.x or data.last_y ~= geo_update.y or
                   data.last_w ~= geo_update.width or data.last_h ~= geo_update.height then
                    c:geometry(geo_update)
                    data.last_x = geo_update.x
                    data.last_y = geo_update.y
                    data.last_w = geo_update.width
                    data.last_h = geo_update.height
                end
                animating_clients[c] = nil
            else
                if data.last_x ~= geo_update.x or data.last_y ~= geo_update.y or
                   data.last_w ~= geo_update.width or data.last_h ~= geo_update.height then
                    c:geometry(geo_update)
                    data.last_x = geo_update.x
                    data.last_y = geo_update.y
                    data.last_w = geo_update.width
                    data.last_h = geo_update.height
                end
                still_animating = true
            end
        end
    end

    if not still_animating and anim_timer then
        anim_timer:stop()
    end
end

local function set_target(c, x, y, w, h)
    if c.valid == false then return end

    if animating_clients[c] then
        local data = animating_clients[c]

        if abs(data.target_x - x) < 2 and abs(data.target_y - y) < 2 and
           abs(data.target_w - w) < 2 and abs(data.target_h - h) < 2 then
            return
        end

        data.vel_x = update_momentum(data.cur_x, data.vel_x, x)
        data.vel_y = update_momentum(data.cur_y, data.vel_y, y)
        data.vel_w = update_momentum(data.cur_w, data.vel_w, w)
        data.vel_h = update_momentum(data.cur_h, data.vel_h, h)

        data.target_x = x
        data.target_y = y
        data.target_w = w
        data.target_h = h
    else
        local current_geo = c:geometry()
        local bw = c.border_width or beautiful.border_width or 0

        local cur_x = current_geo.x - bw
        local cur_y = current_geo.y - bw
        local cur_w = current_geo.width + (bw * 2)
        local cur_h = current_geo.height + (bw * 2)

        if abs(cur_x - x) < 2 and abs(cur_y - y) < 2 and
           abs(cur_w - w) < 2 and abs(cur_h - h) < 2 then
            geo_update.x = floor(x + bw + 0.5)
            geo_update.y = floor(y + bw + 0.5)
            geo_update.width = max(1, floor(w - (bw * 2) + 0.5))
            geo_update.height = max(1, floor(h - (bw * 2) + 0.5))
            c:geometry(geo_update)
            return
        end

        animating_clients[c] = {
            cur_x = cur_x, cur_y = cur_y, cur_w = cur_w, cur_h = cur_h,
            vel_x = 0, vel_y = 0, vel_w = 0, vel_h = 0,
            target_x = x, target_y = y, target_w = w, target_h = h,
            last_x = 0, last_y = 0, last_w = 0, last_h = 0
        }

        if not anim_timer then
            anim_timer = gears.timer {
                timeout = fixed_dt,
                call_now = false,
                autostart = true,
                callback = animate
            }
        elseif not anim_timer.started then
            anim_timer:start()
        end
    end
end

-- ==========================================
-- 3. THE HYBRID LAYOUT ENGINE
-- ==========================================
function layout.arrange(p)
    local clients = {}
    for _, c in ipairs(p.clients) do
        if c.type == "normal" and not c.floating and not c.maximized
           and not c.maximized_horizontal and not c.maximized_vertical
           and not c.fullscreen and not c.minimized and not c.transient_for then
            table.insert(clients, c)
        end
    end
    
    if #clients == 0 then return end

    -- Direct screen object comparison (prevents multi-monitor teleportation)
    for _, c in ipairs(clients) do
        if c.brrr_last_screen ~= p.screen then
            c.brrr_last_x = nil
            c.brrr_last_y = nil
            c.brrr_last_screen = p.screen
        end
    end

    local workarea = p.workarea
    local gap = p.useless_gap or gap_size

    -- FIX: Bulletproof focus detection. No fragile screen object comparisons.
    -- We simply check if the globally focused window is actually in the tiled clients list.
    local focused = capi.client.focus
    local is_in_layout = false
    if focused and focused.valid ~= false and focused:isvisible() 
       and focused.type == "normal" and not focused.floating 
       and not focused.maximized and not focused.maximized_horizontal 
       and not focused.maximized_vertical and not focused.fullscreen 
       and not focused.minimized and not focused.transient_for then
        for _, c in ipairs(clients) do
            if c == focused then
                is_in_layout = true
                break
            end
        end
    end
    
    if not is_in_layout then
        focused = clients[1]
    end

    local num_clients = #clients
    local col_threshold = workarea.width * 0.15

    -- STATE 1: 1 Window
    if num_clients == 1 then
        local tx = workarea.x + gap
        local ty = workarea.y + gap
        local tw = workarea.width - (gap * 2)
        local th = workarea.height - (gap * 2)

        focused.brrr_last_x = tx
        focused.brrr_last_y = ty
        set_target(focused, tx, ty, tw, th)
        return
    end

    -- STATE 2: 2 Windows
    if num_clients == 2 then
        table.sort(clients, function(a, b)
            local ax = a.brrr_last_x or a.x
            local bx = b.brrr_last_x or b.x
            return ax < bx
        end)

        local focus_factor = 0.55
        local focused_w = floor(workarea.width * focus_factor)
        local unfocused_w = workarea.width - focused_w
        local current_x = workarea.x

        for _, c in ipairs(clients) do
            local w = (c == focused) and focused_w or unfocused_w

            local tx = current_x + gap
            local ty = workarea.y + gap
            local tw = w - (gap * 2)
            local th = workarea.height - (gap * 2)

            c.brrr_last_x = tx
            c.brrr_last_y = ty
            set_target(c, tx, ty, tw, th)
            current_x = current_x + w
        end
        return
    end

    -- STATE 3: 3+ Windows
    table.sort(clients, function(a, b)
        local ax = a.brrr_last_x or a.x
        local ay = a.brrr_last_y or a.y
        local bx = b.brrr_last_x or b.x
        local by = b.brrr_last_y or b.y

        if abs(ax - bx) < col_threshold then return ay < by end
        return ax < bx
    end)

    local num_cols = ceil(num_clients / 2)
    local base_count = floor(num_clients / num_cols)
    local remainder = num_clients % num_cols

    local columns = {}
    local client_idx = 1
    for c = 1, num_cols do
        local count = base_count + (c <= remainder and 1 or 0)
        columns[c] = {}
        for _ = 1, count do
            table.insert(columns[c], clients[client_idx])
            client_idx = client_idx + 1
        end
    end

    local focused_col = 1
    for i, col in ipairs(columns) do
        for _, c in ipairs(col) do
            if c == focused then focused_col = i end
        end
    end

    local focus_factor = (num_clients <= 4) and 0.55 or 0.50
    local focused_w = floor(workarea.width * focus_factor)
    local unfocused_w_total = workarea.width - focused_w
    local unfocused_w = floor(unfocused_w_total / (num_cols - 1))

    local col_widths = {}
    for i = 1, num_cols do
        col_widths[i] = (i == focused_col) and focused_w or unfocused_w
    end

    local current_x = workarea.x
    for i, col in ipairs(columns) do
        local col_w = col_widths[i]
        if i == num_cols then
            col_w = workarea.x + workarea.width - current_x
        end

        local num_in_col = #col
        local row_h = floor(workarea.height / num_in_col)
        local current_y = workarea.y

        for j, c in ipairs(col) do
            local h = row_h
            if j == num_in_col then
                h = workarea.y + workarea.height - current_y
            end

            local tx = current_x + gap
            local ty = current_y + gap
            local tw = col_w - (gap * 2)
            local th = h - (gap * 2)

            c.brrr_last_x = tx
            c.brrr_last_y = ty
            set_target(c, tx, ty, tw, th)

            current_y = current_y + h
        end
        current_x = current_x + col_w
    end
end

layout.resize_handler = function(c, context, h) end

-- ==========================================
-- 4. STATE MANAGEMENT SIGNALS
-- ==========================================

capi.client.connect_signal("unmanage", function(c)
    animating_clients[c] = nil
end)

-- Trigger rearrange when a window gains focus
capi.client.connect_signal("focus", function(c)
    if c.screen then
        awful.layout.arrange(c.screen)
    end
end)

-- Trigger rearrange when a window loses focus (crucial for multi-monitor)
capi.client.connect_signal("unfocus", function(c)
    if c.screen then
        awful.layout.arrange(c.screen)
    end
end)

capi.client.connect_signal("property::fullscreen", function(c)
    if c.valid == false then return end
    if c.fullscreen then
        animating_clients[c] = nil
    else
        if c.screen then awful.layout.arrange(c.screen) end
    end
end)

capi.client.connect_signal("property::maximized", function(c)
    if c.valid == false then return end
    if c.maximized or c.maximized_horizontal or c.maximized_vertical then
        animating_clients[c] = nil
    else
        if c.screen then awful.layout.arrange(c.screen) end
    end
end)

return layout