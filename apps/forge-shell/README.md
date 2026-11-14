# Forge shell

Forge OS's desktop shell, written in [Quickshell](https://quickshell.org)
(QML). It draws everything that isn't a window: the top bar, the Control
Center and the bar's popups, notifications, on-screen displays, the desktop
shortcut panel, and the overlays (the shortcut cheat sheet, the hold-Super
popup, the overview, the window switcher, the clipboard and emoji pickers,
and the power menu). It replaces Plasma's panels, and the Control Center
replaces the Flutter Forge Control panel.

The system's state comes from `forged`, the same D-Bus service the rest of
Forge uses. Quickshell has no D-Bus client for QML, so the shell reads
`forged watch`, which prints the state as one JSON line now and again on
every change. Changes go through `forged set` and `forged do`.

## What's where

| | |
|---|---|
| **Bar** (`bar/`) | the Forge button (launcher), workspaces, the focused window; the island in the middle (clock and date, and the song while one plays); the mode badge (resize/move), do not disturb, apps' tray icons, battery (percentage inside), Wi-Fi, Bluetooth, sound, the Control Center |
| **Popups** (`popups/`) | Wi-Fi (networks, joining, passwords), Bluetooth (paired devices, connecting), sound (level, outputs), battery (details) |
| **Control Center** (`panels/ControlCenter.qml`, Super+A) | Wi-Fi, Bluetooth, do not disturb, dark mode, tiling (this workspace), night light (hyprsunset); brightness and volume; power and cooling profiles; now playing; settings, lock, power |
| **Notifications** (`services/Notifs.qml`) | Forge's notification server: pop-ups with actions and images, kept in the notification centre (Super+N, or a click on the clock) until dismissed. Do not disturb (forged's switch) holds pop-ups back, apart from urgent ones |
| **OSDs** (`overlays/Osd.qml`) | volume (PipeWire, whoever changes it), brightness (from forged), Caps Lock |
| **Shortcut panel** (`panels/ShortcutPanel.qml`) | a glass card on the desktop, under windows, listing the main shortcuts by category. It's shown to new users, and can be collapsed (click its title), moved (drag its title), or hidden ("I know these, hide"; Super+Shift+K brings it back) |
| **Cheat sheet** (`overlays/CheatSheet.qml`, Super+/) | every shortcut, full screen, with search ("screenshot" shows those, with their keys) |
| **Hold Super** (`overlays/WhichKey.qml`) | hold Super for half a second: each Super+key and what it does; gone when Super is let go |
| **Overview** (Super+Tab) | every workspace with live previews; click or arrows and Enter |
| **Switcher** (Alt+Tab) | windows, most recent first, with live previews; let go of Alt to switch |
| **Clipboard** (Super+V) | the clipboard history (cliphist); Enter pastes, Delete forgets |
| **Emoji** (Super+.) | search by name; Enter types it |
| **Power** (Ctrl+Alt+Delete) | lock, log out, restart, shut down |

## Shortcuts come from Hyprland

`services/Binds.qml` reads `hyprctl binds -j` at start and again on every
config reload. Forge's binds have descriptions like `[Windows] Close
window` (see the forge-session package), so the panel, the cheat sheet and
the hold-Super popup always match what the keys really do, including binds
the user adds with `forge.bind`. Runs like "Go to workspace 1" to "9" fold
into one row (Super + 1–9).

## Driving it

The session's binds reach the shell as Hyprland global shortcuts
(`hl.dsp.global("forge:control")` and so on, matched by `GlobalShortcut`
in `shell.qml`). They're instant, and they also report when a key is let
go, which the hold-Super popup and the Alt+Tab switcher need. Scripts use
the command:

```sh
forge-shell control | notifications | cheatsheet | clipboard | emoji |
            overview | power | whichkey | shortcuts-panel | close
forge-shell switcher next|previous|commit
forge-shell wallpaper-pause | wallpaper-resume     # forge-game uses these
forge-shell restart
```

It runs as `forge-shell.service` (a systemd user service started with the
graphical session).

## Settings

Kept in `~/.local/state/forge/shell.json`: the shortcut panel's place and
whether it's shown or collapsed, night light, recent emoji. The look follows
`~/.config/forge/theme.json` (the Theming Kit's) live.

## Tests

```sh
apps/forge-shell/tests/run.sh      # OUT=/tmp/shots keeps the screenshots
```

This runs the real shell, with forged, inside Forge's Hyprland session (the
forge-session smoke harness: Hyprland 0.57 nested on the desktop that runs
the test). It checks the shell starts without QML errors, forged answers,
Hyprland frosts the shell's layers, notifications pop up, do not disturb
holds them back, the cheat sheet opens and the clipboard history lists
what was copied. It also takes a screenshot of every panel and overlay.
`build/check.sh qml` runs qmllint.
