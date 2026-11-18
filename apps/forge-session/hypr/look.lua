-- Forge Glass on Hyprland: frosted translucent windows with rounded,
-- squircle corners, a soft lit edge, a deep soft shadow, gentle animations.
local t = forge.theme

hl.config({
    general = {
        gaps_in = 5,
        gaps_out = { top = 8, right = 12, bottom = 12, left = 12 },
        border_size = t.edge_width,
        col = {
            active_border = t.edge_active,
            inactive_border = t.edge_inactive,
        },
        -- Grab any window edge to resize it, as on Windows and macOS.
        resize_on_border = true,
        extend_border_grab_area = 12,
        hover_icon_on_border = true,
        -- Games may tear (rules.lua lets them); nothing else does.
        allow_tearing = true,
        layout = "dwindle",
    },

    decoration = {
        rounding = t.cornerRadius,
        rounding_power = t.cornerShape,
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        dim_inactive = false,
        shadow = {
            enabled = t.shadow > 0,
            range = 28,
            render_power = 3,
            offset = { 0, 8 },
            color = t.shadow_colour,
        },
        blur = {
            enabled = true,
            size = t.blur_size,
            passes = t.blur_passes,
            vibrancy = t.vibrancy,
            vibrancy_darkness = 0.2,
            noise = t.noise,
            contrast = 0.95,
            brightness = 0.9,
            -- Frost whatever is translucent, menus and popups included.
            ignore_opacity = true,
            popups = true,
            new_optimizations = true,
            xray = false,
        },
    },

    animations = { enabled = true },

    dwindle = { preserve_split = true, force_split = 2 },

    misc = {
        -- Hyprland's own wallpapers and logo are off: Forge has its own.
        force_default_wallpaper = 0,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        background_color = 0xff1b1d2b,
        mouse_move_enables_dpms = true,
        key_press_enables_dpms = true,
        focus_on_activate = true,
        enable_swallow = false,
        -- Readable config errors come from Forge (forge-session's notifier).
        disable_autoreload = false,
    },

    ecosystem = {
        -- A distribution handles updates and their news itself.
        no_update_news = true,
        no_donation_nag = true,
    },

    xwayland = { force_zero_scaling = true },

    cursor = { hide_on_key_press = false },
})

-- Calm, quick motion: windows pop in from 92%, workspaces slide.
hl.curve("forgeOut", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
hl.curve("forgeInOut", { type = "bezier", points = { { 0.65, 0 }, { 0.35, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("forgeSpring", { type = "spring", mass = 1, stiffness = 260, dampening = 26 })

hl.animation({ leaf = "global", enabled = true, speed = 8, bezier = "forgeOut" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4, spring = "forgeSpring", style = "popin 92%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2.5, bezier = "forgeOut", style = "popin 92%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4, spring = "forgeSpring" })
hl.animation({ leaf = "border", enabled = true, speed = 5, bezier = "forgeOut" })
hl.animation({ leaf = "fade", enabled = true, speed = 3, bezier = "forgeOut" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 3, bezier = "forgeOut", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 2, bezier = "linear", style = "fade" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "forgeInOut", style = "slide" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 4, bezier = "forgeOut", style = "slidevert" })

-- Forge's shell surfaces (bar, popups, panels, launcher) are frosted too.
hl.layer_rule({
    name = "forge-shell-glass",
    match = { namespace = "^(forge-.*|quickshell.*)$" },
    blur = true,
    blur_popups = true,
    ignore_alpha = 0.05,
})
hl.layer_rule({
    name = "forge-shell-desktop-no-anim",
    match = { namespace = "^forge-(wallpaper|desktop)$" },
    no_anim = true,
})
