---------------------------------------------------------------------------
-- Free game notifier (GamerPower API) — replaces misc/scripts/games.py
-- No extra process: a gears.timer inside awesome. State file is
-- compatible with the python version, so nothing gets re-notified.
---------------------------------------------------------------------------
local awful   = require("awful")
local gears   = require("gears")
local naughty = require("naughty")
local json    = require("misc.json")

local API_URL    = "https://www.gamerpower.com/api/filter?platform=steam.epic-games-store.ubisoft&type=game&sort-by=date"
local INTERVAL   = 30
local STATE_FILE = os.getenv("HOME") .. "/.config/awesome/misc/.information/.free_game_notifier_state.json"
local CACHE_DIR  = os.getenv("HOME") .. "/.config/awesome/misc/.information/free_game_notifier"

local seen = {}

local function load_state()
    local f = io.open(STATE_FILE, "r")
    if not f then return end
    local ok, data = pcall(json.decode, f:read("*a"))
    f:close()
    if ok and type(data) == "table" then
        for _, id in ipairs(data) do seen[tostring(id)] = true end
    end
end

local function save_state()
    local out = {}
    for id in pairs(seen) do out[#out + 1] = tonumber(id) or id end
    local f = io.open(STATE_FILE, "w")"/.config/awesome/misc/.information"
    if f then f:write(json.encode(out)) f:close() end
end

local function notify(game, image)
    local url = game.open_giveaway or game.gamerpower_url
    if not url or url == "" then return end

    local msg = string.format("%s • Ends: %s\n%s\n\n%s",
        (game.worth ~= "N/A" and game.worth) or "Free",
        (game.end_date ~= "N/A" and game.end_date) or "Ongoing",
        game.platforms or "PC",
        (game.description or ""):gsub("%s+", " "):sub(1, 150))

    local open = function()
        awful.spawn { "xdg-open", url }   -- no shell, so "&" in URLs is safe
    end

    naughty.notification {
        title   = "🆓 " .. (game.title or "Free game"),
        message = msg,
        image   = image,      -- nil → your theme's fallback icon
        timeout = 15,         -- naughty counts seconds, not ms
        urgency = "normal",
        actions = { naughty.action { name = "🔗 打开链接", invoke = open } },
        run     = open,       -- whole popup clickable; delete line if it
                              -- clashes with your theme's click handling
        _game_notification = true,
    }
end

local function fetch_and_notify(game)
    if not game.thumbnail or game.thumbnail == "N/A" then
        notify(game, nil)
        return
    end
    local path = CACHE_DIR .. "/" .. game.id .. ".jpg"
    awful.spawn.easy_async_with_shell(
        string.format("mkdir -p '%s' && curl -fsS --max-time 20 -o '%s' '%s'",
            CACHE_DIR, path, game.thumbnail),
        function(_, _, _, exitcode)
            notify(game, exitcode == 0 and path or nil)
        end)
end

local function check()
    awful.spawn.easy_async_with_shell(
        string.format("curl -fsS --max-time 20 -A 'free-game-notifier/1.0' '%s'", API_URL),
        function(stdout, _, _, exitcode)
            if exitcode ~= 0 then return end          -- offline: retry next cycle
            local ok, data = pcall(json.decode, stdout)
            if not ok or type(data) ~= "table" or data[1] == nil then
                return                                 -- {status=0} = no giveaways
            end
            local fresh = {}
            for _, g in ipairs(data) do
                if g.id and not seen[tostring(g.id)] then fresh[#fresh + 1] = g end
            end
            if #fresh == 0 then return end
            for _, g in ipairs(fresh) do
                seen[tostring(g.id)] = true
                fetch_and_notify(g)
            end
            save_state()
        end)
end

load_state()
gears.timer {
    timeout = INTERVAL, autostart = true, call_now = true, callback = check,
}

return { check = check }
