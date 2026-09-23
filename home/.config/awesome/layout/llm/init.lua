-- /layout/llm/init.lua
local awful = require("awful")
local gears = require("gears")

local M = {}

-- Cached LLM state so keybind feedback is instant (no async wait)
local cached_running = false
local cached_mode = nil

-- ===== CONFIGURATION =====
local HOME = os.getenv("HOME") or ""
local SERVER_BIN = HOME .. "/llama.cpp/build/bin/llama-server"
local BASE_MODEL = HOME .. "/models/SIQ-1-35B-ONYX-compact.gguf"
local HOST = "0.0.0.0"
local PORT = "5001"
local LOCK_FILE = "/tmp/llama-manager.lock"
local LOG_FILE = "/tmp/llama-server.log"

local MODE_CONFIG = {
    research = "-c 163840 --rope-scaling yarn --rope-scale 5 --yarn-orig-ctx 32768 --alias SIQ-1-35B.Q5_K_M --fit -b 4096 -ub 1024 -dt 0.1 -t 12 -tb 12 -fa on -ctk q8_0 -ctv q8_0 --ctx-checkpoints 0 --ctx-checkpoints-interval 0 --jinja --verbose --context-shift on --keep -1 --reasoning-format auto --reasoning-budget 12288 --temp 0.85 --top-p 0.95 --top-k 40 --min-p 0.05 --repeat-penalty 1.1 --presence-penalty 0.0",
    chat = "-c 131072 --rope-scaling yarn --rope-scale 4 --yarn-orig-ctx 32768 --alias darwin-36b --fit -b 4096 -ub 1024 -t 12 -tb 12 -fa on -ctk q8_0 -ctv q8_0 --ctx-checkpoints 0 --ctx-checkpoints-interval 0 --jinja --verbose --context-shift on --keep -1 --reasoning-format auto --reasoning-budget 8192 --temp 0.85 --top-p 1.15 --top-k 40 --presence-penalty 0.0"
}

-- ===== HELPERS =====
local function is_pid_alive(pid, callback)
    if not pid or pid == "" then callback(false) return end
    awful.spawn.easy_async_with_shell(
        string.format("kill -0 %s 2>/dev/null && echo yes || echo no", pid),
        function(stdout) callback(stdout:match("yes") ~= nil) end
    )
end

function M.is_running(callback)
    local f = io.open(LOCK_FILE, "r")
    local pid = nil
    if f then
        pid = f:read("*l")
        f:close()
    end

    if pid and pid ~= "" then
        is_pid_alive(pid, function(alive)
            if alive then callback(true, pid)
            else os.remove(LOCK_FILE) callback(false, nil) end
        end)
    else
        awful.spawn.easy_async_with_shell(
            string.format("ss -tlnp 2>/dev/null | grep ':%s ' | grep -oP 'pid=\\K[0-9]+' | head -1", PORT),
            function(stdout)
                local port_pid = stdout:gsub("%s+", "")
                if port_pid ~= "" then
                    is_pid_alive(port_pid, function(alive)
                        if alive then 
                            local fw = io.open(LOCK_FILE, "w")
                            if fw then fw:write(port_pid) fw:close() end
                            callback(true, port_pid)
                        else callback(false, nil) end
                    end)
                else callback(false, nil) end
            end
        )
    end
end

-- ===== ACTIONS =====
function M.kill()
    -- Instant red feedback (optimistic: we are issuing a kill)
    awesome.emit_signal("llm::blink", "red")
    cached_running = false
    cached_mode = nil

    M.is_running(function(running, pid)
        if not running then
            -- Nothing was actually running; correct the flash
            awesome.emit_signal("llm::blink", "white")
            return
        end

        awful.spawn.easy_async(string.format("kill -TERM %s", pid), function()
            local checks = 0
            local timer = gears.timer { timeout = 0.5 }
            timer:connect_signal("timeout", function()
                checks = checks + 1
                is_pid_alive(pid, function(alive)
                    if not alive then
                        timer:stop()
                        os.remove(LOCK_FILE)
                    elseif checks >= 20 then
                        timer:stop()
                        awful.spawn.easy_async(string.format("kill -KILL %s", pid), function()
                            awful.spawn.easy_async(string.format("fuser -k %s/tcp", PORT), function()
                                os.remove(LOCK_FILE)
                            end)
                        end)
                    end
                end)
            end)
            timer:start()
        end)
    end)
end

function M.launch(mode)
    local config = MODE_CONFIG[mode]
    if not config then return end

    M.is_running(function(running)
        if running then
            -- Sync mode and blink if already running
            awesome.emit_signal("llm::mode", mode)
            awesome.emit_signal("llm::blink", mode) 
            return
        end

        awesome.emit_signal("llm::blink", mode)
        awesome.emit_signal("llm::mode", mode)

        local cmd = string.format(
            "bash -c 'nohup \"%s\" -m \"%s\" --host %s --port %s %s >> \"%s\" 2>&1 & echo $! > \"%s\"'",
            SERVER_BIN, BASE_MODEL, HOST, PORT, config, LOG_FILE, LOCK_FILE
        )

        awful.spawn.with_shell(cmd)
        
        -- Start health check loop asynchronously
        local health_checks = 0
        local health_timer = gears.timer { timeout = 1 }
        health_timer:connect_signal("timeout", function()
            health_checks = health_checks + 1
            awful.spawn.easy_async(string.format("curl -s -o /dev/null -w '%%{http_code}' http://localhost:%s/health", PORT), function(stdout)
                local code = stdout:gsub("%s+", "")
                -- FIX: Only emit ready when the server returns 200 OK.
                -- llama.cpp returns 503 while loading the model.
                if code == "200" then 
                    health_timer:stop()
                    awesome.emit_signal("llm::ready", mode)
                elseif health_checks >= 60 then health_timer:stop() end -- 60s timeout
            end)
        end)
        health_timer:start()
    end)
end

-- Cache so the copilot key can flash instantly instead of waiting on the
-- async is_running() subprocess (kill -0 / ss -tlnp).
function M.status_blink()
    local guess_running = cached_running
    local guess_mode = cached_mode

    -- Instant feedback from cache (no subprocess wait)
    if guess_running and guess_mode then
        awesome.emit_signal("llm::mode", guess_mode)
        awesome.emit_signal("llm::blink", guess_mode)
    else
        awesome.emit_signal("llm::blink", "white")
    end

    -- Refresh cache asynchronously and only re-flash if the guess was wrong
    M.is_running(function(running, pid)
        cached_running = running
        if not running then
            cached_mode = nil
            if running ~= guess_running or guess_mode ~= nil then
                awesome.emit_signal("llm::blink", "white")
            end
            return
        end
        awful.spawn.easy_async_with_shell(string.format("ps -p %s -o args=", pid), function(stdout)
            local new_mode
            if stdout:match("darwin%-36b") then new_mode = "chat"
            elseif stdout:match("Qwopus") then new_mode = "research" end
            cached_mode = new_mode

            if running ~= guess_running or new_mode ~= guess_mode then
                if new_mode then
                    awesome.emit_signal("llm::mode", new_mode)
                    awesome.emit_signal("llm::blink", new_mode)
                else
                    awesome.emit_signal("llm::blink", "white")
                end
            end
        end)
    end)
end

-- Prime cache at startup so the first status ping is accurate (no blink emitted)
M.is_running(function(running, pid)
    cached_running = running
    if not running then cached_mode = nil; return end
    awful.spawn.easy_async_with_shell(string.format("ps -p %s -o args=", pid), function(stdout)
        if stdout:match("darwin%-36b") then cached_mode = "chat"
        elseif stdout:match("Qwopus") then cached_mode = "research"
        else cached_mode = nil end
    end)
end)

return M