-- Your Hyprland config.
--
-- Forge OS's defaults come first, from /usr/share/forge/hypr (updated with
-- the system; read them to see what's set). Then, from this folder, if they
-- exist: monitors.lua and keybinds.user.lua (Forge Settings writes those)
-- and user.lua, for your own settings. They load last, so they win.
--
-- Updates never change this file.
require("/usr/share/forge/hypr/forge.lua")
forge.load_user()
