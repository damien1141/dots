---------------------------------------------------------------------------
-- Health notifier — emits signals to resetwave bar for visual reminders
-- Water = blue, Fitness (grease-the-groove) = orange, Posture = pink
-- Toggle via user_likes.health in rc.lua
---------------------------------------------------------------------------
local awful   = require("awful")
local gears   = require("gears")

local user_likes = user_likes or {}
local health_cfg = user_likes.health or {}

local WATER_ENABLED   = health_cfg.water   ~= false
local POSTURE_ENABLED = health_cfg.posture ~= false
local G2G_ENABLED     = health_cfg.g2g     ~= false

local WATER_MIN   = 30 * 60
local WATER_MAX   = 90 * 60
local POSTURE_MIN = 20 * 60
local POSTURE_MAX = 60 * 60
local G2G_INTERVAL = 2 * 60 * 60

local function rand_interval(min_s, max_s)
    return min_s + math.random() * (max_s - min_s)
end

local function schedule_water()
    if not WATER_ENABLED then return end
    local delay = rand_interval(WATER_MIN, WATER_MAX)
    gears.timer.start_new(delay, function()
        awesome.emit_signal("health::water")
        schedule_water()
    end)
end

local function schedule_posture()
    if not POSTURE_ENABLED then return end
    local delay = rand_interval(POSTURE_MIN, POSTURE_MAX)
    gears.timer.start_new(delay, function()
        awesome.emit_signal("health::posture")
        schedule_posture()
    end)
end

local function schedule_fitness()
    if not G2G_ENABLED then return end
    gears.timer.start_new(G2G_INTERVAL, function()
        awesome.emit_signal("health::fitness")
        schedule_fitness()
    end)
end

local function start()
    math.randomseed(os.time())
    schedule_water()
    schedule_posture()
    schedule_fitness()
end

local function set_enabled(kind, enabled)
    if kind == "water"   then WATER_ENABLED   = enabled end
    if kind == "posture" then POSTURE_ENABLED = enabled end
    if kind == "g2g"     then G2G_ENABLED     = enabled end
end

start()

return {
    start       = start,
    set_enabled = set_enabled,
}