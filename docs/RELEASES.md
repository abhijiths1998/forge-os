# Forge OS releases: 2.0 to 3.0

Forge OS 2 ships the ideas below one release at a time; 3.0 is when they are
all in. Each release has one theme, and the plumbing a later release needs
lands first. `docs/ROADMAP.md` keeps the detail and the history of what was
built; this file is the plan.

A release is done when its ISO is built, installed in QEMU and on real
hardware, and every feature in it has been tried on the installed system,
not only in the live session or on the dev machine.

| Version | Theme | Status |
|---|---|---|
| 2.0 | The Forge look and the first Forge apps | Built, not yet released |
| 2.1 | Control Center | In progress: forged and the panel built |
| 2.2 | Living desktop: wallpapers | Planned |
| 2.3 | Forge Assistant | Planned |
| 2.4 | Safe updates and the Game Hub | Planned |
| 2.5 | Focus and the Dynamic Island | Planned |
| 3.0 | Forge apps everywhere | Planned |

## 2.0: the Forge look and the first Forge apps

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

## 2.1: Control Center

Built so far (2026-10-24, tried on the dev machine, not yet in an ISO):
`forged`, Forge Control with its top-bar button, and Forge Battery (a
macOS-style battery in the top bar with the percentage inside). Still to do for 2.1:
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
  written inside it.
- **gtk-layer-shell** for Forge's panels, so they anchor to the screen edge;
  the Launcher moves to it too.

## 2.2: Living desktop

- **Live wallpapers:** shader wallpapers (GLSL, nearly free on CPU and
  battery) and video wallpapers (mpv), paused while a game runs full
  screen. The glass bends whatever moves behind it, so the whole desktop
  comes alive.
- **Forge Wallpapers:** a wallpaper app with free online sources:
  Wallhaven (no key), NASA's picture of the day, and Unsplash and Pexels
  (free keys). Daily wallpaper rotation.
- **Accent colours from the wallpaper:** the accent, glass tint and every
  Forge app follow the wallpaper (through the Theming Kit).

## 2.3: Forge Assistant

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

## 2.4: Safe updates and the Game Hub

- **Undo for updates:** Forge Store takes a snapshot before each update and
  offers "Undo last update" in one click.
- **Game Hub:** one library for Steam, Heroic and Lutris games, with per-game
  profiles (thermal profile, MangoHud, Proton version) applied when a game
  starts.
- Forge Mind knows Lutris and Heroic games' folders and leftover prefixes.

## 2.5: Focus and the Dynamic Island

- **Focus spaces:** Work, Gaming and Study, each setting wallpaper, apps,
  thermal profile and notifications together.
- **Dynamic Island:** the clock in the top bar shows the current song, a
  download, a timer or a call.

## 3.0: Forge apps everywhere

The KDE base stays; the apps people use every day are Forge apps.

- **Forge Files:** a file manager with the Assistant built in (search by
  what you remember, storage and cleanup in place).
- **Forge Settings**, and Forge versions of the rest of the everyday apps
  (terminal, screenshots, media player, text editor, system monitor),
  replacing the KDE ones one by one.
- **Welcome app:** first-boot choices (Flathub, NVIDIA check, codecs,
  the model).

Not tied to a release yet: an own package repo and ISO builds in CI
(ROADMAP's Phases 3 and 4), CachyOS kernel and x86-64-v3 packages, NVIDIA
generation detection.
