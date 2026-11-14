-- Window rules: what floats, where it opens, what stays translucent.
-- Game rules are in game.lua.

-- Dialogs, pickers and small tools float, centred.
local floating = {
    { name = "dialogs", match = { modal = true } },
    { name = "file-pickers", match = { title = "^(Open|Save|Choose|Select|Export|Import)( .*)?$" } },
    { name = "portal-pickers", match = { class = "^(xdg-desktop-portal-gtk|org\\.freedesktop\\.impl\\.portal\\..*)$" } },
    { name = "polkit", match = { class = "^(hyprpolkitagent|org\\.hyprland\\.polkitagent)$" } },
    { name = "settings-tools", match = { class = "^(nm-connection-editor|blueman-manager|pavucontrol|org\\.pulseaudio\\.pavucontrol|nwg-displays|qt6ct|kvantummanager|system-config-printer)$" } },
    { name = "small-apps", match = { class = "^(org\\.gnome\\.Calculator|gnome-calculator|org\\.gnome\\.FileRoller|file-roller|hyprland-dialog|hyprland-share-picker)$" } },
    { name = "forge-small", match = { class = "^org\\.forgeos\\.(thermal|themekit|shot)$" } },
    { name = "installer", match = { class = "^(calamares|io\\.calamares\\.calamares)$" } },
    { name = "steam-dialogs", match = { class = "^steam$", title = "^(Steam Settings|Friends List|Steam - News.*|Special Offers|Product Activation|Install - .*)$" } },
}
for _, r in ipairs(floating) do
    hl.window_rule({ name = "float-" .. r.name, match = r.match, float = true, center = true, tag = "+forge-float" })
end

-- Picture in picture: small, on top, in the corner, on every workspace.
hl.window_rule({
    name = "pip",
    match = { title = "^(Picture[- ]in[- ][Pp]icture)$" },
    float = true, pin = true, keep_aspect_ratio = true,
    size = "30% 30%", move = "69% 68%",
})

-- Forge apps paint their own translucent glass; keep it (never opaque) and
-- give them the theme's corners.
hl.window_rule({
    name = "forge-apps",
    match = { class = "^org\\.forgeos\\..*$" },
    tag = "+forge",
    opaque = false,
})

-- XWayland drag-and-drop helper windows mustn't take focus.
hl.window_rule({
    name = "xwayland-drags",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})

-- Apps asking to be maximised get it only when they ask again later; a
-- new window shouldn't jump to fill the screen on its own.
hl.window_rule({ name = "no-auto-maximise", match = { class = ".*" }, suppress_event = "maximize" })
