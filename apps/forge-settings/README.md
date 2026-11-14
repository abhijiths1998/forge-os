# Forge Settings

Settings for newcomers on Hyprland, where Hyprland itself has none. Flutter
on `forge_ui`, built into the ISO by `apps/build-packages.sh`.

## Pages

- **Displays** — resolution, scale, refresh rate and VRR per output; writes
  `~/.config/hypr/monitors.lua`.
- **Keyboard** — layout, variant, model, options, repeat delay/rate; writes
  `~/.config/hypr/input.user.lua`.
- **Mouse & touchpad** — natural scroll, tap-to-click, scroll factor,
  sensitivity, acceleration profile; writes `~/.config/hypr/input.user.lua`.
- **Shortcuts** — rebind any Forge shortcut, with conflict detection; writes
  `~/.config/hypr/keybinds.user.lua`. `forge keys` is the CLI equivalent.
- **Default apps** — the default web browser (through `xdg-settings`).
- **Startup apps** — what starts with the session (`~/.config/autostart/`).
- **Sound** — volume and default output through `wpctl` (PipeWire).
- **Network & VPN** — opens `nm-connection-editor` (installed).
- **Bluetooth** — on/off, paired devices, connect/forget through `bluetoothctl`.
- **Users** — accounts on this machine (read-only; `useradd`/`userdel` for changes).
- **About** — version, shell, apps.

## Config errors

A bad monitor line or a bad bind lands Hyprland in its raw red bar. Forge
Settings keeps the files it writes syntactically simple, and any failure is
shown as a readable notification with file and line — never the raw red bar.

## Shortcuts and conflict detection

The shortcuts page reads `hyprctl binds -j`, which carries every Forge bind’s
description as `[Category] text` (see `apps/forge-session/hypr/lib/bind.lua`).
The user changes the key on any row; Forge Settings checks the new key isn’t
already bound elsewhere (conflict detection, flagged inline) and writes
`keybinds.user.lua`, which `~/.config/hypr/hyprland.lua` loads after
`keybinds.lua`, so the user’s overrides win.

## `forge keys`

The `forge keys` CLI (part of the `forge` command) lists and rebinds
keybinds from `hyprctl binds -j`:

- `forge keys` — list every bind, grouped by category.
- `forge keys <category> <description> <new-key>` — rebind one bind; a key
  already in use is rejected as a conflict.
- Writes `~/.config/hypr/keybinds.user.lua` and reloads Hyprland’s config.

## Build

`flutter build linux --release` (the bundle goes to
`/usr/lib/forge-settings/`, `/usr/bin/forge-settings` links to it).

Each app keeps a README, a PKGBUILD and a `.desktop`, and builds through
`apps/build-packages.sh`. `forge-settings` is listed in
`profile/packages.x86_64`.
