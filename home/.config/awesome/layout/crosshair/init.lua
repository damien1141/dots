-- ~/.config/awesome/layout/crosshair/init.lua
local wibox = require("wibox")
local awful = require("awful")
local gears = require("gears")

local CrosshairOverlay = {}
CrosshairOverlay.__index = CrosshairOverlay

-- Bounding box for the crosshair wibox/widget
local SIZE = 200

-- Valorant color indices
local color_map = {
    [0] = "#FFFFFF", [1] = "#00FF00", [2] = "#7FFF00", [3] = "#DFFF00",
    [4] = "#FFFF00", [5] = "#00FFFF", [6] = "#FF00FF", [7] = "#FF0000"
}

-- Valorant code keys -> internal properties
local property_map = {
    c = "color", u = "colorCode", h = "outline", o = "outlineOpacity", t = "outlineThickness",
    d = "centerDot", a = "centerDotOpacity", z = "centerDotSize",
    ["0a"] = "innerLineOpacity", ["0l"] = "innerLineLength", ["0v"] = "innerLineVerticalLength", ["0g"] = "innerLineUnbindAxes",
    ["0t"] = "innerLineThickness", ["0o"] = "innerLineOffset",
    ["1b"] = "outerLines", ["1a"] = "outerLineOpacity", ["1l"] = "outerLineLength", ["1v"] = "outerLineVerticalLength", ["1g"] = "outerLineUnbindAxes",
    ["1t"] = "outerLineThickness", ["1o"] = "outerLineOffset",
}

local default_props = {
    color = 0, colorCode = "#FFFFFF",
    outline = false, outlineOpacity = 0.5, outlineThickness = 1,
    centerDot = false, centerDotOpacity = 1, centerDotSize = 2,
    innerLines = true, innerLineOpacity = 0.8, innerLineLength = 6, innerLineVerticalLength = 6,
    innerLineUnbindAxes = false, innerLineThickness = 2, innerLineOffset = 3,
    outerLines = true, outerLineOpacity = 0.35, outerLineLength = 2, outerLineVerticalLength = 2,
    outerLineUnbindAxes = false, outerLineThickness = 2, outerLineOffset = 10,
}

-- Helper to add alpha to hex colors
local function apply_opacity(hex, opacity)
    if type(opacity) ~= "number" then opacity = 1 end
    if opacity < 0 then opacity = 0 elseif opacity > 1 then opacity = 1 end
    hex = hex:gsub("#", "")
    if #hex == 6 then
        return "#" .. hex .. string.format("%02x", math.floor(opacity * 255))
    elseif #hex == 8 then
        local existing_alpha = tonumber(hex:sub(7, 8), 16) or 255
        return "#" .. hex:sub(1, 6) .. string.format("%02x", math.floor(existing_alpha * opacity))
    end
    return "#" .. hex
end

-- Draw a rectangle with an optional outline (outline drawn as an expanded rect behind)
local function draw_crosshair_part(cr, cx, cy, x, y, w, h, fill_color, outline_color, outline_width)
    if outline_width > 0 then
        cr:set_source(gears.color(outline_color))
        cr:rectangle(cx + x - outline_width, cy + y - outline_width, w + outline_width * 2, h + outline_width * 2)
        cr:fill()
    end
    cr:set_source(gears.color(fill_color))
    cr:rectangle(cx + x, cy + y, w, h)
    cr:fill()
end

-- Lazy default instance: lets class-level calls like
-- CrosshairOverlay:toggle() work without manual instantiation.
local default_instance
local function ensure_instance(self)
    if self and self.wibox then return self end
    if not default_instance then default_instance = CrosshairOverlay:new() end
    return default_instance
end

function CrosshairOverlay:new(code)
    local obj = setmetatable({}, CrosshairOverlay)
    obj.props = {}
    for k, v in pairs(default_props) do obj.props[k] = v end

    obj.widget = wibox.widget.base.make_widget(nil, nil, { enable_properties = true })

    function obj.widget:fit(_, _, _)
        return SIZE, SIZE
    end

    function obj.widget:draw(_, cr, width, height)
        local props = obj.props
        local cx, cy = width / 2, height / 2

        -- color 8 = custom code; guard against a missing `u` value
        local crosshair_color = color_map[props.color] or props.colorCode or "#FFFFFF"

        local bw = props.outline and props.outlineThickness or 0
        local out_color = apply_opacity("#000000", props.outlineOpacity)

        -- 1. Center Dot
        if props.centerDot then
            local dot_color = apply_opacity(crosshair_color, props.centerDotOpacity)
            draw_crosshair_part(cr, cx, cy, -props.centerDotSize / 2, -props.centerDotSize / 2,
                props.centerDotSize, props.centerDotSize, dot_color, out_color, bw)
        end

        -- 2. Inner Lines
        if props.innerLines then
            local line_color = apply_opacity(crosshair_color, props.innerLineOpacity)
            local off = props.innerLineOffset + 1
            if props.centerDot then off = off + props.centerDotSize / 2 end

            local thick, h_len, v_len = props.innerLineThickness, props.innerLineLength, props.innerLineVerticalLength
            draw_crosshair_part(cr, cx, cy, off, -thick / 2, h_len, thick, line_color, out_color, bw)              -- Right
            draw_crosshair_part(cr, cx, cy, -off - h_len, -thick / 2, h_len, thick, line_color, out_color, bw)     -- Left
            draw_crosshair_part(cr, cx, cy, -thick / 2, off, thick, v_len, line_color, out_color, bw)              -- Bottom
            draw_crosshair_part(cr, cx, cy, -thick / 2, -off - v_len, thick, v_len, line_color, out_color, bw)     -- Top
        end

        -- 3. Outer Lines
        if props.outerLines then
            local line_color = apply_opacity(crosshair_color, props.outerLineOpacity)
            local off = props.outerLineOffset + 1
            if props.centerDot then off = off + props.centerDotSize / 2 end

            local thick, h_len, v_len = props.outerLineThickness, props.outerLineLength, props.outerLineVerticalLength
            draw_crosshair_part(cr, cx, cy, off, -thick / 2, h_len, thick, line_color, out_color, bw)              -- Right
            draw_crosshair_part(cr, cx, cy, -off - h_len, -thick / 2, h_len, thick, line_color, out_color, bw)     -- Left
            draw_crosshair_part(cr, cx, cy, -thick / 2, off, thick, v_len, line_color, out_color, bw)              -- Bottom
            draw_crosshair_part(cr, cx, cy, -thick / 2, -off - v_len, thick, v_len, line_color, out_color, bw)     -- Top
        end
    end

    obj.wibox = wibox({
        ontop = true,
        visible = false,
        bg = "#00000000",
        input_passthrough = true,
        type = "splash",
        screen = awful.screen.focused() or screen.primary,
    })
    -- Belt and suspenders: constructor args aren't always applied as properties
    obj.wibox.input_passthrough = true
    obj.wibox.width = SIZE
    obj.wibox.height = SIZE
    obj.wibox:set_widget(obj.widget)

    obj:set_code(code)
    obj:center()

    return obj
end

function CrosshairOverlay:set_code(code)
    self = ensure_instance(self)
    -- Reset to defaults so values from a previous code don't leak in
    for k, v in pairs(default_props) do self.props[k] = v end

    if code and code ~= "" then
        local tokens = {}
        for tok in code:gmatch("[^;]+") do tokens[#tokens + 1] = tok end

        -- Valorant codes lead with a version token ("0"). If the token count
        -- is odd, the first token isn't part of a key;value pair -> drop it.
        -- Unknown keys (like "P") are simply skipped below.
        if #tokens % 2 == 1 then table.remove(tokens, 1) end

        for i = 1, #tokens - 1, 2 do
            local key, val = tokens[i], tokens[i + 1]
            local target = property_map[key]
            if target then
                if target == "colorCode" then
                    self.props[target] = "#" .. (val:gsub("^#", ""))
                elseif type(default_props[target]) == "boolean" then
                    self.props[target] = (val == "1" or val == "true")
                else
                    local num = tonumber(val)
                    if num then self.props[target] = num end
                end
            end
        end
    end

    -- Axis unbinding: vertical length is locked to horizontal unless unbound
    if not self.props.innerLineUnbindAxes then
        self.props.innerLineVerticalLength = self.props.innerLineLength
    end
    if not self.props.outerLineUnbindAxes then
        self.props.outerLineVerticalLength = self.props.outerLineLength
    end

    if self.widget then self.widget:emit_signal("widget::redraw_needed") end
end

-- Exact center of the CURRENT screen's full geometry (not the workarea,
-- so your bar doesn't push the crosshair off-center).
function CrosshairOverlay:center()
    self = ensure_instance(self)
    local s = awful.screen.focused() or self.wibox.screen or screen.primary
    self.wibox.screen = s
    local g = s.geometry
    self.wibox.x = g.x + math.floor((g.width - SIZE) / 2)
    self.wibox.y = g.y + math.floor((g.height - SIZE) / 2)
end

function CrosshairOverlay:toggle()
    self = ensure_instance(self)
    self.wibox.visible = not self.wibox.visible
    if self.wibox.visible then
        self.wibox.ontop = true
        self.wibox.input_passthrough = true
        self:center()
        self.widget:emit_signal("widget::redraw_needed")
    end
end

-- Convenience: CrosshairOverlay("0;c;5;...") works like :new()
setmetatable(CrosshairOverlay, {
    __call = function(_, ...) return CrosshairOverlay:new(...) end
})

return CrosshairOverlay