-- Keyboard, mouse and touchpad. The keyboard layout is the one chosen in
-- the installer (Calamares writes it for X11; Hyprland doesn't read that,
-- so it's read here). Forge Settings writes its own choice to
-- ~/.config/hypr/input.user.lua, which loads later and wins.
local xkb = { layout = "us", variant = "", model = "", options = "" }
local f = io.open("/etc/X11/xorg.conf.d/00-keyboard.conf", "r")
if f then
    for line in f:lines() do
        local key, value = line:match('Option%s+"Xkb(%a+)"%s+"([^"]*)"')
        if key then xkb[key:lower()] = value end
    end
    f:close()
end

hl.config({
    input = {
        kb_layout = xkb.layout,
        kb_variant = xkb.variant,
        kb_model = xkb.model,
        kb_options = xkb.options,
        numlock_by_default = true,
        repeat_delay = 300,
        repeat_rate = 30,
        -- Click to focus, as on Windows and macOS; scrolling still reaches
        -- the window under the pointer.
        follow_mouse = 2,
        float_switch_override_focus = 0,
        sensitivity = 0,
        accel_profile = "adaptive",
        touchpad = {
            natural_scroll = true,
            tap_to_click = true,
            disable_while_typing = true,
            clickfinger_behavior = true,
            scroll_factor = 0.8,
        },
    },
})

-- Three fingers left or right: the next or previous workspace.
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
