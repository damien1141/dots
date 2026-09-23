-- awesome/mods/layout-brrr/init.lua
-- v11.0 = profile-aware smoothness build:
-- - reads your tlp-pd state file: misc/.information/power_profile_state
-- - low/balanced -> 49hz hint, performance -> 91hz hint
-- - re-detects xrandr after profile changes
-- - per-screen refresh matching when possible
-- - exact-refresh-first cadence selection
-- - real frame timing + coalesced first frame

local awful = require("awful")
local gears = require("gears")
local beautiful = require("beautiful")
local capi = { client = client, screen = screen }

local floor, max, min, abs, ceil, sqrt =
    math.floor, math.max, math.min, math.abs, math.ceil, math.sqrt

local mono_us = nil
do
    local ok, GLib = pcall(function()
        return require("lgi").require("GLib")
    end)

    if ok and GLib and GLib.get_monotonic_time then
        mono_us = function()
            return GLib.get_monotonic_time()
        end
    end
end

-- ==========================================
-- CONFIG
-- ==========================================
local layout = { name = "accordion-brrr" }
local gap_size = 3

layout.animations_on = true
layout.animate_resizing = false
layout.animate_first_placement = false
layout.debug = true

layout.high_fps = 91
layout.fallback_fps = 60

layout.refresh_lock = true
layout.refresh_policy = "min"
layout.start_ceiling = 240

layout.auto_downshift = true
layout.late_downshift = true
layout.auto_upshift = true

layout.force_fps = nil

layout.eco = "auto"
layout.eco_fraction = 0.85
layout.eco_k_mult = 0.90

layout.size_quantum = 1
layout.eco_size_quantum = 1
layout.settle_velocity = 12.0

layout.surrender_on_starve = false
layout.surrender_seconds = 12

-- your tlp-pd profile hints
layout.profile_refresh_performance = 91
layout.profile_refresh_low = 49
layout.profile_poll_seconds = 1.0

local function dbg(...)
    if layout.debug then
        print("[accordion-brrr]", ...)
    end
end

local function clamp_fps(v)
    v = tonumber(v)
    if not v then return 60 end

    v = floor(v + 0.5)

    if v < 30 then return 30 end
    if v > 240 then return 240 end

    return v
end

local function clamp_num(v, lo, hi)
    v = tonumber(v)
    if not v then return lo end
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- ==========================================
-- SPRING PROFILE
-- ==========================================
local stiffness = 350.0
local damping = 2.0 * sqrt(stiffness) * 1.03
local precision = 1.5
local max_velocity = 8000.0

local focus_factor_small = 0.55
local focus_factor_large = 0.50
local factor_min, factor_max = 0.25, 0.75

local function stability_floor_for(k, c)
    local stable = 0.9 * (sqrt(c * c + 4 * k) - c) / k
    local fps = ceil(1 / stable)

    if fps < 30 then fps = 30 end
    if fps > 240 then fps = 240 end

    return fps
end

local base_stability_floor = stability_floor_for(stiffness, damping)
local hard_min_fps = max(30, base_stability_floor)

local active_eco = false
local active_stiffness = stiffness
local active_damping = damping
local active_stability_floor = base_stability_floor

layout.high_fps = clamp_fps(layout.high_fps)
layout.fallback_fps = clamp_fps(layout.fallback_fps)

if layout.high_fps < hard_min_fps then
    layout.high_fps = hard_min_fps
end

if layout.fallback_fps < hard_min_fps then
    layout.fallback_fps = hard_min_fps
end

if layout.fallback_fps > layout.high_fps then
    layout.fallback_fps = layout.high_fps
end

-- ==========================================
-- PROFILE STATE (tlp-pd)
-- ==========================================
local profile_state_path =
    gears.filesystem.get_configuration_dir() .. "misc/.information/power_profile_state"

local profile_cache = nil
local profile_cache_at = -math.huge

local function read_profile_state(force)
    local now = mono_us and (mono_us() / 1e6) or os.time()

    if not force
       and profile_cache ~= nil
       and now - profile_cache_at < 1.0 then
        return profile_cache
    end

    local f = io.open(profile_state_path, "r")
    if not f then
        profile_cache = nil
        profile_cache_at = now
        return nil
    end

    local line = f:read("*l")
    f:close()

    local profile = line and line:match("^([^:]+)") or nil

    if profile then
        profile = profile:match("^%s*(.-)%s*$")
        profile = profile:lower()
    end

    if profile == "" then
        profile = nil
    end

    profile_cache = profile
    profile_cache_at = now

    return profile
end

local function profile_refresh_for(profile)
    if profile == "performance" then
        return clamp_fps(layout.profile_refresh_performance)
    elseif profile == "balanced" or profile == "power-saver" then
        return clamp_fps(layout.profile_refresh_low)
    end

    return nil
end

local initial_profile = read_profile_state(true)
local profile_refresh_hint = profile_refresh_for(initial_profile)
local profile_override_active = profile_refresh_hint ~= nil

-- ==========================================
-- REFRESH STATE
-- ==========================================
local refresh_hz = profile_refresh_hint
local detected_refresh = profile_refresh_hint

local refresh_by_name = {}
local refresh_by_geo = {}

-- ==========================================
-- ECO DETECTION
-- ==========================================
local function read_first_line(path)
    local ok, f = pcall(io.open, path, "r")
    if not ok or not f then return nil end

    local ok2, line = pcall(function()
        return f:read("*l")
    end)

    pcall(function()
        f:close()
    end)

    if ok2 then return line end
    return nil
end

local eco_cache = nil
local eco_cache_at = -math.huge

local function sys_eco_wanted()
    local now = mono_us and (mono_us() / 1e6) or os.time()

    if eco_cache ~= nil and now - eco_cache_at < 5 then
        return eco_cache
    end

    local wants = false

    local epp_paths = {
        "/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference",
        "/sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference",
    }

    for _, p in ipairs(epp_paths) do
        local line = read_first_line(p)
        if line then
            line = line:lower()
            if line:find("power", 1, true) then
                wants = true
                break
            end
        end
    end

    if not wants then
        local gov_paths = {
            "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor",
            "/sys/devices/system/cpu/cpufreq/policy0/scaling_governor",
        }

        for _, p in ipairs(gov_paths) do
            local line = read_first_line(p)
            if line then
                line = line:lower()
                if line:find("powersave", 1, true)
                   or line:find("conservative", 1, true) then
                    wants = true
                    break
                end
            end
        end
    end

    eco_cache = wants
    eco_cache_at = now

    return wants
end

local function eco_wanted()
    local v = layout.eco

    if v == true or v == "on" or v == "true" then
        return true
    end

    if v == false or v == "off" or v == "false" then
        return false
    end

    local prof = read_profile_state(false)

    if prof == "performance" then
        return false
    end

    if prof == "balanced" or prof == "power-saver" then
        return true
    end

    return sys_eco_wanted()
end

local function apply_active_profile(eco)
    active_eco = eco and true or false

    local mult = 1.0
    if active_eco then
        mult = clamp_num(layout.eco_k_mult, 0.25, 4.0)
    end

    active_stiffness = stiffness * mult
    active_damping = 2.0 * sqrt(active_stiffness) * 1.03
    active_stability_floor = stability_floor_for(active_stiffness, active_damping)

    if active_stability_floor < hard_min_fps then
        active_stability_floor = hard_min_fps
    end

    dbg("profile ->", active_eco and "eco" or "performance",
        string.format("k=%.1f floor=%dfps", active_stiffness, active_stability_floor))
end

apply_active_profile(eco_wanted())

-- ==========================================
-- ENGINE STATE
-- ==========================================
local anim_timer = nil
local animating_clients = {}
local geo_update = {}

local frame_requested = false
local last_frame_us = nil

local missed_streak = 0
local good_streak = 0
local slow_streak = 0
local tick_dbg_count = 0

local last_fps_change_s = 0
local surrender_until_s = 0

local current_fps
local fixed_dt
local target_fps
local cadence_tiers = {}

-- forward declarations
local animate
local schedule_frame
local ensure_timer
local update_fps
local cold_start
local rebuild_timer
local stop_timer
local snap_all_to_targets
local clear_animation
local kick_animation
local monitor_tick
local maybe_retune_for_screen

-- ==========================================
-- CADENCE / REFRESH LOGIC
-- ==========================================
local function divisors_under(refresh, limit)
    refresh = floor(refresh + 0.5)
    limit = floor(limit + 0.5)

    local best = nil
    local root = floor(sqrt(refresh))

    for d = 1, root do
        if refresh % d == 0 then
            local q = refresh / d

            if d >= hard_min_fps and d <= limit then
                if not best or d > best then
                    best = d
                end
            end

            if q >= hard_min_fps and q <= limit then
                if not best or q > best then
                    best = q
                end
            end
        end
    end

    return best
end

local function choose_refresh_fps(refresh, cap, high)
    if not refresh then
        return min(high, cap)
    end

    refresh = clamp_fps(refresh)
    cap = clamp_fps(cap)
    high = clamp_fps(high)

    local limit = min(cap, high)

    if refresh <= limit then
        return refresh
    end

    local div = divisors_under(refresh, limit)
    if div then
        return div
    end

    -- prime-ish panels: exact refresh usually beats a non-divisor cap
    if refresh <= high and refresh <= 120 then
        return refresh
    end

    return limit
end

local function refresh_for_screen(s)
    if profile_override_active and profile_refresh_hint then
        return profile_refresh_hint
    end

    if s then
        local outputs = s.outputs or {}

        if type(outputs) == "table" then
            for k, v in pairs(outputs) do
                local name = nil

                if type(k) == "string" then
                    name = k
                end

                if type(v) == "string" then
                    name = v
                elseif type(v) == "table" and v.name then
                    name = v.name
                end

                if name and refresh_by_name[name] then
                    return refresh_by_name[name]
                end
            end
        end

        if s.geometry then
            local key = string.format(
                "%dx%d+%d+%d",
                s.geometry.width or 0,
                s.geometry.height or 0,
                s.geometry.x or 0,
                s.geometry.y or 0
            )

            if refresh_by_geo[key] then
                return refresh_by_geo[key]
            end
        end
    end

    return detected_refresh
end

local function compute_target_from_refresh(r)
    if layout.force_fps then
        return clamp_fps(layout.force_fps)
    end

    local high = clamp_fps(layout.high_fps)
    local cap = clamp_fps(layout.start_ceiling)

    local normal

    if r then
        normal = choose_refresh_fps(r, cap, high)
    else
        normal = min(high, cap)
    end

    normal = max(normal, active_stability_floor, hard_min_fps)

    if active_eco and normal > 60 then
        local frac = clamp_num(layout.eco_fraction, 0.25, 1.0)
        local eco_cap = floor(normal * frac + 0.5)

        if r then
            local eco_fps = choose_refresh_fps(r, eco_cap, high)
            return max(eco_fps, active_stability_floor, hard_min_fps)
        end

        return max(eco_cap, active_stability_floor, hard_min_fps)
    end

    return normal
end

local function desired_fps_for_screen(s)
    local r = refresh_for_screen(s)
    return compute_target_from_refresh(r)
end

local function build_tiers(base)
    base = clamp_fps(base)

    if base < active_stability_floor then
        base = active_stability_floor
    end

    local seen = {}
    local tiers = {}

    local function add(f)
        f = clamp_fps(f)

        if f < active_stability_floor then
            f = active_stability_floor
        end

        if f > base then
            f = base
        end

        if not seen[f] then
            seen[f] = true
            tiers[#tiers + 1] = f
        end
    end

    add(base)
    add(floor(base * 0.85 + 0.5))
    add(floor(base * 0.75 + 0.5))
    add(floor(base * 0.66 + 0.5))
    add(floor(base * 0.50 + 0.5))

    local fb = clamp_fps(layout.fallback_fps)
    if fb <= base and fb >= active_stability_floor then
        add(fb)
    end

    add(active_stability_floor)

    table.sort(tiers, function(a, b)
        return a > b
    end)

    return tiers
end

local function tier_below(fps)
    local best = nil

    for _, t in ipairs(cadence_tiers) do
        if t < fps and t >= active_stability_floor then
            if not best or t > best then
                best = t
            end
        end
    end

    return best
end

local function tier_above(fps)
    local best = nil

    for _, t in ipairs(cadence_tiers) do
        if t > fps and t <= target_fps then
            if not best or t < best then
                best = t
            end
        end
    end

    return best
end

target_fps = desired_fps_for_screen(nil)
cadence_tiers = build_tiers(target_fps)
current_fps = target_fps
fixed_dt = 1 / current_fps

-- ==========================================
-- HELPERS
-- ==========================================
local function delay_call(f)
    if gears.timer.delayed_call then
        gears.timer.delayed_call(f)
    else
        gears.timer.start_new(0, function()
            f()
            return false
        end)
    end
end

schedule_frame = function()
    if frame_requested then return end

    frame_requested = true

    delay_call(function()
        frame_requested = false

        if layout.animations_on and next(animating_clients) ~= nil then
            animate()
        end
    end)
end

local function surrendered()
    if not layout.surrender_on_starve then return false end
    if not mono_us then return false end

    return (mono_us() / 1e6) < surrender_until_s
end

stop_timer = function()
    if anim_timer then
        anim_timer:stop()
    end

    last_frame_us = nil
    missed_streak = 0
    good_streak = 0
    slow_streak = 0
end

rebuild_timer = function(dt)
    local should_run =
        (anim_timer and anim_timer.started)
        or (next(animating_clients) ~= nil)

    if anim_timer then
        anim_timer:stop()
    end

    anim_timer = gears.timer {
        timeout = dt,
        call_now = false,
        autostart = false,
        callback = function()
            if animate then
                animate()
            end
        end,
    }

    if should_run then
        if mono_us then
            last_frame_us = mono_us() - floor(dt * 1e6)
        end

        anim_timer:start()
    end
end

update_fps = function(fps)
    fps = clamp_fps(fps)

    if fps < active_stability_floor then
        fps = active_stability_floor
    end

    if layout.force_fps then
        fps = clamp_fps(layout.force_fps)
    end

    if fps == current_fps then return end

    current_fps = fps
    fixed_dt = 1 / current_fps

    missed_streak = 0
    good_streak = 0
    slow_streak = 0

    if mono_us then
        last_fps_change_s = mono_us() / 1e6
    end

    if anim_timer then
        rebuild_timer(fixed_dt)
    end

    dbg("fps ->", current_fps)
end

monitor_tick = function(actual_dt)
    if not mono_us then return end
    if not actual_dt or actual_dt <= 0 then return end

    if actual_dt > 0.25 then
        missed_streak = 0
        good_streak = 0
        slow_streak = 0
        return
    end

    local expected = 1 / current_fps
    local now_s = mono_us() / 1e6

    if actual_dt > expected * 1.45 then
        missed_streak = missed_streak + 1
        good_streak = 0
    elseif actual_dt < expected * 1.18 then
        good_streak = good_streak + 1
        missed_streak = 0
    else
        missed_streak = 0
        good_streak = 0
    end

    if actual_dt > expected * 1.28 then
        slow_streak = slow_streak + 1
    else
        slow_streak = 0
    end

    if layout.debug then
        tick_dbg_count = tick_dbg_count + 1
        if tick_dbg_count % 120 == 0 then
            dbg(string.format(
                "cadence target %.0ffps, actual %.1ffps, missed %d, slow %d, good %d",
                current_fps,
                actual_dt > 0 and (1 / actual_dt) or 0,
                missed_streak,
                slow_streak,
                good_streak
            ))
        end
    end

    if layout.force_fps then return end

    if layout.auto_downshift then
        if missed_streak >= 6 and now_s - last_fps_change_s > 0.75 then
            local next_tier = tier_below(current_fps)

            if next_tier then
                missed_streak = 0
                slow_streak = 0
                update_fps(next_tier)
                return
            elseif missed_streak >= 8 and layout.surrender_on_starve then
                missed_streak = 0
                slow_streak = 0

                surrender_until_s = now_s + max(3, tonumber(layout.surrender_seconds) or 12)
                dbg("surrender: bottom tier starving, springs off", layout.surrender_seconds, "s")

                if snap_all_to_targets then
                    snap_all_to_targets()
                end

                return
            end
        end

        if layout.late_downshift
           and slow_streak >= 60
           and now_s - last_fps_change_s > 2.0 then
            local next_tier = tier_below(current_fps)

            if next_tier then
                slow_streak = 0
                missed_streak = 0
                update_fps(next_tier)
                return
            elseif slow_streak >= 120 and layout.surrender_on_starve then
                slow_streak = 0
                missed_streak = 0

                surrender_until_s = now_s + max(3, tonumber(layout.surrender_seconds) or 12)
                dbg("surrender: sustained late ticks, springs off", layout.surrender_seconds, "s")

                if snap_all_to_targets then
                    snap_all_to_targets()
                end

                return
            end
        end
    end

    if layout.auto_upshift
       and current_fps < target_fps
       and good_streak >= 240
       and slow_streak == 0
       and missed_streak == 0
       and now_s - last_fps_change_s > 5.0 then
        local next_tier = tier_above(current_fps)

        if next_tier then
            good_streak = 0
            missed_streak = 0
            update_fps(next_tier)
            return
        end
    end
end

local function compute_geo(x, y, w, h, bw)
    return floor(x + bw + 0.5),
           floor(y + bw + 0.5),
           max(1, floor(w - bw * 2 + 0.5)),
           max(1, floor(h - bw * 2 + 0.5))
end

local function apply_geo(c, x, y, w, h)
    if c.valid == false then return end

    local bw = c.border_width or beautiful.border_width or 0
    local gx, gy, gw, gh = compute_geo(x, y, w, h, bw)

    geo_update.x, geo_update.y, geo_update.width, geo_update.height =
        gx, gy, gw, gh

    c:geometry(geo_update)
end

local function clamp_velocity(v)
    if v > max_velocity then return max_velocity
    elseif v < -max_velocity then return -max_velocity end
    return v
end

local function update_momentum(cur, vel, new_target)
    if (new_target - cur) * vel < 0 then
        return vel * 0.2
    end
    return vel
end

-- ==========================================
-- ANIMATION LOOP
-- ==========================================
animate = function()
    if not layout.animations_on then
        if snap_all_to_targets then
            snap_all_to_targets()
        end
        return
    end

    local now_us = mono_us and mono_us() or nil
    local sim_dt = fixed_dt

    if now_us then
        if last_frame_us then
            local actual = (now_us - last_frame_us) / 1e6

            if actual > 0 then
                monitor_tick(actual)

                if actual <= 0.25 then
                    sim_dt = actual
                end
            end
        end

        last_frame_us = now_us
    end

    if next(animating_clients) == nil then
        stop_timer()
        return
    end

    if sim_dt <= 0 then
        sim_dt = fixed_dt
    end

    if sim_dt < 0.0005 then
        sim_dt = 0.0005
    end

    local max_sim_dt = 1 / max(hard_min_fps, active_stability_floor)
    if sim_dt > max_sim_dt then
        sim_dt = max_sim_dt
    end

    local still_animating = false
    local dead = nil

    local quantum_setting = active_eco and layout.eco_size_quantum or layout.size_quantum
    local quantum = max(1, floor(tonumber(quantum_setting) or 1))
    local settle_vel = max(0, tonumber(layout.settle_velocity) or 12.0)

    for c, data in pairs(animating_clients) do
        if c.valid == false then
            dead = dead or {}
            dead[#dead + 1] = c
        else
            local s = c.screen

            if not s or awful.layout.get(s) ~= layout then
                dead = dead or {}
                dead[#dead + 1] = c

            elseif not c:isvisible() then
                apply_geo(c, data.target_x, data.target_y, data.target_w, data.target_h)

                dead = dead or {}
                dead[#dead + 1] = c

            else
                data.vel_x = clamp_velocity(
                    data.vel_x +
                    (-active_stiffness * (data.cur_x - data.target_x)
                     - active_damping * data.vel_x) * sim_dt
                )

                data.vel_y = clamp_velocity(
                    data.vel_y +
                    (-active_stiffness * (data.cur_y - data.target_y)
                     - active_damping * data.vel_y) * sim_dt
                )

                data.vel_w = clamp_velocity(
                    data.vel_w +
                    (-active_stiffness * (data.cur_w - data.target_w)
                     - active_damping * data.vel_w) * sim_dt
                )

                data.vel_h = clamp_velocity(
                    data.vel_h +
                    (-active_stiffness * (data.cur_h - data.target_h)
                     - active_damping * data.vel_h) * sim_dt
                )

                data.cur_x = data.cur_x + data.vel_x * sim_dt
                data.cur_y = data.cur_y + data.vel_y * sim_dt
                data.cur_w = data.cur_w + data.vel_w * sim_dt
                data.cur_h = data.cur_h + data.vel_h * sim_dt

                local bw = c.border_width or beautiful.border_width or 0

                local gx, gy, gw, gh =
                    compute_geo(data.cur_x, data.cur_y, data.cur_w, data.cur_h, bw)

                local tx, ty, tw, th =
                    compute_geo(data.target_x, data.target_y, data.target_w, data.target_h, bw)

                local near =
                    abs(data.cur_x - data.target_x) < precision and
                    abs(data.cur_y - data.target_y) < precision and
                    abs(data.cur_w - data.target_w) < precision and
                    abs(data.cur_h - data.target_h) < precision

                local int_exact =
                    gx == tx and gy == ty and gw == tw and gh == th

                local slow =
                    abs(data.vel_x) < settle_vel and
                    abs(data.vel_y) < settle_vel and
                    abs(data.vel_w) < settle_vel and
                    abs(data.vel_h) < settle_vel

                local settled = slow and (near or int_exact)

                if settled then
                    apply_geo(c, data.target_x, data.target_y, data.target_w, data.target_h)

                    dead = dead or {}
                    dead[#dead + 1] = c
                else
                    still_animating = true

                    local ax, ay, aw, ah =
                        data.last_x, data.last_y, data.last_w, data.last_h

                    local need_pos = (ax ~= gx) or (ay ~= gy)

                    local need_w = (aw == nil)
                        or (quantum <= 1 and aw ~= gw)
                        or (quantum > 1 and abs(gw - aw) >= quantum)

                    local need_h = (ah == nil)
                        or (quantum <= 1 and ah ~= gh)
                        or (quantum > 1 and abs(gh - ah) >= quantum)

                    if need_pos or need_w or need_h then
                        local out_x = ax or gx
                        local out_y = ay or gy
                        local out_w = aw or gw
                        local out_h = ah or gh

                        if need_pos then
                            out_x = gx
                            out_y = gy
                        end

                        if need_w then
                            out_w = gw
                        end

                        if need_h then
                            out_h = gh
                        end

                        geo_update.x, geo_update.y, geo_update.width, geo_update.height =
                            out_x, out_y, out_w, out_h

                        c:geometry(geo_update)

                        data.last_x, data.last_y = out_x, out_y

                        if need_w then
                            data.last_w = out_w
                        end

                        if need_h then
                            data.last_h = out_h
                        end
                    end
                end
            end
        end
    end

    if dead then
        for _, c in ipairs(dead) do
            animating_clients[c] = nil
        end
    end

    if not still_animating then
        stop_timer()
    end
end

ensure_timer = function()
    if next(animating_clients) == nil then return end

    if not anim_timer then
        anim_timer = gears.timer {
            timeout = fixed_dt,
            call_now = false,
            autostart = false,
            callback = function()
                animate()
            end,
        }
    elseif anim_timer.timeout ~= fixed_dt then
        anim_timer.timeout = fixed_dt
    end

    if not anim_timer.started then
        if mono_us then
            last_frame_us = mono_us() - floor(fixed_dt * 1e6)
        end

        anim_timer:start()
        schedule_frame()
    end
end

cold_start = function(s)
    if layout.force_fps then
        target_fps = clamp_fps(layout.force_fps)
        cadence_tiers = build_tiers(target_fps)
        update_fps(target_fps)
        return
    end

    local want_eco = eco_wanted()

    if want_eco ~= active_eco then
        apply_active_profile(want_eco)
    end

    local desired = desired_fps_for_screen(s)

    target_fps = desired
    cadence_tiers = build_tiers(desired)

    update_fps(desired)
end

maybe_retune_for_screen = function(s)
    if layout.force_fps then return end

    local desired = desired_fps_for_screen(s)

    if desired < current_fps or current_fps < active_stability_floor then
        target_fps = desired
        cadence_tiers = build_tiers(desired)
        update_fps(desired)
    elseif desired > target_fps then
        target_fps = desired
        cadence_tiers = build_tiers(desired)
    end
end

kick_animation = function(s)
    if not layout.animations_on then return end
    if next(animating_clients) == nil then return end
    if surrendered() then return end

    if layout.force_fps then
        local forced = clamp_fps(layout.force_fps)
        if current_fps ~= forced then
            update_fps(forced)
        end
    elseif not anim_timer or not anim_timer.started then
        cold_start(s)
    else
        maybe_retune_for_screen(s)
    end

    ensure_timer()
    schedule_frame()
end

clear_animation = function(c)
    if c == nil then return end

    animating_clients[c] = nil

    if next(animating_clients) == nil then
        stop_timer()
    end
end

snap_all_to_targets = function()
    for c, data in pairs(animating_clients) do
        if c.valid ~= false and c.screen and awful.layout.get(c.screen) == layout then
            apply_geo(c, data.target_x, data.target_y, data.target_w, data.target_h)
        end
    end

    animating_clients = {}
    stop_timer()
end

local function set_target(c, x, y, w, h, instant)
    if c.valid == false then return end

    if not c:isvisible()
       or (not layout.animate_first_placement and not c.brrr_tiled_once) then
        clear_animation(c)
        apply_geo(c, x, y, w, h)
        c.brrr_tiled_once = true
        return
    end

    c.brrr_tiled_once = true

    if instant or not layout.animations_on or surrendered() then
        clear_animation(c)

        local g = c:geometry()
        local bw = c.border_width or beautiful.border_width or 0

        if abs((g.x - bw) - x) < 2 and abs((g.y - bw) - y) < 2 and
           abs((g.width + bw * 2) - w) < 2 and abs((g.height + bw * 2) - h) < 2 then
            return
        end

        apply_geo(c, x, y, w, h)
        return
    end

    local data = animating_clients[c]

    if data then
        if abs(data.target_x - x) < 2 and abs(data.target_y - y) < 2 and
           abs(data.target_w - w) < 2 and abs(data.target_h - h) < 2 then
            return
        end

        data.vel_x = update_momentum(data.cur_x, data.vel_x, x)
        data.vel_y = update_momentum(data.cur_y, data.vel_y, y)
        data.vel_w = update_momentum(data.cur_w, data.vel_w, w)
        data.vel_h = update_momentum(data.cur_h, data.vel_h, h)

        data.target_x, data.target_y, data.target_w, data.target_h = x, y, w, h

        kick_animation(c.screen)
        return
    end

    local g = c:geometry()
    local bw = c.border_width or beautiful.border_width or 0

    local cur_x, cur_y = g.x - bw, g.y - bw
    local cur_w, cur_h = g.width + bw * 2, g.height + bw * 2

    if abs(cur_x - x) < 2 and abs(cur_y - y) < 2 and
       abs(cur_w - w) < 2 and abs(cur_h - h) < 2 then
        apply_geo(c, x, y, w, h)
        return
    end

    animating_clients[c] = {
        cur_x = cur_x,
        cur_y = cur_y,
        cur_w = cur_w,
        cur_h = cur_h,

        vel_x = 0,
        vel_y = 0,
        vel_w = 0,
        vel_h = 0,

        target_x = x,
        target_y = y,
        target_w = w,
        target_h = h,
    }

    kick_animation(c.screen)
end

-- ==========================================
-- REFRESH DETECTION
-- ==========================================
local function schedule_refresh_recheck(delay)
    gears.timer.start_new(delay or 0.8, function()
        if layout.detect_refresh then
            layout.detect_refresh()
        end

        return false
    end)
end

local function parse_xrandr(out)
    local rates = {}
    local by_name = {}
    local by_geo = {}

    local current_output = nil
    local current_geo = nil

    for line in tostring(out or ""):gmatch("[^\r\n]+") do
        local connected_name = line:match("^(%S+) connected")
        local disconnected_name = line:match("^(%S+) disconnected")

        if connected_name then
            current_output = connected_name

            local w, h, x, y = line:match("(%d+)x(%d+)%+(%d+)%+(%d+)")

            if w and h and x and y then
                current_geo = string.format(
                    "%dx%d+%d+%d",
                    tonumber(w),
                    tonumber(h),
                    tonumber(x),
                    tonumber(y)
                )
            else
                current_geo = nil
            end
        elseif disconnected_name then
            current_output = nil
            current_geo = nil
        elseif current_output and line:match("^%s") then
            if line:find("*", 1, true) then
                for rate in line:gmatch("([%d%.]+)%*") do
                    local n = tonumber(rate)

                    if n and n >= 24 then
                        rates[#rates + 1] = n
                        by_name[current_output] = n

                        if current_geo then
                            by_geo[current_geo] = n
                        end

                        break
                    end
                end
            end
        end
    end

    return rates, by_name, by_geo
end

local function choose_global_rate(rates)
    if #rates == 0 then return nil end

    local policy = tostring(layout.refresh_policy or "min"):lower()

    if policy == "off" then return nil end
    if policy == "first" then return rates[1] end

    local chosen = rates[1]

    for i = 2, #rates do
        if policy == "max" then
            if rates[i] > chosen then chosen = rates[i] end
        else
            if rates[i] < chosen then chosen = rates[i] end
        end
    end

    return chosen
end

local function apply_detected_refresh(rates, by_name, by_geo)
    if not layout.refresh_lock then return end
    if layout.force_fps then return end

    if tostring(layout.refresh_policy or "min"):lower() == "off" then
        return
    end

    local r = choose_global_rate(rates)
    if not r or r < 24 then return end

    refresh_by_name = by_name
    refresh_by_geo = by_geo

    detected_refresh = clamp_fps(r)
    refresh_hz = detected_refresh
    profile_override_active = false

    local desired = desired_fps_for_screen(capi.screen.focused)

    target_fps = desired
    cadence_tiers = build_tiers(desired)

    if not (anim_timer and anim_timer.started) then
        update_fps(desired)
    elseif current_fps > desired or current_fps < active_stability_floor then
        update_fps(desired)
    end

    dbg(
        "refresh", refresh_hz, "hz -> tiers",
        table.concat(cadence_tiers, "/")
    )
end

local detection_in_flight = false

function layout.detect_refresh()
    if layout.force_fps then return false end
    if not layout.refresh_lock then return false end

    if tostring(layout.refresh_policy or "min"):lower() == "off" then
        return false
    end

    if not awful.spawn or not awful.spawn.easy_async_with_shell then
        return false
    end

    if detection_in_flight then return true end

    detection_in_flight = true

    awful.spawn.easy_async_with_shell(
        "xrandr --current 2>/dev/null",
        function(out)
            detection_in_flight = false

            local rates, by_name, by_geo = parse_xrandr(out)

            if #rates > 0 then
                apply_detected_refresh(rates, by_name, by_geo)
            end
        end
    )

    return true
end

layout.detect_refresh()
schedule_refresh_recheck(1.2)
schedule_refresh_recheck(3.0)

-- ==========================================
-- PUBLIC CONTROL
-- ==========================================
function layout.set_animations(enabled)
    enabled = enabled and true or false

    if layout.animations_on == enabled then return end

    layout.animations_on = enabled

    if not enabled then
        snap_all_to_targets()
    end
end

function layout.toggle_animations()
    layout.set_animations(not layout.animations_on)
    return layout.animations_on
end

function layout.set_fps(fps)
    if fps == nil then
        layout.force_fps = nil
        cold_start(capi.screen.focused)
    else
        layout.force_fps = clamp_fps(fps)
        update_fps(layout.force_fps)
    end
end

function layout.set_eco(mode)
    layout.eco = mode
    eco_cache = nil
    eco_cache_at = -math.huge

    if not layout.force_fps then
        cold_start(capi.screen.focused)
    end
end

function layout.cancel_surrender()
    surrender_until_s = 0
end

function layout.tiers()
    return string.format(
        "%s%s%s (target %dfps, current %dfps)",
        table.concat(cadence_tiers, "/"),
        refresh_hz and string.format(" (panel %d hz)", refresh_hz) or " (undetected)",
        active_eco and " eco" or "",
        target_fps or current_fps,
        current_fps
    )
end

function layout.set_power_profile(profile)
    local p = tostring(profile or ""):lower():match("^%s*(.-)%s*$")

    if p == "" then return end

    local hint = profile_refresh_for(p)

    if hint then
        profile_refresh_hint = hint
        detected_refresh = hint
        refresh_hz = hint
        profile_override_active = true
    end

    eco_cache = nil
    eco_cache_at = -math.huge

    if not layout.force_fps then
        cold_start(capi.screen.focused)
    end

    schedule_refresh_recheck(0.7)
    schedule_refresh_recheck(2.0)
end

-- optional immediate hook from your power bar:
-- awesome.emit_signal("brrr::power_profile", profile_name)
if awesome and awesome.connect_signal then
    awesome.connect_signal("brrr::power_profile", function(profile)
        layout.set_power_profile(profile)
    end)
end

-- profile state poller: no bar modification strictly required
local last_profile_token = initial_profile or "none"

gears.timer {
    timeout = clamp_num(layout.profile_poll_seconds, 0.25, 10.0),
    call_now = false,
    autostart = true,
    callback = function()
        local prof = read_profile_state(true)
        local token = prof or "none"

        if token ~= last_profile_token then
            last_profile_token = token

            if prof then
                layout.set_power_profile(prof)
            end
        end
    end,
}

-- catch mode changes / hotplug as best as awesome allows
if capi.screen and capi.screen.connect_signal then
    capi.screen.connect_signal("property::geometry", function()
        schedule_refresh_recheck(0.5)
    end)

    capi.screen.connect_signal("list", function()
        schedule_refresh_recheck(0.5)
    end)
end

-- ==========================================
-- LAYOUT ENGINE
-- ==========================================
local screen_state = setmetatable({}, { __mode = "k" })

local function get_state(s)
    local st = screen_state[s]

    if not st then
        st = {}
        screen_state[s] = st
    end

    return st
end

local function client_in_list(c, list)
    for _, v in ipairs(list) do
        if v == c then return true end
    end

    return false
end

local function order_by_x(clients)
    table.sort(clients, function(a, b)
        local ax, bx = a.brrr_last_x or a.x, b.brrr_last_x or b.x

        if ax ~= bx then return ax < bx end

        local ay, by = a.brrr_last_y or a.y, b.brrr_last_y or b.y

        if ay ~= by then return ay < by end

        return a.window < b.window
    end)
end

local function order_spatially(clients, col_threshold)
    order_by_x(clients)

    local clusters = {}

    for _, c in ipairs(clients) do
        local cx = c.brrr_last_x or c.x
        local last = clusters[#clusters]

        if last and abs(cx - last.ref_x) < col_threshold then
            table.insert(last.clients, c)
        else
            table.insert(clusters, { ref_x = cx, clients = { c } })
        end
    end

    local ordered = {}

    for _, cl in ipairs(clusters) do
        table.sort(cl.clients, function(a, b)
            local ay, by = a.brrr_last_y or a.y, b.brrr_last_y or b.y

            if ay ~= by then return ay < by end

            return a.window < b.window
        end)

        for _, c in ipairs(cl.clients) do
            table.insert(ordered, c)
        end
    end

    return ordered
end

local function on_screen(s)
    return s ~= nil and awful.layout.get(s) == layout
end

local pending_arrange = setmetatable({}, { __mode = "k" })

local function schedule_arrange(s)
    if not on_screen(s) or pending_arrange[s] then return end

    pending_arrange[s] = true

    gears.timer.delayed_call(function()
        pending_arrange[s] = nil

        if on_screen(s) then
            awful.layout.arrange(s)
        end
    end)
end

local function rearrange(c)
    if c.valid ~= false and c.screen and on_screen(c.screen) then
        schedule_arrange(c.screen)
    end
end

function layout.arrange(p)
    if not p or not p.screen then return end

    local st = get_state(p.screen)

    local instant = st.want_instant
    st.want_instant = nil

    local clients = {}

    for _, c in ipairs(p.clients) do
        if c.type == "normal" and not c.floating and not c.maximized
           and not c.maximized_horizontal and not c.maximized_vertical
           and not c.fullscreen and not c.minimized and not c.transient_for then
            table.insert(clients, c)
        end
    end

    dbg("arrange", "clients:", #clients, "instant:", instant, "fps:", current_fps)

    if #clients == 0 then return end

    for _, c in ipairs(clients) do
        if c.brrr_last_screen ~= p.screen then
            c.brrr_last_x = nil
            c.brrr_last_y = nil
            c.brrr_last_screen = p.screen
            c.brrr_tiled_once = nil
        end
    end

    local workarea = p.workarea
    local gap = max(0, p.useless_gap or gap_size)

    local focused = capi.client.focus

    if focused and focused.valid ~= false and client_in_list(focused, clients) then
        st.master = focused
    elseif not (st.master and st.master.valid ~= false and client_in_list(st.master, clients)) then
        st.master = nil
    end

    local num_clients = #clients

    if num_clients == 1 then
        local c = clients[1]
        st.master = c

        local tx, ty = workarea.x + gap, workarea.y + gap

        c.brrr_last_x, c.brrr_last_y = tx, ty

        set_target(
            c,
            tx,
            ty,
            workarea.width - gap * 2,
            workarea.height - gap * 2,
            instant
        )

        return
    end

    local factor = st.focus_factor
        or (num_clients <= 4 and focus_factor_small or focus_factor_large)

    if num_clients == 2 then
        order_by_x(clients)

        st.master = st.master or clients[1]

        local master = st.master
        local master_w = floor(workarea.width * factor)
        local other_w = workarea.width - master_w
        local current_x = workarea.x

        for _, c in ipairs(clients) do
            local w = (c == master) and master_w or other_w
            local tx, ty = current_x + gap, workarea.y + gap

            c.brrr_last_x, c.brrr_last_y = tx, ty

            set_target(
                c,
                tx,
                ty,
                w - gap * 2,
                workarea.height - gap * 2,
                instant
            )

            current_x = current_x + w
        end

        return
    end

    clients = order_spatially(clients, workarea.width * 0.15)

    st.master = st.master or clients[1]

    local master = st.master

    local num_cols = ceil(num_clients / 2)
    local base_count = floor(num_clients / num_cols)
    local remainder = num_clients % num_cols

    local columns = {}
    local client_idx = 1

    for col = 1, num_cols do
        local count = base_count + (col <= remainder and 1 or 0)

        columns[col] = {}

        for _ = 1, count do
            table.insert(columns[col], clients[client_idx])
            client_idx = client_idx + 1
        end
    end

    local master_col = 1

    for i, col in ipairs(columns) do
        if client_in_list(master, col) then
            master_col = i
            break
        end
    end

    local master_w = floor(workarea.width * factor)
    local unfocused_w = floor((workarea.width - master_w) / (num_cols - 1))

    local col_widths = {}

    for i = 1, num_cols do
        col_widths[i] = (i == master_col) and master_w or unfocused_w
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
            local h = (j == num_in_col)
                and (workarea.y + workarea.height - current_y)
                or row_h

            local tx, ty = current_x + gap, current_y + gap

            c.brrr_last_x, c.brrr_last_y = tx, ty

            set_target(
                c,
                tx,
                ty,
                col_w - gap * 2,
                h - gap * 2,
                instant
            )

            current_y = current_y + h
        end

        current_x = current_x + col_w
    end
end

layout.resize_handler = function(c, context, h)
    if not c or c.valid == false or not c.screen then return end

    if context ~= "mouse.resize" and context ~= "mouse.move" then return end

    local dx = (h and h.dx) or 0

    if dx == 0 then return end

    local wa = c.screen.workarea

    if not wa or not wa.width or wa.width <= 0 then return end

    local st = get_state(c.screen)
    local current = st.focus_factor or focus_factor_small

    st.focus_factor = min(factor_max, max(factor_min, current + dx / wa.width))

    if not layout.animate_resizing then
        st.want_instant = true
    end

    schedule_arrange(c.screen)
end

-- ==========================================
-- SIGNALS
-- ==========================================
capi.client.connect_signal("unmanage", function(c)
    clear_animation(c)

    for _, st in pairs(screen_state) do
        if st.master == c then
            st.master = nil
        end
    end
end)

capi.client.connect_signal("focus", function(c)
    if c.valid == false or not c.screen then return end
    if not on_screen(c.screen) then return end

    local st = get_state(c.screen)

    if st.master == c then return end

    schedule_arrange(c.screen)
end)

capi.client.connect_signal("property::fullscreen", function(c)
    if c.valid == false then return end

    if c.fullscreen then
        clear_animation(c)
    else
        rearrange(c)
    end
end)

local function on_maximize_change(c)
    if c.valid == false then return end

    if c.maximized or c.maximized_horizontal or c.maximized_vertical then
        clear_animation(c)
    else
        rearrange(c)
    end
end

capi.client.connect_signal("property::maximized", on_maximize_change)
capi.client.connect_signal("property::maximized_horizontal", on_maximize_change)
capi.client.connect_signal("property::maximized_vertical", on_maximize_change)

capi.client.connect_signal("property::floating", function(c)
    if c.valid == false then return end

    if c.floating then
        clear_animation(c)
    end

    rearrange(c)
end)

capi.client.connect_signal("property::minimized", function(c)
    if c.valid == false then return end

    if c.minimized then
        clear_animation(c)
    end

    rearrange(c)
end)

capi.client.connect_signal("property::border_width", function(c)
    if c.valid == false then return end

    rearrange(c)
end)

return layout
