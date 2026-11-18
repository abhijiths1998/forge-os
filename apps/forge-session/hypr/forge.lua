-- Forge OS defaults for Hyprland.
--
-- Shipped by the forge-session package and replaced on every update: don't
-- edit this. ~/.config/hypr/hyprland.lua loads it, then ~/.config/hypr/user.lua,
-- where your own settings go (they win, since they come later).
--
-- The global `forge` table holds the helpers the modules share, so user.lua
-- can use them too (forge.bind, forge.exec, forge.tiling...).
local DIR = "/usr/share/forge/hypr"

forge = forge or {}
forge.dir = DIR
forge.home = os.getenv("HOME") or ""
forge.config = os.getenv("XDG_CONFIG_HOME") or (forge.home .. "/.config")
forge.state = os.getenv("XDG_STATE_HOME") or (forge.home .. "/.local/state")
forge.json = require(DIR .. "/lib/json.lua")

local binds = require(DIR .. "/lib/bind.lua")
forge.bind = binds.bind
forge.submap = binds.submap_define
forge.binds = binds

-- True when an executable is on PATH (binds for apps that aren't
-- installed yet are left out, so every listed shortcut works).
local path_cache = {}
function forge.has(cmd)
    if path_cache[cmd] == nil then
        path_cache[cmd] = os.execute("command -v '" .. cmd .. "' >/dev/null 2>&1") == true
    end
    return path_cache[cmd]
end

-- A dispatcher that runs a command.
function forge.exec(cmd)
    return hl.dsp.exec_cmd(cmd)
end

-- A short on-screen hint (submaps use it). Forge's shell shows its own
-- badge too; this one works without it.
local hint
function forge.hint(text, ms)
    if hint then pcall(function() hint:dismiss() end) end
    hint = hl.notification.create({ text = text, timeout = ms or 0, font_size = 14 })
end
function forge.unhint()
    if hint then pcall(function() hint:dismiss() end) end
    hint = nil
end

-- The modules, in order. Each is a plain file you can read to see what
-- Forge sets; user.lua can undo any of it.
for _, name in ipairs({ "env", "theme", "look", "input", "rules", "tiling", "game", "keybinds", "autostart" }) do
    require(DIR .. "/" .. name .. ".lua")
end

-- The user's files from ~/.config/hypr, in order; called by the user's
-- hyprland.lua after this file.
function forge.load_user()
    for _, name in ipairs({ "monitors.lua", "input.user.lua", "keybinds.user.lua", "user.lua" }) do
        local path = forge.config .. "/hypr/" .. name
        local f = io.open(path, "r")
        if f then
            f:close()
            require(path)
        end
    end
end
