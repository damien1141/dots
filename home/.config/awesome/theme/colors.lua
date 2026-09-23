-- Awe-... colors
-----------------
-- Copyleft © 2022 Saimoomedits

-- default color pallate: "Awesthetic pro - Dark Frosted"


local colors = {}

-- foreground color
colors.foreground      = "#ccd0d9"

-- backgrounds (Solid - for bars and non-blurred widgets)
colors.bg_color         = "#0F0F11"
colors.bg_2             = "#1a1a1d"
colors.bg_3             = "#212125"

-- backgrounds (Frosted - for dashboards, popups, and control centers)
-- These alpha channels (CC, B3, 99) trigger the picom blur perfectly 
-- without being so transparent that you can't read the text.
colors.bg_transparent   = "#0F0F11EE" -- 80% opacity (Best for main dashboards)
colors.bg_frost_2       = "#1a1a1dd3" -- 70% opacity (Best for inner cards/widgets inside the dashboard)
colors.bg_frost_3       = "#21212599" -- 60% opacity (Best for sliders/hover states inside the dashboard)

-- base green
colors.green   = "#589979"
colors.green_2 = colors.green .. "99"
colors.green_3 = "#19502a"

-- base red
colors.red     = "#9C474C"
colors.red_2    = "#F85E4D"
colors.red_3 = "#F9DEDC"

-- base black
colors.black   = "#000000"
colors.ext_white_bg = "#EBF0FF"

-- accents
colors.accent         = "#8AB4F8"
colors.accent_2       = colors.accent .. "66"
colors.accent_3       = "#8AB4F8"

-- accents (Frosted - slightly more opaque so they pop against the blurred dark glass)
colors.accent_transparent = "#8AB4F899" -- 60% opacity (Perfect for active toggles/blurred sliders)

return colors