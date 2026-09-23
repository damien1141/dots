-- rules
--------
-- Copyleft © 2022 Saimoomedits


-- requirements
-- ~~~~~~~~~~~~
local awful = require("awful")
local beautiful = require("beautiful")
local ruled = require("ruled")

-- Configurations
-- ~~~~~~~~~~~~~~

-- connect to signal
ruled.client.connect_signal("request::rules", function()

    -- Global
    ruled.client.append_rule {
        id = "global",
        rule = {},
        properties = {
            focus               = awful.client.focus.filter,
            raise               = true,
            size_hints_honor    = false,
            screen              = awful.screen.preferred,
            titlebars_enabled   = true,
            placement           = awful.placement.centered + awful.placement.no_overlap + awful.placement.no_offscreen
        }
    }

    -- tasklist order
    ruled.client.append_rule {
        id          = "tasklist_order",
        rule        = {},
        properties  = {},
        callback    = awful.client.setslave
    }

    -- Floating
    ruled.client.append_rule {
        id          = "floating",
        rule_any    = {
            class   = {"Sxiv", "Zathura", "Galculator", "Xarchiver", "amberol"},
            role    = { "pop-up"},
            instance    = {"spad","music","blueberry"}
        },
        properties      = {floating = true, placement = awful.placement.centered}
    }

    -- Betterbird to Tag 9
    ruled.client.append_rule {
        id = "betterbird_tag_9",
        rule_any = {
            class = { "Thunderbird", "thunderbird-esr", "thunderbird", "Betterbird", "betterbird", "betterbird-esr" }
        },
        properties = {
            tag = "9" -- change to the exact string name of your 9th tag if it isn't literally "9"
        }
    }

    -- Librewolf to Tag 1
    ruled.client.append_rule {
        id = "librewolf_tag_1",
        rule_any = {
            class = { "Librewolf", "librewolf" }
        },
        properties = {
            tag = "1" -- change to the exact string name of your 9th tag if it isn't literally "9"
        }
    }

    -- gram to Tag 2
    ruled.client.append_rule {
        id = "gram_tag_2",
        rule_any = {
            class = { "Gram", "gram" }
        },
        properties = {
            tag = "2" -- change to the exact string name of your 9th tag if it isn't literally "9"
        }
    }

    -- Borders
    ruled.client.append_rule {
        id = "borders",
        rule_any = {type = {"normal", "dialog"}},
        except_any = {
            role = {"Popup"},
            type = {"splash"},
            name = {"^discord.com is sharing your screen.$"}
        },
        properties = {
            border_width = beautiful.border_width,
        }
    }

    -- Center Placement
    ruled.client.append_rule {
        id = "center_placement",
        rule_any = {
            type = {"dialog"},
            class = {"Steam", "discord", "markdown_input", "nemo", "thunar" },
            instance = {"markdown_input",},
            role = {"GtkFileChooserDialog"}
        },
        properties = {placement = awful.placement.center}
    }

    -- Titlebar rules
    ruled.client.append_rule {
        id = "titlebars",
        rule_any = {
            type = {
            "dialog",
            "splash"
        },
        name = {
            "^discord.com is sharing your screen.$",
            "file_progress"
        },
				class = {
                        "spad",
						"amberol"
				}
    },
        properties = {titlebars_enabled = false}
    }
    end)


    -- Music client
    ruled.client.append_rule {
        rule_any = {class = {"music"}, instance = {"music"}},
        properties = {
            floating = true,
            width = 700,
			height = 444,
			x = 650,
			y = 500
        },

}

-- Split-Screen Magic: Snap todo_edit to left side
ruled.client.append_rule {
    id = "todo_edit_split",
    rule = { class = "todo_edit" },
    properties = {
        floating = true,
        border_width = 0,
        placement = function(c)
            -- Snap to the left, leaving room for the dashboard and gaps
            awful.placement.left(c, {margins = beautiful.useless_gap * 2})
            local s = c.screen
            local dash_width = beautiful.xresources.apply_dpi(430)
            c.width = s.geometry.width - dash_width - (beautiful.useless_gap * 4)
            c.height = s.geometry.height - (beautiful.useless_gap * 4)
        end
    }
}

-- -- hide titlebar for tiled/maxed
-- screen.connect_signal("arrange", function(s)
--   local layout = s.selected_tag.layout.name
--   for _, c in pairs(s.clients) do
--     if c.maximized or c.fullscreen then
--       awful.titlebar.hide(c)
--       c.border_width = 0
--     elseif layout == "floating" or c.floating then
--       awful.titlebar.show(c)
--       c.border_width = 0
--     else
--       awful.titlebar.hide(c)
--       c.border_width = beautiful.border_width
--     end
--   end
-- end)
