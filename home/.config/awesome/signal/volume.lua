local awful = require("awful")

local volume_old = -1
local muted_old = -1

local function emit_volume_info()
    -- Get volume percentage
    awful.spawn.easy_async_with_shell("amixer -D pulse get Master | tail -n 1 | awk '{print $5}' | tr -d '[%]'", function(vol_out)
        -- Get mute state
        awful.spawn.easy_async_with_shell("amixer -D pulse get Master | grep -o '\\[on\\]\\|\\[off\\]'", function(mute_out)
            local volume = tonumber(vol_out:match("%d+")) or 0
            local muted = mute_out:match("\\[on\\]") ~= nil
            
            if volume ~= volume_old or muted ~= muted_old then
                awesome.emit_signal("volume::value", tostring(volume))
                awesome.emit_signal("volume::muted", muted)
                volume_old = volume
                muted_old = muted
            end
        end)
    end)
end

emit_volume_info()

-- Listen for background changes
local volume_script = [[bash -c "amixer -D pulse monitor Master"]]

awful.spawn.easy_async({"pkill", "--full", "--uid", os.getenv("USER"), "^amixer monitor"}, function ()
    awful.spawn.with_line_callback(volume_script, {
        stdout = function(line)
            emit_volume_info()
        end
    })
end)
