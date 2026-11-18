# Forge session

Forge OS's desktop session on Hyprland: the defaults Hyprland loads, the
keybinds, the small scripts those call, and the user services the session
runs. Forge's shell (the bar, the Control Center, notifications and the
pickers) is the separate `forge-shell` package.

## How the config is put together

Hyprland 0.55 moved its config to Lua, and 0.57 dropped `hyprland.conf`.
Everything here is Lua, apart from hypridle and hyprlock, which still read
their own `.conf` files.

```
/usr/share/forge/hypr/        this package; replaced on every update
  forge.lua        loads the modules below, in order
  env.lua          environment for apps (from forge-gpu-env)
  theme.lua        reads ~/.config/forge/theme.json (the Theming Kit's)
  look.lua         Forge Glass: blur, corners, edge, shadow, animations
  input.lua        keyboard layout (the installer's), touchpad, gestures
  rules.lua        what floats; Forge apps stay translucent
  tiling.lua       tiling per workspace (off by default)
  game.lua         game rules; effects off while a game is full screen
  keybinds.lua     every shortcut, through forge.bind
  autostart.lua    forge-session-start
  lib/             bind (categories), snap (Super+arrows), json
  hypridle.conf    dim 4 min, lock 5, screens off 5.5, sleep 30
  hyprlock.conf    the Forge Glass lock screen

~/.config/hypr/               the user's; updates never touch it
  hyprland.lua     loads Forge's, then forge.load_user():
  monitors.lua       Forge Settings' displays page writes it
  input.user.lua     Forge Settings' keyboard and touchpad pages
  keybinds.user.lua  Forge Settings' shortcuts page
  user.lua           the user's own settings, loaded last
```

New users get `hyprland.lua` and `user.lua` from `/etc/skel`. Copies are in
`/usr/share/forge/skel/hypr` for anyone who wants them back.

## Shortcuts

Every bind goes through `forge.bind(category, keys, description,
dispatcher)`. Hyprland's `hyprctl binds -j` then shows the description as
`[Category] description`, which is what the desktop shortcut panel, the
Super+/ cheat sheet, the hold-Super popup and Forge Settings read. Shortcuts
for parts that aren't installed (forge-shell, Forge Arcade) are left out,
so every shortcut listed works.

The categories are Apps, Shell, Windows, Workspaces, Screenshots, System
and Media. See `hypr/keybinds.lua`, or press Super+/ once forge-shell is
installed.

## Scripts

| Script | What it does |
|---|---|
| `forge-gpu-env` | the session's environment: NVIDIA's variables when NVIDIA drives the screen, `AQ_DRM_DEVICES` on hybrid laptops, toolkits on Wayland |
| `forge-open` | terminal, files, browser, launcher, settings, Control Center, system monitor, honouring the user's defaults |
| `forge-screenshot` | area, screen or window, with Forge Shot when it's there, else grim and slurp |
| `forge-record` | screen recording with gpu-screen-recorder (NVENC, VA-API) |
| `forge-power-menu`, `forge-logout` | Ctrl+Alt+Delete |
| `forge-game` | around games: wallpaper paused and the game cooling profile while one is full screen; idle blocked while GameMode runs |
| `forge-idle`, `forge-lock` | hypridle and hyprlock, with the user's own configs if there are any |
| `forge-wallpaper` | the wallpaper through awww |
| `forge-session-start` | once at login: D-Bus environment, cursor, GTK/Qt theme |

## Services

These start with `graphical-session.target`, which uwsm starts:
`forge-idle`, `forge-wallpaper`, `forge-clipboard-{text,image,keep}`,
`forge-automount` and `hyprpolkitagent`. GameMode starts and stops
`forge-game-inhibit` through `/etc/gamemode.ini`.

## Tests

```sh
lua tests/check-binds.lua hypr   # every bind has a category and description
tests/smoke.sh                   # a real Hyprland 0.57 runs the config
```

`tests/smoke.sh` needs the `forge-os-check` image (`build/check.sh` builds
it) and a Wayland desktop. Hyprland runs as a window on that desktop, since
it needs a parent that speaks current protocols, or a GPU it can drive. It
then checks the binds, floating by default, snapping, per-workspace tiling,
resize mode and workspaces, and leaves screenshots behind.
