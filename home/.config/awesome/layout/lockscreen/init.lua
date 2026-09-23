local gfs = require("gears.filesystem")
local lock_screen = {}
local config_dir = gfs.get_configuration_dir()
package.cpath = package.cpath .. ";" .. config_dir .. "mods/?.so;"

-- Load fingerprint module
local fprint = require("layout.lockscreen.fprint")

lock_screen.init = function()
    local pam = require("liblua_pam")
    
    -- Password authentication
    lock_screen.authenticate = function(password)
        return pam.auth_current_user(password)
    end

    -- Expose fingerprint module properly (fixed the broken fprint.verify() call)
    lock_screen.fprint = fprint

    -- Load the lockscreen UI
    require("layout.lockscreen.lock")
end

return lock_screen