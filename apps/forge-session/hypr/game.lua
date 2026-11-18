-- Games: full screen, tearing allowed (lower latency), never idle, and the
-- desktop's effects off while one is full screen.
--
-- A window counts as a game when it says so (the content-type protocol),
-- when it's a Steam game or gamescope, a Windows game under Wine/Proton,
-- or one of Forge Arcade's games.
local GAMES = "^(steam_app_[0-9]+|gamescope|.*\\.exe|port-calder|hardlight|bramble-bound|orbit-golf"
    .. "|prism-smash|lumen-drift|relic-runner|ember-isle|nova-lancer|deep-delve)$"

local effects = {
    tag = "+game",
    immediate = true,          -- tearing: frames reach the screen at once
    idle_inhibit = "fullscreen",
    no_blur = true,
    no_shadow = true,
    render_unfocused = true,   -- keeps rendering behind an overlay
}
local by_class = { name = "games", match = { class = GAMES } }
local by_content = { name = "games-content", match = { content = "game" } }
for k, v in pairs(effects) do by_class[k] = v; by_content[k] = v end
hl.window_rule(by_class)
hl.window_rule(by_content)

-- While a game is full screen on the active workspace: blur, shadows and
-- animations off, and forge-game pauses the live wallpaper and switches the
-- thermal profile (it puts both back afterwards).
local active = false

local function is_game(win)
    if type(win.tags) ~= "table" then return false end
    for _, tag in ipairs(win.tags) do
        if tag == "game" or tag == "game*" then return true end
    end
    return false
end

local function update()
    local ws = hl.get_active_workspace()
    local fs = ws and ws.has_fullscreen and ws.fullscreen_window
    local on = (fs and is_game(fs)) and true or false
    if on == active then return end
    active = on
    local t = forge.theme
    hl.config({
        decoration = {
            blur = { enabled = not on },
            shadow = { enabled = (not on) and t.shadow > 0 },
        },
        animations = { enabled = not on },
    })
    hl.exec_cmd("forge-game " .. (on and "fullscreen-on" or "fullscreen-off"))
end

for _, event in ipairs({ "window.fullscreen", "window.active", "window.destroy", "workspace.active" }) do
    hl.on(event, function() update() end)
end

forge.game = { update = update, is_active = function() return active end }
