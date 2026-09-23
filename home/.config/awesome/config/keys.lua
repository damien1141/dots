-- keybinds haha
----------------
-- Copyleft © 2022 Saimoomedits


-- requirements
-- ~~~~~~~~~~~~
local awful         = require("awful")
local hotkeys_popup = require("awful.hotkeys_popup")
local lmachi        = require("mods.layout-machi")
local bling         = require("mods.bling")
local misc          = require("misc")
local llm = require("layout.llm")
local crosshair = require("layout.crosshair")
require("layout.lockscreen").init()
-- At the top of rc.lua with your other requires:
-- signal.bright is the single source of truth for brightness (keys + sliders + popups).
local brightness = require("signal.bright")
-- signal.icc owns ICC profile loading; composed on top of nightlight.
local icc = require("signal.icc")
-- nightlight: peer of brightness for color temperature (spectrum).
local nightlight = require("nightlight")

-- vars/misc
-- ~~~~~~~~~

-- modkey
local modkey    = "Mod4"

-- modifer keys
local shift     = "Shift"
local ctrl      = "Control"
local alt       = "Mod1"
local altgr     = "Mod5"

-- Configurations
-- ~~~~~~~~~~~~~~

-- mouse keybindings
awful.mouse.append_global_mousebindings({
    awful.button({ }, 4, awful.tag.viewprev),
    awful.button({ }, 5, awful.tag.viewnext),
})

-- launchers
awful.keyboard.append_global_keybindings({

    -- copilot key (Status Ping)
    awful.key({ modkey, "Shift" }, "#201", function ()
        llm.status_blink() -- Smart blink: White if off, Mode color if on
    end, {description = "Copilot: Status", group = "launcher"}),

    -- ctrl + copilot (Kill Server)
    awful.key({ modkey, shift, ctrl }, "#201", function ()
        llm.kill()
    end, {description = "Copilot: Kill Server", group = "launcher"}),

    -- alt + copilot (Spawn Chat)
    awful.key({ modkey, shift, alt }, "#201", function ()
        llm.launch("chat")
    end, {description = "Copilot: Chat", group = "launcher"}),

    -- altgr + copilot (Spawn Research)
    awful.key({ modkey, shift, altgr }, "#201", function ()
        llm.launch("research")
    end, {description = "Copilot: Research", group = "launcher"}),

    -- Show/hide
    awful.key({ modkey, "Shift" }, "x", function()
        crosshair:toggle()
    end, { description = "toggle crosshair overlay", group = "crosshair" }),

    awful.key({ modkey, "Shift" }, "w", function()
		awful.util.spawn_with_shell("$HOME/.config/awesome/misc/scripts/wall.sh")
	end),

	awful.key({ modkey, "Shift" }, "F3", function()
		awful.util.spawn_with_shell("$HOME/.config/awesome/misc/scripts/switch-back.sh")
	end),

	awful.key({ modkey}, "F3", function()
		awful.util.spawn_with_shell("$HOME/.config/awesome/misc/scripts/both-main-monitors.sh")
	end),

		awful.key({ modkey}, "F4", function()
		awful.util.spawn_with_shell("xrandr --auto")
	end),

	awful.key({ modkey }, "Return", function()
		awful.spawn(user_likes.term)
	end,
    { description = "open terminal", group = "launcher" }),

    	awful.key({ modkey }, "e", function()
		awful.spawn(user_likes.files)
	end,
    { description = "open nemo", group = "launcher" }),

        	awful.key({ modkey }, "d", function()
		awful.spawn(user_likes.discord)
	end,
    { description = "open Discord", group = "launcher" }),

        	awful.key({ modkey }, "s", function()
		awful.spawn(user_likes.steam)
	end,
    { description = "open steam", group = "launcher" }),

	awful.key({ modkey }, "a", function()
		awful.spawn(user_likes.music)
	end,
    { description = "launch music client", group = "launcher" }),

	awful.key({ modkey }, "w", function()
		awful.spawn.with_shell(user_likes.web)
	end,
    { description = "open web browser", group = "launcher" }),

    awful.key({ modkey }, "z", function()
        app_launcher:toggle()
        awesome.emit_signal("launcher::toggled", true)
    end, { description = "open launcher", group = "launcher" }),

	awful.key({ modkey }, "r", function()
        awful.util.spawn_with_shell("$HOME/.config/awesome/misc/scripts/picker", false)
	end,
    { description = "exec color picker", group = "launcher" }),

	awful.key({ modkey }, "c", function()
        cc_toggle(screen.primary)
	end,
    { description = "toggle control center", group = "launcher" }),

	awful.key({ modkey }, "x", function()
		dd_toggle(screen.primary)
	end,
	   { description = "open dashboard", group = "launcher" }),

	awful.key({ modkey }, "'", function()
        term_scratch_pad:toggle()
	end,
    { description = "toggle scratchpad", group = "launcher" }),

	awful.key({ modkey }, "l", function()
	       awful.spawn.with_shell("betterlockscreen -l blur")
	end,
	   { description = "show lockscreen", group = "launcher" }),

})



-- ESC to close control center and dashboard
awful.keyboard.append_global_keybindings({
    awful.key({}, "Escape", function()
        if control_c.visible then
            control_hide()
        elseif dashbaord_d.visible then
            dashbaord_d.visible = false
            awesome.emit_signal("dashboard::visible", false)
        end
    end,
    { description = "close control center or dashboard", group = "launcher" }),
})

-- control/media

awful.keyboard.append_global_keybindings({

    awful.key({}, "XF86MonBrightnessUp",  function()
            brightness.up()
        end,
        {description = "increase brightness", group = "control"}),


        awful.key({}, "XF86MonBrightnessDown", function()
            brightness.down()
        end,
        {description = "decrease brightness", group = "control"}),

    -- nightlight: cycle auto -> off -> hold(current) -> auto
    awful.key({ modkey }, "n", function()
            nightlight.toggle()
            local notify = require("layout.ding.extra.short")
            if notify then
                local s = nightlight.status_line()
                local on = s ~= "off"
                notify(on and "" or "", "Night Light " .. s)
            end
        end,
        {description = "nightlight: cycle auto/off/hold", group = "control"}),

    -- nightlight presets
    awful.key({ modkey, shift }, "n", function()
            nightlight.set_temp(1900)
        end,
        {description = "nightlight: hold 1900K (candle)", group = "control"}),

    awful.key({ modkey, shift }, "m", function()
            nightlight.set_temp(4500)
        end,
        {description = "nightlight: hold 4500K", group = "control"}),

    -- nightlight: purge cache + kill competing sct + gamma -> 6500K.
    -- Use when the screen gets stuck at a stale temperature.
    awful.key({ modkey, ctrl }, "n", function()
            nightlight.reset()
        end,
        {description = "nightlight: reset (kill sct, 6500K)", group = "control"}),

    -- nightlight: full re-init -- reset() + start() + immediate apply.
    -- Use when the curve is stuck, the timer died, or after sleep/suspend.
    awful.key({ modkey, alt }, "n", function()
            nightlight.init()
        end,
        {description = "nightlight: re-initialize", group = "control"}),

    -- ICC profile: re-apply dispwin to all matched outputs.
    awful.key({ modkey, ctrl }, "i", function()
            icc.reload("keybind")
        end,
        {description = "icc: reload calibration profile", group = "control"}),


    awful.key({modkey}, "Print", function()
        awful.util.spawn_with_shell("$HOME/.config/awesome/misc/scripts/ss full", false)
    end,
    {description = "screenshot", group = "control"}),

    awful.key({ modkey, shift }, "s", function()
        awful.util.spawn_with_shell("$HOME/.config/awesome/misc/scripts/ss area", false)
    end,
    { description = "screenshot area", group = "launcher" }),


    awful.key({}, "XF86AudioRaiseVolume",
        function()
            awful.spawn("amixer -D pulse set Master 2.5%+", false)
            awesome.emit_signal("volume::changed", 2.5)
        end,
        {description = "increase volume", group = "control"}),

    awful.key({}, "XF86AudioLowerVolume",
        function()
            awful.spawn("amixer -D pulse set Master 2.5%-", false)
            awesome.emit_signal("volume::changed", -2.5)
        end,
        {description = "decrease volume", group = "control"}),

    awful.key({}, "XF86AudioMute", function()
        awful.spawn("amixer -D pulse set Master toggle", false)
        awful.spawn.easy_async_with_shell("amixer -D pulse get Master | grep -o '\\[on\\]\\|\\[off\\]'", function(out)
            awesome.emit_signal("volume::muted", out:match("\\[on\\]") ~= nil)
        end)
    end,
    {description = "mute volume", group = "control"}),


    awful.key({modkey }, "F2", function()
        misc.musicMenu()
    end,
    {description = "screenshot", group = "control"}),

        awful.key({}, "XF86AudioPlay",
        function()
            awful.spawn("playerctl play-pause", false)
        end,
        { description = "play/pause", group = "media" }
    ),

    awful.key({}, "XF86AudioNext",
        function()
            awful.spawn("playerctl next", false)
        end,
        { description = "next", group = "media" }
    ),

    awful.key({}, "XF86AudioPrev",
        function()
            awful.spawn("playerctl previous", false)
        end,
        { description = "previous", group = "media" }
    )

})



-- awesome yeah!
awful.keyboard.append_global_keybindings({

    awful.key({ modkey },       "F1",      hotkeys_popup.show_help,
              {description="show this help window", group="awesome"}),

    awful.key({ modkey, ctrl }, "r", awesome.restart,
              {description = "reload awesome", group = "awesome"}),

    awful.key({ modkey, shift }, "c", awesome.restart,
              {description = "reload awesome", group = "awesome"}),

    awful.key({ modkey, shift }, "e", awesome.quit,
              {description = "quit awesome", group = "awesome"}),

    awful.key({ modkey, shift }, "q", function ()
        awful.util.spawn_with_shell("systemctl poweroff", false)
    end,
    {description = "power off system", group = "awesome"}),

    awful.key({ modkey, shift }, "r", function ()
        awful.util.spawn_with_shell("systemctl reboot", false)
    end,
    {description = "reboot system", group = "awesome"}),

    -- awful.key({ modkey }, "v", function () require("mods.exit-screen") awesome.emit_signal('module::exit_screen:show') end,
    --           {description = "show exit screen", group = "modules"}),

})

-- Tags related keybindings
awful.keyboard.append_global_keybindings({
    awful.key({ modkey }, "Escape", awful.tag.history.restore,
              {description = "go back", group = "tags"}),
})

-- Focus related keybindings
awful.keyboard.append_global_keybindings({
    awful.key({ modkey }, "Left",
        function ()
            awful.client.focus.bydirection("left")
            bling.module.flash_focus.flashfocus(client.focus)
        end,
    {description = "focus left", group = "client"}),


    awful.key({ modkey }, "Right",
        function ()
            awful.client.focus.bydirection("right")
            bling.module.flash_focus.flashfocus(client.focus)
        end,
    {description = "focus right", group = "client"}),


    awful.key({ modkey, ctrl }, "j", function ()
        awful.screen.focus_relative( 1)
    end,
    {description = "focus the next screen", group = "screen"}),


    awful.key({ modkey, ctrl }, "k", function ()
        awful.screen.focus_relative(-1)
    end,
    {description = "focus the previous screen", group = "screen"}),


    awful.key({ modkey, ctrl }, "n",
              function ()
                  local c = awful.client.restore()
                  if c then
                    c:activate { raise = true, context = "key.unminimize" }
                  end
              end,
    {description = "restore minimized", group = "client"}),
})


-- Layout related keybindings
awful.keyboard.append_global_keybindings({

    awful.key({ modkey, shift   }, "d", function () awful.client.swap.byidx(  1)                end,
              {description = "swap with next client by index", group = "client"}),

    awful.key({ modkey, shift   }, "a", function () awful.client.swap.byidx( -1)                end,
              {description = "swap with previous client by index", group = "client"}),

    awful.key({ modkey,           }, "u", awful.client.urgent.jumpto,
              {description = "jump to urgent client", group = "client"}),

    awful.key({ modkey, shift   }, "l",     function () awful.tag.incmwfact( 0.05)            end,
              {description = "increase master width factor", group = "layout"}),

    awful.key({ modkey,           }, "h",     function () awful.tag.incmwfact(-0.05)            end,
              {description = "decrease master width factor", group = "layout"}),

    awful.key({ modkey, shift   }, "h",     function () awful.tag.incnmaster( 1, nil, true)     end,
              {description = "increase the number of master clients", group = "layout"}),

    awful.key({ modkey, shift   }, "l",     function () awful.tag.incnmaster(-1, nil, true)     end,
              {description = "decrease the number of master clients", group = "layout"}),

    awful.key({ modkey, ctrl }, "h",     function () awful.tag.incncol( 1, nil, true)           end,
              {description = "increase the number of columns", group = "layout"}),

    awful.key({ modkey, ctrl }, "l",     function () awful.tag.incncol(-1, nil, true)           end,
              {description = "decrease the number of columns", group = "layout"}),

    awful.key({ modkey,           }, "space", function () awful.layout.inc( 1)                  end,
              {description = "select next", group = "layout"}),

    awful.key({ modkey, shift   }, "space", function () awful.layout.inc(-1)                    end,
              {description = "select previous", group = "layout"}),


    -- layout machi
	awful.key({ modkey }, ".", function()
		lmachi.default_editor.start_interactive()                                               end,
    { description = "edit current layout", group = "layout" }),

	awful.key({ modkey, shift }, ".", function()
		lmachi.switcher.start(client.focus)                                                     end,
    { description = "switch between windows for a machi layout", group = "layout" }),

})




-- tag related keys
awful.keyboard.append_global_keybindings({
    awful.key {
        modifiers   = { modkey },
        keygroup    = "numrow",
        description = "only view tag",
        group       = "tag",
        on_press    = function (index)
            local screen = awful.screen.focused()
            local tag = screen.tags[index]
            if tag then
                tag:view_only()
            end
        end,
    },

    awful.key {
        modifiers   = { modkey, ctrl },
        keygroup    = "numrow",
        description = "toggle tag",
        group       = "tag",
        on_press    = function (index)
            local screen = awful.screen.focused()
            local tag = screen.tags[index]
            if tag then
                awful.tag.viewtoggle(tag)
            end
        end,
    },

    awful.key {
        modifiers = { modkey, shift },
        keygroup    = "numrow",
        description = "move focused client to tag",
        group       = "tag",
        on_press    = function (index)
            if client.focus then
                local tag = client.focus.screen.tags[index]
                if tag then
                    client.focus:move_to_tag(tag)
                end
            end
        end,
    },

    awful.key {
        modifiers   = { modkey, ctrl, shift },
        keygroup    = "numrow",
        description = "toggle focused client on tag",
        group       = "tag",
        on_press    = function (index)
            if client.focus then
                local tag = client.focus.screen.tags[index]
                if tag then
                    client.focus:toggle_tag(tag)
                end
            end
        end,
    },

    awful.key {
        modifiers   = { modkey },
        keygroup    = "numpad",
        description = "select layout directly",
        group       = "layout",
        on_press    = function (index)
            local t = awful.screen.focused().selected_tag
            if t then
                t.layout = t.layouts[index] or t.layout
            end
        end,
    }
})


-- mouse mgmt
client.connect_signal("request::default_mousebindings", function()
    awful.mouse.append_client_mousebindings({

        awful.button({ }, 1, function (c)
            c:activate { context = "mouse_click" }
        end),

        awful.button({ modkey }, 1, function (c)
            c:activate { context = "mouse_click", action = "mouse_move"  }
        end),

        awful.button({ modkey }, 3, function (c)
            c:activate { context = "mouse_click", action = "mouse_resize"}
        end),

    })
end)

-- client mgmt
client.connect_signal("request::default_keybindings", function()
    awful.keyboard.append_client_keybindings({
        awful.key({ modkey,           }, "f",
            function (c)
                c.fullscreen = not c.fullscreen
                c:raise()
            end,
        {description = "toggle fullscreen", group = "client"}),

		awful.key({ alt }, "Tab", function()
			awesome.emit_signal("window_switcher::turn_on")
		end,
        {description = "switch between windows", group = "client"}),

		awful.key({ modkey }, "Tab", function()
			awesome.emit_signal("window_switcher::turn_on")
		end,
        {description = "switch between windows", group = "client"}),

        awful.key({ modkey }, "q",      function (c) c:kill() end,
                {description = "close", group = "client"}),

        awful.key({ modkey }, "x",  awful.client.floating.toggle,
                {description = "toggle floating", group = "client"}),


        awful.key({ modkey, ctrl }, "Return", function (c) c:swap(awful.client.getmaster()) end,
                {description = "move to master", group = "client"}),


        awful.key({ modkey,           }, "o",      function (c) c:move_to_screen()               end,
                {description = "move to screen", group = "client"}),


        awful.key({ modkey,           }, "t",      function (c) c.ontop = not c.ontop            end,
                {description = "toggle keep on top", group = "client"}),


        awful.key({ modkey,           }, "n",
            function (c)
                c.minimized = true
            end ,
        {description = "minimize", group = "client"}),


        awful.key({ modkey,           }, "g",
            function (c)
                c.maximized = not c.maximized
                c:raise()
            end ,
        {description = "(un)maximize", group = "client"}),

    })

end)
