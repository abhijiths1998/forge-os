-- Every Forge shortcut. Each one has a category and a description: the
-- desktop shortcut panel, the Super+/ cheat sheet, the hold-Super popup
-- and Forge Settings read them from `hyprctl binds -j`.
--
-- Windows and macOS habits first. Change or add your own in
-- ~/.config/hypr/keybinds.user.lua (Forge Settings writes it) or user.lua:
--   hl.unbind("SUPER + B")
--   forge.bind("Apps", "SUPER + B", "Open Firefox", forge.exec("firefox"))
local bind, exec, has = forge.bind, forge.exec, forge.has
local snap = require(forge.dir .. "/lib/snap.lua")
local SUPER = "SUPER"

-- Forge's shell (forge-shell) draws the bar, panels and pickers; its keys
-- only exist when it's installed, so every shortcut listed works. They're
-- global shortcuts ("forge:<name>"), which reach the shell at once and tell
-- it when a key is let go.
local function shell(action) return hl.dsp.global("forge:" .. action) end
local SHELL = has("forge-shell")

-- Apps ----------------------------------------------------------------------
bind("Apps", "SUPER + Return", "Open terminal", exec("forge-open terminal"))
bind("Apps", "SUPER + SHIFT + Return", "Open backup terminal (foot)", exec("foot"))
bind("Apps", "SUPER + E", "Open files", exec("forge-open files"))
bind("Apps", "SUPER + B", "Open browser", exec("forge-open browser"))
bind("Apps", "SUPER + Space", "Open launcher", exec("forge-open launcher"))
bind("Apps", "ALT + Space", "Open launcher", exec("forge-open launcher"))
bind("Apps", "ALT + F2", "Run a command", exec("forge-open launcher"))
bind("Apps", "SUPER + I", "Open settings", exec("forge-open settings"))
bind("Apps", "CTRL + SHIFT + Escape", "Open system monitor", exec("forge-open monitor"))
if has("forge-arcade") then
    bind("Apps", "SUPER + G", "Open Forge Arcade", exec("forge-arcade"))
end
if has("forge-gaming") then
    bind("Apps", "SUPER + SHIFT + G", "Open Forge Gaming", exec("forge-gaming"))
end
if has("forge-terminal") and SHELL then
    bind("Apps", "SUPER + grave", "Drop-down terminal", exec("forge-terminal --dropdown"))
end

-- Shell ---------------------------------------------------------------------
if SHELL then
    bind("Shell", "SUPER + A", "Control Center", shell("control"))
    bind("Shell", "SUPER + N", "Notifications", shell("notifications"))
    bind("Shell", "SUPER + slash", "Shortcut cheat sheet", shell("cheatsheet"))
    bind("Shell", "SUPER + V", "Clipboard history", shell("clipboard"))
    bind("Shell", "SUPER + period", "Emoji picker", shell("emoji"))
    bind("Shell", "SUPER + Tab", "Overview of workspaces", shell("overview"))
    bind("Shell", "SUPER + SHIFT + K", "Show or hide the shortcut panel", shell("shortcutsPanel"))
    -- Hold Super for half a second: what each next key does (gone when Super
    -- is let go).
    bind("Shell", "SUPER + Super_L", "Hold for a list of shortcuts", shell("whichkey"),
        { long_press = true })
else
    bind("Shell", "SUPER + A", "Control Center", exec("forge-open control"))
end
bind("Shell", "SUPER + SHIFT + C", "Pick a colour from the screen", exec("hyprpicker --autocopy --format=hex"))

-- Windows -------------------------------------------------------------------
bind("Windows", "SUPER + Q", "Close window", hl.dsp.window.close())
bind("Windows", "ALT + F4", "Close window", hl.dsp.window.close())
bind("Windows", "SUPER + Up", "Maximise", snap.maximise)
bind("Windows", "SUPER + Down", "Restore, or minimise", snap.restore_or_minimise)
bind("Windows", "SUPER + SHIFT + Down", "Show minimised windows", hl.dsp.workspace.toggle_special("minimized"))
bind("Windows", "SUPER + Left", "Snap left (or move left when tiled)", function() snap.snap("left") end)
bind("Windows", "SUPER + Right", "Snap right (or move right when tiled)", function() snap.snap("right") end)
bind("Windows", "SUPER + ALT + Left", "Focus the window to the left", hl.dsp.focus({ direction = "left" }))
bind("Windows", "SUPER + ALT + Right", "Focus the window to the right", hl.dsp.focus({ direction = "right" }))
bind("Windows", "SUPER + ALT + Up", "Focus the window above", hl.dsp.focus({ direction = "up" }))
bind("Windows", "SUPER + ALT + Down", "Focus the window below", hl.dsp.focus({ direction = "down" }))
bind("Windows", "SUPER + F", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
bind("Windows", "SUPER + T", "Float or tile this window", hl.dsp.window.float({ action = "toggle" }))
bind("Windows", "SUPER + SHIFT + T", "Tiling on or off for this workspace", function() forge.tiling.toggle() end)
bind("Windows", "SUPER + P", "Keep on top of every workspace", hl.dsp.window.pin({ action = "toggle" }))
if SHELL then
    bind("Windows", "ALT + Tab", "Switch windows", shell("switcherNext"))
    bind("Windows", "ALT + SHIFT + Tab", "Switch windows, backwards", shell("switcherPrevious"))
    -- Letting go of Alt picks the window the switcher shows.
    bind("Windows", "ALT + Alt_L", "Pick the window (let go of Alt)", shell("switcherCommit"),
        { release = true })
else
    bind("Windows", "ALT + Tab", "Switch windows", function()
        hl.dispatch(hl.dsp.window.cycle_next({ next = true }))
        hl.dispatch(hl.dsp.window.bring_to_top())
    end)
    bind("Windows", "ALT + SHIFT + Tab", "Switch windows, backwards", function()
        hl.dispatch(hl.dsp.window.cycle_next({ prev = true }))
        hl.dispatch(hl.dsp.window.bring_to_top())
    end)
end
bind("Windows", "SUPER + mouse:272", "Move window (drag)", hl.dsp.window.drag(), { mouse = true })
bind("Windows", "SUPER + mouse:273", "Resize window (right-drag)", hl.dsp.window.resize(), { mouse = true })

-- Resize and move modes: arrows until Enter or Escape, with a hint on screen.
local RESIZE_HINT = "Resize: arrow keys (Shift for bigger steps)   ·   Enter or Esc to finish"
local MOVE_HINT = "Move: arrow keys (Shift for bigger steps)   ·   Enter or Esc to finish"
local function leave() forge.unhint(); hl.dispatch(hl.dsp.submap("reset")) end

bind("Windows", "SUPER + R", "Resize mode", function()
    hl.dispatch(hl.dsp.submap("resize")); forge.hint(RESIZE_HINT)
end)
bind("Windows", "SUPER + M", "Move mode", function()
    hl.dispatch(hl.dsp.submap("move")); forge.hint(MOVE_HINT)
end)

local function steps(name, make)
    forge.submap(name, function()
        for _, s in ipairs({ { "", 20 }, { "SHIFT + ", 100 } }) do
            local mod, n = s[1], s[2]
            bind("Windows", mod .. "Left", name == "resize" and "Narrower" or "Move left", make(-n, 0), { repeating = true })
            bind("Windows", mod .. "Right", name == "resize" and "Wider" or "Move right", make(n, 0), { repeating = true })
            bind("Windows", mod .. "Up", name == "resize" and "Shorter" or "Move up", make(0, -n), { repeating = true })
            bind("Windows", mod .. "Down", name == "resize" and "Taller" or "Move down", make(0, n), { repeating = true })
        end
        bind("Windows", "Return", "Finish", leave)
        bind("Windows", "Escape", "Finish", leave)
    end)
end
steps("resize", function(x, y) return hl.dsp.window.resize({ x = x, y = y, relative = true }) end)
steps("move", function(x, y) return hl.dsp.window.move({ x = x, y = y, relative = true }) end)

-- Workspaces ----------------------------------------------------------------
for i = 1, 9 do
    bind("Workspaces", "SUPER + " .. i, "Go to workspace " .. i, hl.dsp.focus({ workspace = i }))
    bind("Workspaces", "SUPER + SHIFT + " .. i, "Move window to workspace " .. i, hl.dsp.window.move({ workspace = i }))
end
bind("Workspaces", "SUPER + CTRL + Left", "Previous workspace", hl.dsp.focus({ workspace = "r-1" }))
bind("Workspaces", "SUPER + CTRL + Right", "Next workspace", hl.dsp.focus({ workspace = "r+1" }))
bind("Workspaces", "SUPER + CTRL + SHIFT + Left", "Move window to the previous workspace", hl.dsp.window.move({ workspace = "r-1" }))
bind("Workspaces", "SUPER + CTRL + SHIFT + Right", "Move window to the next workspace", hl.dsp.window.move({ workspace = "r+1" }))
bind("Workspaces", "SUPER + mouse_down", "Next workspace (scroll)", hl.dsp.focus({ workspace = "e+1" }))
bind("Workspaces", "SUPER + mouse_up", "Previous workspace (scroll)", hl.dsp.focus({ workspace = "e-1" }))
bind("Workspaces", "SUPER + S", "Scratchpad: show or hide", hl.dsp.workspace.toggle_special("scratchpad"))
bind("Workspaces", "SUPER + ALT + S", "Send window to the scratchpad", hl.dsp.window.move({ workspace = "special:scratchpad" }))

-- Screenshots ---------------------------------------------------------------
bind("Screenshots", "Print", "Screenshot an area", exec("forge-screenshot area"))
bind("Screenshots", "SUPER + SHIFT + S", "Screenshot an area", exec("forge-screenshot area"))
bind("Screenshots", "SHIFT + Print", "Screenshot the screen", exec("forge-screenshot screen"))
bind("Screenshots", "SUPER + Print", "Screenshot the window", exec("forge-screenshot window"))
bind("Screenshots", "SUPER + ALT + R", "Start or stop screen recording", exec("forge-record toggle"))

-- System --------------------------------------------------------------------
bind("System", "SUPER + L", "Lock the screen", exec("loginctl lock-session"))
if SHELL then
    bind("System", "CTRL + ALT + Delete", "Power menu", shell("power"))
    bind("System", "Caps_Lock", "Show Caps Lock on screen", shell("capsLock"), { non_consuming = true })
else
    bind("System", "CTRL + ALT + Delete", "Power menu", exec("forge-power-menu"))
end
bind("System", "SUPER + SHIFT + N", "Do not disturb on or off", exec("forged set dnd toggle"))
bind("System", "SUPER + SHIFT + Escape", "Restart the shell", exec("forge-shell restart"))

-- Hardware keys work on the lock screen too, and repeat while held.
local hw = { locked = true, repeating = true }
bind("Media", "XF86AudioRaiseVolume", "Volume up", exec("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"), hw)
bind("Media", "XF86AudioLowerVolume", "Volume down", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), hw)
bind("Media", "XF86AudioMute", "Mute", exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
bind("Media", "XF86AudioMicMute", "Mute the microphone", exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
-- Brightness goes through forged (logind), so the shell's display shows it
-- at once; brightnessctl if forged isn't there.
bind("Media", "XF86MonBrightnessUp", "Brightness up", exec("forged set brightness +5 || brightnessctl -e4 -n2 set 5%+"), hw)
bind("Media", "XF86MonBrightnessDown", "Brightness down", exec("forged set brightness -5 || brightnessctl -e4 -n2 set 5%-"), hw)
bind("Media", "XF86KbdBrightnessUp", "Keyboard light up", exec("brightnessctl -d '*::kbd_backlight' set 33%+"), hw)
bind("Media", "XF86KbdBrightnessDown", "Keyboard light down", exec("brightnessctl -d '*::kbd_backlight' set 33%-"), hw)
local media = { locked = true }
bind("Media", "XF86AudioPlay", "Play or pause", exec("playerctl play-pause"), media)
bind("Media", "XF86AudioPause", "Play or pause", exec("playerctl play-pause"), media)
bind("Media", "XF86AudioNext", "Next track", exec("playerctl next"), media)
bind("Media", "XF86AudioPrev", "Previous track", exec("playerctl previous"), media)
