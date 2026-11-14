# Forge OS releases

Forge OS 3 moves the desktop from KDE Plasma to Hyprland, with Forge's own
shell in Quickshell (decided 2026-11-14; the audit and design are in
`docs/HYPRLAND.md`). Each release has one theme, and the plumbing a later
release needs lands first. `docs/ROADMAP.md` keeps the detail and the
history of what was built; this file is the plan.

A release is done when its ISO is built, installed in QEMU and on real
hardware, and every feature in it has been tried on the installed system,
not only in the live session or on the dev machine.

| Version | Theme | Milestones (HYPRLAND.md) | Status |
|---|---|---|---|
| 2.x | KDE Plasma line: 2.0 (the Forge look, the first apps) and 2.1 (Control Center) | — | Frozen: never released as an ISO; its work carries into 3.0 |
| **3.0** | Hyprland: the session, forge-shell, every Forge app ported, one theme everywhere | M1–M3 | In progress |
| 3.1 | Forge Arcade (Forge's games) and Forge Terminal + fastfetch | M4–M5 | Planned |
| 3.2 | The Forge cast and Forge Wallpapers (was 2.2, living desktop) | M6 | Planned |
| 3.3 | Forge Settings and the keybind editor (from the old 3.0) | M7 | In progress |
| 3.4 | Forge Code, the Neovim distribution | M8 | Planned |
| 3.5 | Onboarding: Welcome and Keyboard Dojo | M9 | Planned |
| 3.6+ | Forge Assistant (was 2.3), safe updates and the Game Hub (2.4), Focus and the Dynamic Island (2.5) | — | Planned |

## 3.0: Hyprland

- **M1, the session** (`apps/forge-session`): Hyprland 0.57 through uwsm,
  Forge's defaults in Lua under `/usr/share/forge/hypr` (updated with the
  system) and the user's own files in `~/.config/hypr` (never touched).
  Forge Glass in Hyprland's terms, NVIDIA set up by `forge-gpu-env`,
  Windows/macOS-style shortcuts, each with a category and a description,
  resize and move modes with hints, snapping, per-workspace tiling (off by
  default), game rules, hypridle and a Forge Glass hyprlock. The live ISO
  boots into Hyprland and opens Calamares.
- **M2, forge-shell** (`apps/forge-shell`, Quickshell): the bar, Control
  Center, popups, notifications with do-not-disturb, OSDs, the desktop
  shortcut panel, the Super+/ cheat sheet, the hold-Super popup, overview,
  window switcher, clipboard, emoji and colour pickers. Plasma leaves the
  ISO.
- **M3, the apps**: forged and every Forge app without KDE, theme sync to
  Hyprland, GTK, Qt, the terminal, Neovim, the login screen and fastfetch;
  Forge Shot on grim with recording; the `forge` CLI's tile, glass, theme
  and keys.
- **M7, Forge Settings + keybind editor** (`apps/forge-settings`, Flutter on
  `forge_ui`): displays, keyboard, mouse, default apps, startup, sound,
  network/VPN (`nm-connection-editor` fallback), Bluetooth, users, about;
  plus the shortcuts editor that rebinds any bind from `hyprctl binds -j`
  with conflict detection, writing `~/.config/hypr/keybinds.user.lua`, and
  the `forge keys` CLI equivalent. Config errors show as a readable
  notification with file and line, never the raw red bar.

## The 2.x line (KDE, frozen)

Kept as the record of what 2.0 and 2.1 brought; all of it moves to 3.0.

### 2.0: the Forge look and the first Forge apps

Everything built so far, released together.

- **Forge Glass:** natural liquid glass that runs to the edge, no borders;
  `forge glass calm|liquid|bold`.
- **Forge UI kit** (`apps/forge_ui`): the theme, palette and widgets every
  Forge app shares.
- **Forge Theming Kit:** themes and sliders for colour and glass.
- **Forge Launcher**, **Forge Store**, **Forge Browser**.
- **Forge Mind:** find files from plain requests ("the pdf from march"),
  storage stats and safe cleanup (`forge find`, `forge space`); a local model
  (Ollama, Vulkan) downloaded at install time.
- **Forge Thermal.**
- **Release plumbing:** a version (`/etc/os-release`, the installer,
  `forge about`) that survives package updates.

To release: version plumbing; a full ISO build; a QEMU install that checks
the model download in the installer and on first boot; the items in
ROADMAP's "Verification status" that are still open.

### 2.1: Control Center

Built so far (2026-10-24, tried on the dev machine, not yet in an ISO):
`forged`, Forge Control with its top-bar button, Forge Battery, and Forge
Wi-Fi, Bluetooth and Sound in place of the tray's icons. Still to do for 2.1:
picking a Wi-Fi network or Bluetooth device in the panel (today they only
switch on and off), the Launcher on gtk-layer-shell, and a check on a
laptop's built-in screen and a real install. The panel's own
gtk-layer-shell anchoring works.

- **`forged`:** a system service (D-Bus) that knows the system state and can
  change it: network, Bluetooth, audio, brightness, power and thermal
  profiles, theme, tiling, do-not-disturb, media. The Control Center uses it
  first; the Assistant, Focus and the Dynamic Island build on it later.
- **Control Center:** a glass panel from the top bar with Wi-Fi, Bluetooth,
  volume, brightness, power and thermal profile, dark mode, tiling,
  do-not-disturb and now playing (Flutter, `forge_ui`).
- **Forge Battery:** the top bar's battery, macOS-style, the percentage
  written inside it, and a popup with its details and style.
- **One theme everywhere:** `forge-theme-sync` takes the theme where KDE's
  colour scheme doesn't reach: the login screen, the terminal prompt and
  `forge`, GNOME's settings, Flatpak apps; forged runs it on any theme
  change.
- **Forge Wi-Fi, Bluetooth and Sound:** the tray's own icons replaced, each
  with a popup like the battery's: networks and joining them, paired
  devices, volume and outputs. The tray stays, slim, for apps' icons.
- **gtk-layer-shell** for Forge's panels, so they anchor to the screen edge;
  the Launcher moves to it too.

### Was 2.2, now 3.2: Living desktop

- **Live wallpapers:** shader wallpapers (GLSL, nearly free on CPU and
  battery) and video wallpapers (mpv), paused while a game runs full
  screen. The glass bends whatever moves behind it, so the whole desktop
  comes alive.
- **Forge Wallpapers:** a wallpaper app with free online sources:
  Wallhaven (no key), NASA's picture of the day, and Unsplash and Pexels
  (free keys). Daily wallpaper rotation.
- **Accent colours from the wallpaper:** the accent, glass tint and every
  Forge app follow the wallpaper (through the Theming Kit).

### Was 2.3, now 3.6+: Forge Assistant

Builds on Forge Mind and `forged`.

- **Assistant panel:** chat in Forge UI, in the Launcher (`?ai`) and as a
  side panel. The local model calls Forge Mind's and `forged`'s actions:
  "switch to Cool and open Steam", "install OBS", "why is my fan loud?",
  "what's filling my disk this week?". Actions that change things are
  shown and confirmed before they run.
- **Search inside files:** text in documents, OCR on screenshots, image
  search by meaning.
- **Downloads remember where they came from** (Forge Browser), so "the zip
  from github" works.
- **Troubleshooting:** "why did my game crash?" from the journal and Proton
  logs.
- An optional cloud model, off by default.

### Was 2.4, now 3.6+: Safe updates and the Game Hub

- **Undo for updates:** Forge Store takes a snapshot before each update and
  offers "Undo last update" in one click.
- **Game Hub:** one library for Steam, Heroic and Lutris games, with per-game
  profiles (thermal profile, MangoHud, Proton version) applied when a game
  starts.
- Forge Mind knows Lutris and Heroic games' folders and leftover prefixes.

### Was 2.5, now 3.6+: Focus and the Dynamic Island

- **Focus spaces:** Work, Gaming and Study, each setting wallpaper, apps,
  thermal profile and notifications together.
- **Dynamic Island:** the clock in the top bar shows the current song, a
  download, a timer or a call.

### Was 3.0, now 3.3 and later: Forge apps everywhere

(Written for Plasma; Hyprland replaced the KDE base instead.) The apps
people use every day are Forge apps.

- **Forge Files:** a file manager with the Assistant built in (search by
  what you remember, storage and cleanup in place).
- **Forge Settings**, and Forge versions of the rest of the everyday apps
  (terminal, media player, text editor, system monitor), replacing the KDE
  ones one by one. Screenshots came early: **Forge Shot** (2026-10-24), in
  place of Spectacle on the Print keys; screen recording is still
  Spectacle's.
- **Welcome app:** first-boot choices (Flathub, NVIDIA check, codecs,
  the model).

Not tied to a release yet: an own package repo and ISO builds in CI
(ROADMAP's Phases 3 and 4), CachyOS kernel and x86-64-v3 packages, NVIDIA
generation detection.
