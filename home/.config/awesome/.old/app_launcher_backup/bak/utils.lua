---------------------------------------------------------------------------
-- Shared utility helpers for the app launcher.
-- Pure functions where possible; small async wrapper for math evaluation.
---------------------------------------------------------------------------

local awful = require("awful")

local utils = {}

--- Maps terminal binary names to the command prefix used to launch a
--- program inside that terminal.
utils.terminal_commands_lookup = {
    alacritty  = "alacritty -e",
    termite    = "termite -e",
    rxvt       = "rxvt -e",
    terminator = "terminator -e",
}

--- Fuzzy match score. Lower is better. 100 means "no match".
function utils.get_match_score(text, name)
    if not text or text == "" then return 0 end
    if not name or name == "" then return 100 end
    local t = text:lower()
    local n = name:lower()

    if n == t then return 0 end
    if n:sub(1, #t) == t then return 1 end

    local pos = n:find(t, 1, true)
    if pos then return pos + 2 end

    return 100
end

--- Case-insensitive "does this value appear in this table" check.
function utils.has_value(tab, val)
    if not val or val == "" then return false end
    if not tab then return false end
    local val_lower = tostring(val):lower()
    for _, value in pairs(tab) do
        if val_lower:find(tostring(value):lower(), 1, true) then return true end
    end
    return false
end

--- Runs `qalc` on `expr` (leading `=` stripped) and returns the trimmed
--- result via `callback`. Returns "..." for empty input, "Error" on failure.
function utils.evaluate_math(expr, callback)
    local clean_expr = expr:gsub("^=%s*", "")
    if clean_expr == "" then
        callback("...")
        return
    end
    local safe_expr = clean_expr:gsub("'", "'\\''")
    awful.spawn.easy_async_with_shell(string.format("qalc -t '%s' 2>&1", safe_expr), function(stdout)
        local result = (stdout or ""):gsub("^%s*(.-)%s*$", "%1")
        result = result:gsub("\27%[[0-9;]*[a-zA-Z]", "")
        result = result:gsub("[%c\r]", "")

        if result:lower():match("error") or result == "" then
            callback("Error")
        else
            callback(result)
        end
    end)
end

return utils