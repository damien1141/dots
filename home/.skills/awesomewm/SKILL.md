---
name: awesomewm
description: Configure AwesomeWM, an asynchronous window manager. Use when editing rc.lua, tags, layouts, widgets, or rules. Requires non-blocking, interruptible UI updates and defensive handling of missing themes and rapidly firing signals.
argument-hint: <project-context>
---

## 1. Animation & Rubato Integration
Rubato is the standard for AwesomeWM animations, but it requires careful handling to prevent UI collapse.

- **The `NaN` Trap:** If a `rubato` animation is interrupted (e.g., rapid hovering or tag switching), it can momentarily yield `NaN`, `inf`, or negative numbers. 
  - **Never** pass `pos` directly to a widget dimension (`forced_height`, etc.). 
  - **Never** rely on `math.max()` or `math.min()` to filter `NaN`. In Lua, `math.max(10, NaN)` returns `NaN`.
  - **Correct Clamp:** `if pos and pos == pos and pos > 0 then ... end` (because `NaN ~= NaN` in Lua).
- **Initialize Target & Pos:** Always initialize `rubato.timed` with BOTH `pos = initial_value` and `target = initial_value`. If you only set `pos`, the default `target` is `0`. If an update fires before the animation fully initializes, the widget will animate to `0` and disappear.
- **No Timers for Transitions:** Never use `gears.timer` to delay UI state changes (e.g., waiting 0.1s to fade a button out after release). Instead, instantly set the `rubato.target` to the new state and let the easing library handle the smooth transition natively.
- **Destroy Timers on Widget Death:** If you must use `gears.timer` (e.g., bling task preview delays), ensure they are stopped or collected when the widget is destroyed to prevent memory leaks and signals firing on dead widgets.

## 2. Layout & Widget Architecture
Dynamic sizing (animations) inside fixed layouts causes the entire bar/widget to shift and jump.

- **Fixed Wrappers for Dynamic Children:** If a child widget animates its size (e.g., a pill growing from 10px to 32px), it must be placed inside a wrapper with a `forced_height` and `forced_width` equal to the *maximum* possible size of the child. 
  - Use `wibox.container.place` as this wrapper. It keeps the animated child centered without altering the parent layout's geometry.
- **Asymmetric Transitions:** When a widget goes from State A (10px) to State B (32px), the animation will look smoother if you use asymmetric timings or `intro` values so the "grow" and "shrink" don't look identical.
- **Font Bounding Boxes:** Do not animate the `margins` of `wibox.container.margin` around text or icon fonts. Shrinking the bounding box of a text glyph will cause AwesomeWM to distort it into an ellipse or wrap it. Animate opacity or background colors instead of physical text size.

## 3. Performance & Memory
AwesomeWM runs on a single thread. Bad UI code will lock up the entire window manager.

- **Never `collectgarbage("collect")` in callbacks:** Never call `collectgarbage("collect")` inside `update_callback`, `create_callback`, or signal handlers. This forces a global GC pause and causes severe stuttering/lag on hover or focus changes. Let Lua's incremental GC handle it.
- **Avoid Deep `get_children_by_id` in Hot Loops:** `get_children_by_id` is expensive. In `update_callback`, if you need to manipulate a child, cache the reference in `create_callback` (e.g., `self.my_bg = self:get_children_by_id("background_role")[1]`) and access `self.my_bg` during updates.
- **Signal Safety:** Always check if the client or tag still exists before running heavy logic in a signal callback.

## 4. Lua & AwesomeWM Quirks
- **Global vs Local Helpers:** Users often define helper functions globally in `rc.lua` (e.g., `colorizeText()`) rather than namespaced in a `helpers` module. If `helpers.colorizeText` throws a nil error, try the global version.
- **Color Strings:** AwesomeWM accepts 8-digit hex colors (`#RRGGBBAA`) for opacity. Use this for soft glows (e.g., `.. "33"` or `.. "1A"`) instead of animating opacity directly if you want to save CPU cycles.
- **Theme Fallbacks:** Always provide fallbacks for `beautiful` variables: `beautiful.accent or "#8AB4F8"`. If a theme fails to load, widgets will crash the WM otherwise.
- **DPI Consistency:** Always scale sizes using `dpi()`. Never hardcode pixel values, as they will look wrong on HiDPI displays.

## 5. Standard Widget Template Pattern
When building `awful.widget.taglist` or `tasklist`, use this structural pattern:

```lua
widget_template = {
    {
        id = "background_role",
        widget = wibox.container.background,
    },
    -- Wrapper to absorb size changes
    widget = wibox.container.place,
    forced_height = dpi(40), 
    forced_width = dpi(10),
    
    create_callback = function(self, c3, index, objects)
        -- 1. Fetch child safely
        local bg = self:get_children_by_id("background_role")[1]
        if not bg then return end
        
        -- 2. Set initial state
        local h = get_height(c3)
        bg.forced_height = h
        
        -- 3. Initialize Rubato safely (pos + target + NaN clamp)
        self.anim = rubato.timed{
            pos = h, target = h,
            subscribed = function(pos)
                if pos and pos == pos and pos > 0 then
                    bg.forced_height = math.max(dpi(6), math.min(pos, dpi(40)))
                end
            end
        }
    end,
    
    update_callback = function(self, c3, index, objects)
        -- 1. Update colors instantly
        -- 2. Glide to new height using self.anim.target
    end
}
```
