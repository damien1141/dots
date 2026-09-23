-- nightlight/test.lua -- plain Lua: lua nightlight/test.lua

local fails = 0

local function ok(c, m)
    if c then
        io.write("  ok   - ", m, "\n")
    else
        fails = fails + 1
        io.write("  FAIL - ", m, "\n")
    end
end

local function passthrough()
    return setmetatable({}, {
        __index = function()
            return function() end
        end,
    })
end

package.preload["awful"] = passthrough
package.preload["gears"] = passthrough
package.preload["naughty"] = passthrough

_G.awesome = {
    emit_signal = function() end,
    connect_signal = function() end,
    disconnect_signal = function() end,
}

local nl = dofile((arg[0]:match("^(.*[/])") or "./") .. "init.lua")
local C = nl._C
C.slew = 1

-- expected data: 2026-09-02, sr 06:09, ss 18:26, gmt-6
local LAT, LON = 9.1037, -94.5974
local t0 = os.time({ year = 2026, month = 9, day = 2, hour = 12 })

local sr, ss = nl._solar_events(t0, LAT, LON)
local e_sr = os.time({ year = 2026, month = 9, day = 2, hour = 6, min = 9 })
local e_ss = os.time({ year = 2026, month = 9, day = 2, hour = 18, min = 26 })

print("== solar math ==")

ok(sr and math.abs(sr - e_sr) <= 360,
    string.format("sunrise %s (API said 06:09)", os.date("%H:%M", sr)))

ok(ss and math.abs(ss - e_ss) <= 360,
    string.format("sunset %s (API said 18:26)", os.date("%H:%M", ss)))

local psr, pss = nl._solar_events(
    os.time({ year = 2026, month = 6, day = 21, hour = 12 }), 71, 0
)
ok(pss - psr == 172800, "polar day: clamped, no crash")

local nsr, nss = nl._solar_events(
    os.time({ year = 2026, month = 12, day = 21, hour = 12 }), 71, 0
)
ok(nss < nsr, "polar night: clamped, no crash")

print("== curve ==")

C.lat, C.lon = LAT, LON
local asr, ass = nl._anchors(t0)

local function at(h, m)
    return select(1, nl._target_kelvin(
        os.time({ year = 2026, month = 9, day = 2, hour = h, min = m or 0 }),
        asr, ass
    ))
end

ok(at(18, 14) == C.day, "18:14 sun up -> full day")
ok(at(7, 40) == C.day, "7:40 boot -> day")
ok(at(19, 26) > C.dusk and at(19, 26) < C.day, "19:26 -> mid dusk ramp")
ok(at(20, 56) == C.deep, "20:56 -> deep")
ok(at(5) == C.deep, "pre-dawn -> deep")

C.lat, C.lon = nil, nil
local now0 = os.time()
local fsr, fss = nl._fixed_sun(now0)

local prev, mx = nil, 0
for t = fsr - 7200, fss + 20000, 60 do
    local k = nl._target_kelvin(t, fsr, fss)
    if prev then mx = math.max(mx, math.abs(k - prev)) end
    prev = k
end

ok(mx <= 75, string.format("max 60s target step %.1f K (slope-bound)", mx))

print("== slew ==")

local cur, resid, bad, max_step, last, mid = 6500, 0, false, 0, 6500, nil

for i = 1, 60000 do
    cur, resid = nl._advance(cur, 1900, 0.85, 0.1, resid)
    if cur ~= math.floor(cur) then bad = true end
    max_step = math.max(max_step, math.abs(cur - last))
    last = cur
    if i == 600 then mid = cur end
end

ok(not bad, "fractional rate never yields fractional Kelvin")
ok(max_step <= 1, string.format("gentle steps are 1 K (max %.1f)", max_step))
ok(mid and math.abs((6500 - mid) - 51) <= 2,
    string.format("rate honored: %d K in 60s (~0.85 K/s)", 6500 - (mid or 0)))
ok(cur == 1900, "gentle walk lands exactly on target")

cur, resid, bad, max_step, last = 6500, 0, false, 0, 6500
local n = 0

for _ = 1, 60000 do
    n = n + 1
    local r = math.min(400, math.max(1, math.abs(1900 - cur) / 20))
    cur, resid = nl._advance(cur, 1900, r, 0.1, resid)

    if cur ~= math.floor(cur) then bad = true end
    max_step = math.max(max_step, math.abs(cur - last))
    last = cur

    if cur == 1900 then break end
end

ok(not bad and max_step <= 23, "converge steps <= 23 K")
ok(cur == 1900, string.format("converge lands exactly (%d ticks = %.1fs)", n, n * 0.1))

print(string.format("\n%d failure(s)", fails))
os.exit(fails == 0 and 0 or 1)
