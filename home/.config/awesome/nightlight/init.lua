-- nightlight/init.lua
-- solar-anchored color temperature for awesomewm
-- dependencies: sct, xrandr. no network.

--[[
SCIENCE NOTES & SYSTEMS ARCHITECTURE
====================================

1. THE SOLAR MATH (NOAA SUNRISE EQUATION)
   The J2000 epoch (946728000) is defined in UTC. If you pass local noon
   directly into the equations, the computed sunrise/sunset shifts by your
   exact timezone offset. (e.g., at GMT-6, passing local noon shifts the
   sun schedule by +6 hours, making the script think it's midnight at 6am).
   FIX: We compute local noon via os.time(), then subtract the timezone
   offset (parsed from os.date("%z")) to get the epoch for 12:00 UTC on
   that local date. The math then returns correct local epochs for sr/ss.

2. THE CURVE ("NEVER WARMER THAN THE SKY")
   - Pre-dawn (sr-2h .. sr): Ramps from deep (1900K) to pre_dawn (3400K).
     Waking up to pitch-black red is jarring; waking up to neutral is blinding.
     3400K is the sweet spot for early risers.
   - Sunrise (sr .. sr+90m): Ramps from pre_dawn to day (6500K).
   - Day (sr+90m .. ss): Holds at 6500K. The sun is up; the screen is neutral.
   - Dusk (ss .. ss+90m): Ramps from day to dusk (2700K).
   - Evening (ss+90m .. ss+150m): Ramps from dusk to deep (1900K).
   - Night: Holds at 1900K.
   Sunset is capped at `cap_hour` (default 21:00) so summer evenings don't
   keep you awake with blue light until 23:00.

3. THE ACTUATOR (sct)
   We use `sct` as a dumb, stateless actuator. `sct <kelvin>` overwrites
   the X11 gamma LUT instantly. We explicitly avoid daemon-mode tools
   (like redshift's background service) because they fight the controller
   for state ownership and suffer from gamma-stacking bugs when repeatedly
   polled. The Lua script is the brain; sct is just the muscle.

4. THE SLEW ENGINE (INTEGER MATH & JND)
   Human eyes detect flicker if color temperature jumps abruptly.
   We slew from current to target using a 10Hz micro-stepper.
   Crucially, it uses INTEGER-ONLY steps with a fractional residual budget.
   This prevents Lua 5.3+ from passing floats to string.format("%d"), and
   ensures that even at slow rates (e.g., 0.85 K/s), the screen moves
   smoothly (one 1K step every ~1.2s) without ever holding a fractional
   state. Step sizes are bounded to stay under the Just Noticeable
   Difference (JND) at 10Hz.

5. RECONCILIATION (MEASURE, DON'T BELIEVE)
   /tmp often survives reboots. If the state file says "1900K" but the
   display server reset the gamma LUT to neutral on boot, trusting the
   file causes a 90-minute crawl from 6500K down to 1900K.
   Instead, on boot/wake (absence > 5 min), we read the actual X11 gamma
   LUT via `xrandr --verbose`. If the LUT is 1.0:1.0:1.0, we assume 6500K.
   If it's warm, we trust the state file. Then we converge to the solar
   target. We also force a reconcile on date-change and every 6 hours
   to prevent long-uptime state desyncs.
]]--

local awful   = require("awful")
local gears   = require("gears")
local naughty = require("naughty")

local STATE = "/tmp/awesome_nightlight_state"
local TOOL  = "sct"

local RAMP_MORNING = 5400
local RAMP_DUSK    = 5400
local RAMP_EVENING = 3600
local SLEW_DT       = 0.1
local GAP_CONVERGE  = 300
local CONVERGE_SECS = 20
local CONVERGE_MAX  = 400
local RESYNC_SECS   = 6 * 3600
local PRE_DAWN_WINDOW = 7200 -- 2 hours before sunrise
local RAD           = math.pi / 180

local C = {
    day = 6500, pre_dawn = nil, dusk = 2700, deep = 1900,
    cap_hour = 21, evening_lag = 0, tick = 60,
    lat = nil, lon = nil,
    slew = nil,
    heal = 600,
    fade_manual = false,
    utc_offset_hours = nil,
}

local BRIDGE_DEBOUNCE = 0.25
local BRIDGE_MIN_GAP  = 2.0

local _started = false
local _timer, _bridge_timer, _slew_timer = nil, nil, nil
local _override, _override_since, _manual_k = nil, nil, nil
local _target_k, _target_why = nil, nil
local _current_k   = nil
local _slew_resid  = 0
local _converge    = false
local _dip_k, _dip_until = nil, 0
local _off_applied = false
local _last_applied, _last_apply_at = nil, 0
local _last_tick_at = 0
local _fail_streak = 0
local _last_log_k, _last_log_why, _last_log_t = nil, nil, 0

local _last_daykey = nil
local _last_full_check = 0

local function log(msg)
    io.stderr:write(("[nightlight %s] %s\n"):format(os.date("%H:%M:%S"), msg))
end

local function rint(x)
    local v = math.floor(x + 0.5)
    if math.tointeger then return math.tointeger(v) or v end
    return v
end

local function tz_offset_seconds(ts)
    if C.utc_offset_hours then return C.utc_offset_hours * 3600 end
    local z = os.date("%z", ts)
    if type(z) == "string" then
        local sign, hh, mm = z:match("^([+-])(%d%d)(%d%d)$")
        if sign and hh and mm then
            local s = (sign == "-") and -1 or 1
            return s * ((tonumber(hh) * 3600) + (tonumber(mm) * 60))
        end
    end
    local t = os.date("!*t", ts)
    t.isdst = nil
    return ts - os.time(t)
end

local function solar_events(now, lat, lon)
    local d = os.date("*t", now)
    local local_noon = os.time({
        year = d.year, month = d.month, day = d.day,
        hour = 12, min = 0, sec = 0,
    })
    local utc_noon = local_noon + tz_offset_seconds(local_noon)
    local jdays  = (utc_noon - 946728000) / 86400
    local jstar  = jdays - lon / 360
    local mean  = (357.5291 + 0.98560028 * jstar) % 360
    local meanr = mean * RAD
    local center = 1.9148 * math.sin(meanr)
                 + 0.02 * math.sin(2 * meanr)
                 + 0.0003 * math.sin(3 * meanr)
    local ecl  = (mean + center + 180 + 102.9372) % 360
    local eclr = ecl * RAD
    local delta = math.asin(math.sin(eclr) * math.sin(23.44 * RAD))
    local jtrans = jstar + 0.0053 * math.sin(meanr) - 0.0069 * math.sin(2 * eclr)
    local transit = 946728000 + jtrans * 86400
    local phi = lat * RAD
    local cosw = (math.sin(-0.833 * RAD) - math.sin(phi) * math.sin(delta))
               / (math.cos(phi) * math.cos(delta))
    if cosw <= -1 then return rint(transit - 86400), rint(transit + 86400) end
    if cosw >= 1 then return rint(transit + 43200), rint(transit - 43200) end
    local w = math.deg(math.acos(cosw)) / 360
    return rint(transit - w * 86400), rint(transit + w * 86400)
end

local function fixed_sun(now)
    local d = os.date("*t", now)
    return os.time({year = d.year, month = d.month, day = d.day, hour = 6, min = 30, sec = 0}),
           os.time({year = d.year, month = d.month, day = d.day, hour = 19, min = 30, sec = 0})
end

local function valid_epoch(x)
    return type(x) == "number" and x == x and x > 0 and x < 1e12
end

local function anchors(now)
    local sr, ss
    if C.lat and C.lon then sr, ss = solar_events(now, C.lat, C.lon)
    else sr, ss = fixed_sun(now) end
    if not (valid_epoch(sr) and valid_epoch(ss)) then sr, ss = fixed_sun(now) end
    local d = os.date("*t", now)
    local cap = os.time({year = d.year, month = d.month, day = d.day, hour = C.cap_hour, min = 0, sec = 0})
    if ss > cap then ss = cap end
    ss = ss + (C.evening_lag or 0)
    return sr, ss
end

local function target_kelvin(now, sr, ss)
    local has_pre_dawn = C.pre_dawn and C.pre_dawn > C.deep and C.pre_dawn < C.day
    local pre_dawn_start = sr - PRE_DAWN_WINDOW

    if now < sr then
        if has_pre_dawn and now >= pre_dawn_start then
            local t = (now - pre_dawn_start) / PRE_DAWN_WINDOW
            return C.deep + (C.pre_dawn - C.deep) * t, "pre-dawn ramp"
        end
        return C.deep, "night"
    end

    if now < sr + RAMP_MORNING then
        local start_k = has_pre_dawn and C.pre_dawn or C.deep
        local t = (now - sr) / RAMP_MORNING
        return start_k + (C.day - start_k) * t, "sunrise ramp"
    end

    if now < ss then return C.day, "day" end

    if now < ss + RAMP_DUSK then
        local t = (now - ss) / RAMP_DUSK
        return C.day + (C.dusk - C.day) * t, "dusk ramp"
    end

    if now < ss + RAMP_DUSK + RAMP_EVENING then
        local t = (now - (ss + RAMP_DUSK)) / RAMP_EVENING
        return C.dusk + (C.deep - C.dusk) * t, "evening ramp"
    end

    return C.deep, "night"
end

local function persist(k)
    local f = io.open(STATE, "w")
    if f then f:write(string.format("%d\n", k)); f:close() end
end

local function load_state()
    local f = io.open(STATE, "r")
    if not f then return nil end
    local k = tonumber(f:read("*l") or "")
    f:close()
    if k and k >= 1000 and k <= 10000 then return math.floor(k + 0.5) end
    return nil
end

local function _emit_status()
    local line
    if _override == false then line = "off"
    elseif _override == true then line = string.format("manual %dK", _manual_k or 0)
    else line = string.format("%dK %s", math.floor(_current_k or _last_applied or 0), _target_why or "?") end
    awesome.emit_signal("nightlight::status", line)
end

local function apply(k, why, force)
    local k_int = math.floor((tonumber(k) or 0) + 0.5)
    if k_int < 1000 or k_int > 10000 then return end
    if not force and k_int == _last_applied then return end
    _last_applied = k_int
    _last_apply_at = os.time()
    _off_applied = false
    awful.spawn.easy_async_with_shell(
        string.format("timeout 10 %s %d >/dev/null 2>&1", TOOL, k_int),
        function(_, _, _, exit)
            if exit ~= 0 then
                _fail_streak = _fail_streak + 1
            else
                if _fail_streak ~= 0 then _fail_streak = 0 end
                persist(k_int)
                awesome.emit_signal("nightlight::applied", k_int, why)
                _emit_status()
            end
        end
    )
end

local function apply_off(force)
    if _off_applied and not force then return end
    _off_applied = true
    _target_k, _target_why = nil, nil
    _converge, _slew_resid = false, 0
    if _slew_timer then _slew_timer:stop() end
    _current_k, _last_applied = 6500, 6500
    _last_apply_at = os.time()
    awful.spawn.easy_async_with_shell(
        string.format("timeout 10 %s >/dev/null 2>&1", TOOL),
        function(_, _, _, exit)
            if exit == 0 then persist(6500) end
            awesome.emit_signal("nightlight::applied", nil, "off")
            awesome.emit_signal("nightlight::mode_changed", "off")
            _emit_status()
        end
    )
end

local function advance(cur, target, rate, dt, resid)
    local delta = target - cur
    if delta == 0 then return cur, 0 end
    local budget = rate * dt + resid
    local step = math.floor(budget)
    resid = budget - step
    if step < 1 then return cur, resid end
    if step > math.abs(delta) then step, resid = math.abs(delta), 0 end
    return cur + (delta > 0 and step or -step), resid
end

local function slew_step()
    if not _target_k or _current_k == nil then
        if _slew_timer then _slew_timer:stop() end
        return
    end
    local r = C.slew or 1
    if _converge then
        r = math.min(CONVERGE_MAX, math.max(r, math.abs(_target_k - _current_k) / CONVERGE_SECS))
    end
    local cur, resid = advance(_current_k, _target_k, r, SLEW_DT, _slew_resid)
    _current_k, _slew_resid = cur, resid
    apply(cur, _target_why)
    if cur == _target_k then
        _converge = false
        if _slew_timer then _slew_timer:stop() end
    end
end

local function ensure_slew()
    if _target_k and _current_k and _current_k ~= _target_k then
        if not _slew_timer then
            _slew_timer = gears.timer({ timeout = SLEW_DT, autostart = false, callback = slew_step })
        end
        if not _slew_timer.started then _slew_timer:again() end
    end
end

local function set_target(k, why)
    local k_int = math.floor((tonumber(k) or 0) + 0.5)
    if k_int < 1000 or k_int > 10000 then return end
    _target_k, _target_why = k_int, why
    if _current_k == nil then _current_k = load_state() or 6500 end
    if _current_k == k_int then
        _converge = false
        if C.heal > 0 and (os.time() - _last_apply_at) >= C.heal then apply(k_int, why, true) end
    else
        ensure_slew()
    end
end

local function snap(k, why)
    local k_int = math.floor((tonumber(k) or 0) + 0.5)
    if k_int < 1000 or k_int > 10000 then return end
    _target_k, _target_why, _current_k = k_int, why, k_int
    _converge, _slew_resid = false, 0
    if _slew_timer then _slew_timer:stop() end
    apply(k_int, why, true)
end

local function measure_screen(cb)
    awful.spawn.easy_async_with_shell("xrandr --verbose 2>/dev/null", function(out)
        local conn, saw, warm = false, false, false
        for line in (out or ""):gmatch("[^\r\n]+") do
            if line:match("^%S+ connected") then conn = true
            elseif line:match("^%S+ disconnected") then conn = false
            elseif conn then
                local r, g, b = line:match("^%s*Gamma:%s*([%d%.]+):([%d%.]+):([%d%.]+)")
                if r then
                    saw = true
                    if math.abs((tonumber(r) or 1) - 1) > 0.02
                       or math.abs((tonumber(g) or 1) - 1) > 0.02
                       or math.abs((tonumber(b) or 1) - 1) > 0.02 then
                        warm = true
                    end
                end
            end
        end
        if not saw then cb(nil) else cb(warm and "warm" or "neutral") end
    end)
end

local function reconcile(cb)
    measure_screen(function(s)
        if s == "neutral" then _current_k = 6500
        else
            local k = load_state()
            if s == "warm" and k and k < 6400 then _current_k = k
            else _current_k = k or 6500 end
        end
        _last_full_check = os.time()
        if cb then cb() end
    end)
end

local function decide()
    local now = os.time()
    if _override == false then apply_off() return end
    if _override == true then set_target(_manual_k, "manual hold") return end
    if _dip_k then
        if now < _dip_until then set_target(_dip_k, "preview") return end
        _dip_k = nil; _converge = true
    end
    local sr, ss = anchors(now)
    local k, why = target_kelvin(now, sr, ss)
    set_target(k, why)
end

local function tick()
    local now = os.time()
    local d = os.date("*t", now)
    local daykey = d.year * 1000 + d.yday
    local away = (now - _last_tick_at) > GAP_CONVERGE
    local day_changed = _last_daykey ~= daykey
    local stale = (now - _last_full_check) > RESYNC_SECS
    _last_tick_at = now
    if day_changed or stale then
        _last_daykey = daykey
        _last_full_check = now
        away = true
    end
    if _override then
        local sr = anchors(now)
        local dawn = sr + RAMP_MORNING
        while dawn <= (_override_since or now) do dawn = dawn + 86400 end
        if now >= dawn then
            _override, _manual_k = nil, nil
            naughty.notify({ text = "nightlight: auto (resumed)" })
        end
    end
    if away then
        reconcile(function() _converge = true; decide() end)
    else
        decide()
    end
end

local function _brightness_bridge()
    if not _bridge_timer then
        _bridge_timer = gears.timer({
            timeout = BRIDGE_DEBOUNCE, single_shot = true, autostart = false,
            callback = function()
                if (os.time() - _last_apply_at) < BRIDGE_MIN_GAP then return end
                if _override == false then apply_off(true)
                elseif _current_k then apply(_current_k, _target_why or "re-assert", true)
                else tick() end
            end,
        })
    end
    _bridge_timer:again()
end

local M = {}

function M.start()
    if _started then return end
    _started = true
    _last_daykey = nil
    _last_full_check = 0
    local ul = (type(user_likes) == "table" and user_likes) or {}
    local ov = (type(ul.nightlight) == "table" and ul.nightlight) or {}
    for _, key in ipairs({
        "day", "pre_dawn", "dusk", "deep", "cap_hour", "evening_lag",
        "tick", "slew", "heal",
    }) do
        local v = tonumber(ov[key])
        if v then C[key] = v end
    end
    if ov.fade_manual ~= nil then C.fade_manual = ov.fade_manual and true or false end
    C.utc_offset_hours = tonumber(ov.utc_offset_hours)
    local lat = tonumber(ov.lat) or tonumber(ul.lat)
    local lon = tonumber(ov.lon) or tonumber(ul.lon)
    if lat and lon and math.abs(lat) <= 90 and math.abs(lon) <= 180 then C.lat, C.lon = lat, lon
    else C.lat, C.lon = nil, nil end
    if C.cap_hour < 0 then C.cap_hour = 0 end
    if C.cap_hour > 23 then C.cap_hour = 23 end
    if C.tick < 10 then C.tick = 10 end
    if C.evening_lag < 0 then C.evening_lag = 0 end
    if C.heal < 0 then C.heal = 0 end
    local need = math.max(math.abs(C.day - C.deep) / RAMP_MORNING, math.abs(C.day - C.dusk) / RAMP_DUSK, math.abs(C.dusk - C.deep) / RAMP_EVENING)
    if not C.slew then C.slew = need
    elseif C.slew < need then C.slew = need end

    local pd_str = C.pre_dawn and string.format(", pre-dawn %dK", C.pre_dawn) or ""
    if C.lat and C.lon then
        log(string.format(
            "started: lat %.4f lon %.4f%s; max auto rate %.2f K/s",
            C.lat, C.lon, pd_str, C.slew
        ))
    else
        log("no valid lat/lon; fixed 06:30/19:30 schedule")
        naughty.notify({
            text = "nightlight: no valid coordinates configured; fixed 06:30/19:30 schedule",
            timeout = 10,
        })
    end
    awesome.connect_signal("signal::brightness", _brightness_bridge)
    _timer = gears.timer({ timeout = C.tick, autostart = true, call_now = true, callback = tick })
    gears.timer.start_new(0.05, function() _emit_status() end)
end

function M.stop()
    if _timer then _timer:stop() end
    if _bridge_timer then _bridge_timer:stop() end
    if _slew_timer then _slew_timer:stop() end
    awesome.disconnect_signal("signal::brightness", _brightness_bridge)
    _timer, _bridge_timer, _slew_timer = nil, nil, nil
    _started, _last_tick_at = false, 0
end

function M.reset()
    _override, _override_since, _manual_k = nil, nil, nil
    _dip_k, _dip_until = nil, 0
    _target_k, _target_why = nil, nil
    _current_k, _last_applied, _off_applied = 6500, 6500, false
    _converge, _slew_resid = false, 0
    _last_apply_at, _last_tick_at, _fail_streak = 0, 0, 0
    _last_daykey, _last_full_check = nil, 0
    if _slew_timer then _slew_timer:stop() end
    persist(6500)
    awful.spawn.easy_async_with_shell("timeout 10 sct >/dev/null 2>&1", function() end)
end

function M.resync()
    if not _started then return end
    _converge = true
    reconcile(function() _converge = true; decide() end)
    _emit_status()
end

function M.init()
    M.reset()
    if not _started then M.start() end
    _last_tick_at = 0
    tick()
    _emit_status()
end

function M.toggle()
    local now = os.time()
    if _override == nil then
        _override, _override_since = false, now
        apply_off()
    elseif _override == false then
        local sr, ss = anchors(now)
        local k = target_kelvin(now, sr, ss)
        _override, _override_since = true, now
        _manual_k = math.floor(k + 0.5)
        if C.fade_manual then set_target(_manual_k, "manual hold")
        else snap(_manual_k, "manual hold") end
    else
        _override, _manual_k = nil, nil
        _converge = true
        tick()
    end
    _emit_status()
end

function M.set_temp(k)
    k = tonumber(k)
    if not k or k < 1000 or k > 10000 then return false end
    _override, _override_since = true, os.time()
    _dip_k = nil
    _manual_k = math.floor(k + 0.5)
    if C.fade_manual then set_target(_manual_k, "manual")
    else snap(_manual_k, "manual") end
    _emit_status()
    return true
end

function M.dip(k, hold_secs)
    if not _started or _override ~= nil then return false end
    k = tonumber(k)
    if not k or k < 1000 or k > 10000 then return false end
    _dip_k = math.floor(k + 0.5)
    _dip_until = os.time() + (hold_secs or 600)
    _converge = true
    decide()
    return true
end

function M.refresh() tick() end

function M.status_line()
    if _override == false then return "off" end
    if _override == true then return string.format("manual %dK", _manual_k or 0) end
    return string.format("%dK %s", math.floor(_current_k or _last_applied or 0), _target_why or "?")
end

M._emit_status   = _emit_status
M._solar_events  = solar_events
M._anchors       = anchors
M._target_kelvin = target_kelvin
M._fixed_sun     = fixed_sun
M._advance       = advance
M._C             = C
M._RAMP          = { morning = RAMP_MORNING, dusk = RAMP_DUSK, evening = RAMP_EVENING }
M._CONV          = { gap = GAP_CONVERGE, secs = CONVERGE_SECS, max = CONVERGE_MAX, dt = SLEW_DT }
return M
