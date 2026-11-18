-- What starts with the session. Most of it runs as systemd user services
-- (uwsm starts graphical-session.target): the polkit agent, idle and lock,
-- the clipboard history, auto-mounting, the wallpaper, Forge's shell. Apps'
-- own autostart entries (/etc/xdg/autostart) run through uwsm too.
-- forge-session-start covers the rest: the session's environment for D-Bus
-- activated services, the cursor, and the theme for GTK and Qt apps.
hl.on("hyprland.start", function()
    hl.exec_cmd("forge-session-start")
end)
