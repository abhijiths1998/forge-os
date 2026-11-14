# Forge OS

*Built hot. Runs cool.*

Forge OS is an Arch-based Linux distro for gaming on Hyprland, with
first-class NVIDIA support. It cherry-picks ideas from CachyOS, Nobara,
Garuda, Bazzite and EndeavourOS instead of copying any one of them. See
`docs/ROADMAP.md` for the feature rationale and what's still ahead.

**Forge OS 3** moves the desktop from KDE Plasma to Hyprland, with Forge's
own shell in Quickshell; Plasma is gone. It arrives in steps (3.0 the
Hyprland desktop, then Forge Arcade and Forge Terminal, the Forge cast and
wallpapers, Forge Settings, Forge Code, onboarding). The plan is in
`docs/RELEASES.md`, the move itself in `docs/HYPRLAND.md`; the version is
set in `forge-os-release` (`forge about` shows it).

## What you get

- **Gaming, ready to go:** Steam, Lutris, Heroic, Wine, Proton tooling
  (ProtonUp-Qt, ntsync), GameMode, MangoHud, vkBasalt, Gamescope and a
  SteamOS-style Big Picture session in the login screen's session list.
- **Drivers for any GPU:** NVIDIA (open kernel modules), plus AMD and Intel
  Vulkan (64- and 32-bit) and hardware video decode, gstreamer codecs, and
  Xbox controllers over Bluetooth (xpadneo).
- **Tuned like Nobara/Bazzite/CachyOS:** linux-zen kernel, zram swap,
  ananicy-cpp with CachyOS's rules, irqbalance, split-lock throttling off,
  per-drive I/O schedulers, power profiles.
- **Forge Thermal:** CPU and GPU clock profiles to keep temperatures down,
  from the app or `forge thermal`. The default, Balanced, runs the CPU at
  90% of its maximum.
- **Safe to tinker:** btrfs with snapper snapshots you can boot from GRUB
  (grub-btrfs).
- **Installer:** Calamares, for UEFI and legacy BIOS machines.

## The desktop: Forge Glass on Hyprland

A calm pastel "liquid glass" desktop: Hyprland frosts translucent windows,
menus and panels, with rounded squircle corners, a soft lit edge and a deep
shadow (`apps/forge-session`). Forge's shell (`apps/forge-shell`, Quickshell)
draws a slim floating glass bar with workspaces, the clock and what's
playing, the Control Center, notifications with do not disturb, volume and
brightness displays, and a shortcut panel on the desktop that teaches the
keys (Super+/ shows them all, holding Super shows what each next key does).
Shortcuts follow Windows and macOS habits: Super+Q closes, Super+E opens
files, Super+L locks, Super+arrows snap, Super+1 to 9 switch workspaces,
Alt+Tab switches windows, Super+Space opens the command bar, Print takes a
screenshot. Tiling is a per-workspace switch (Super+Shift+T), off to begin
with. Plus Jakarta Sans type, light and dark. In a terminal:

```sh
forge install obs-studio   # repos, Chaotic-AUR, AUR (via pamac)
forge update               # packages + Flatpaks
forge theme dark           # or light; no argument toggles
forge tile on              # tiling on for this workspace
forge thermal              # temperatures, clocks and the active profile
forge thermal cool         # silent, cool, balanced or performance
```

## Forge apps

In-house apps in the Forge Glass look, in `apps/` (each has a README),
built into the ISO by `apps/build-packages.sh`. The Flutter ones share
`apps/forge_ui`: the theme model, palette and widgets, so they follow the
theme set in the Theming Kit:

| App | Replaces | Built with |
|---|---|---|
| **Forge Launcher**: Super+Space / Alt+Space command bar for apps, files, Forge actions, power, maths, `> command` and `? web search` | KRunner | Flutter + GTK runner (layer shell) |
| **Forge Store**: Discover, categories, search (repos, Chaotic-AUR, AUR), installed, updates | Pamac GUI | Flutter + libpamac (C++) |
| **Forge Browser**: tabs (across the top or vertical), bookmarks, history, downloads, built-in ad and tracker blocking (EasyList, EasyPrivacy, Peter Lowe) | Brave as the default | C++ / Qt WebEngine |
| **Forge Shell**: the bar, the Control Center (Wi-Fi, Bluetooth, quiet, dark mode, tiling, night light, brightness, volume, power and cooling profiles, now playing), notifications, OSDs, the desktop shortcut panel, the cheat sheet, overview, Alt+Tab, clipboard and emoji pickers; state from `forged` | Plasma's panels and tray | Quickshell (QML) + `forged` (Python, D-Bus) |
| **Forge Shot**: screenshots on the Print keys: an area on the frozen screen (loupe, handles), a window (click it) or the whole screen; a thumbnail after; an editor (arrows, boxes, text, highlighter, pixelate, numbered steps, crop); copy, save, copy the text in it. Super+Alt+R records the screen (gpu-screen-recorder, NVENC) | Spectacle | Flutter (forge_ui) + grim |
| **Forge Theming Kit**: themes (Forge Glass, Frost, Midnight, Ember, Aurora, Mint...) and sliders for colour (accent, glass tint, light/dark) and glass (blur, vibrancy, lit edge, grain), opacities and corners; `forge theme <name>` | Plasma's colour and effect settings, for the Forge look | Flutter (forge_ui) |

Each is translucent, so Hyprland's blur frosts it like the rest of the
desktop, and each draws a glass title bar of its own (Hyprland draws none). Brave stays installed for sites that need Widevine DRM.

## One theme everywhere

A theme set in the Theming Kit (or with `forge theme`, `forge glass`, or the
Control Center's dark switch) is one file, `~/.config/forge/theme.json`, and
reaches as much of the system as can take one:

| Where | How |
|---|---|
| Hyprland: blur, the lit edge, corners, shadows | forge-session's `theme.lua` reads theme.json; `hyprctl reload` |
| Forge's shell (bar, Control Center, panels) | reads theme.json live |
| Forge apps (Launcher, Store, Files, Terminal...) and Forge Code | read theme.json |
| GTK 3 and 4 apps | `forge.css` (libadwaita's named colours, which adw-gtk3 follows), light/dark, icons, fonts, cursor |
| Qt 5 and 6 apps | a Forge Glass palette through qt5ct/qt6ct |
| Firefox, Chromium/Brave, Electron apps, web pages | the appearance portal (light/dark and the accent, from GNOME's settings) |
| Flatpak apps | allowed to read the GTK colours; adw-gtk3 for GTK 3 apps from Flathub |
| The terminal prompt and `forge`'s output | `~/.config/forge/theme.sh`; open terminals follow at their next prompt |
| The login screen | its accent and light/dark (`forge-theme-login`, through polkit) |

`forge-theme-sync` does all of it. forged runs it two seconds after
theme.json changes, from anywhere. `forge theme status` shows where each
place stands, and `forge theme sync` runs it by hand. Not reached: Steam
(its own skin) and apps with their own theme settings (Discord, Brave's own
theme).

## Forge Thermal

Caps the CPU's and GPU's maximum clocks at a share of what the hardware
allows, so the machine runs cooler and quieter:

| Profile | CPU | GPU | For |
|---|---|---|---|
| Silent | 60% | 60% | reading, video |
| Cool | 75% | 80% | lower temperatures, most of the speed |
| **Balanced** (default) | 90% | 100% | everyday use |
| Cool gaming | 100% | 100% | games: the firmware holds the CPU at 90 °C / 45 W and the GPU at 80 °C (Lenovo LOQ/Legion only) |
| Performance | 100% | 100% | no limits |
| Custom | 30–100% | 30–100% | your own, set with sliders in the app |

The CPU limit works with amd-pstate, intel_pstate and acpi-cpufreq. On the
GPU it's a clock lock on NVIDIA, a power cap on AMD and a maximum frequency
on Intel. Where the firmware takes limits itself (Lenovo LOQ/Legion, through
`lenovo-wmi-other`), profiles can also set the CPU and GPU temperature limits
and the CPU's sustained and boost watts, which costs less speed than a clock
cap; the app (`apps/forge-thermal`) shows the live temperatures, a two-minute
graph, the fan speed and sliders for those limits. The choice is kept across reboots and suspend, and the user at the
machine can switch without a password. Profiles live in
`/etc/forge-thermal/profiles/` and are plain `KEY=value` files.

The artwork is generated: `branding-source/glass/generate.py` (wallpapers,
logo, boot assets) and `colors.py` (the terminal scheme), then `install.sh`
copies them into the profile. See `docs/ROADMAP.md` → "Forge Glass revamp".

## Forge Mind

The local file index and storage analyser that Forge's AI features are
built on (`forge-mind`). It's deterministic: a model only turns a request
into its calls and explains the results, so nothing is guessed and nothing
leaves the machine.

```sh
forge find the pdf from march      # files, from a request in plain words
forge space                        # disk, Steam libraries, snapshots, biggest folders
forge space cleanup                # what could go, with sizes and reasons
forge space clean <path>           # clean one of those (home files go to the trash)
```

Requests are read for the kind of file ("pdf", "screenshots", "videos"), when
("around march", "last week", "2 weeks ago"), where ("in downloads"), how big
("bigger than 2gb") and where it came from ("from github"); the rest are name
words. Rules do this instantly. A local model, run by
[Ollama](https://ollama.com) (qwen3:4b, set in `/etc/forge/mind.conf`, or per
user in `~/.config/forge/mind.conf`), reads longer requests too and adds likely name words: "my landlord's letter"
also looks for lease, rent and tenancy. It only adds words (a small model
guesses dates and file types wrong), takes about a second on a laptop
RTX 3050, and leaves the GPU the moment a game starts (GameMode). Files are
ranked by how many words match, typed words first. The Launcher
(Super+Space) shows these results under the apps.

The ISO carries Ollama (with its Vulkan backend: 40 MB, any GPU, instead of
CUDA's 6 GB) but not the 2.5 GB model. The installer downloads it
(`forge-mind-model`), in the time it can spare; if it's offline or the line
is slow, the first boot with a network finishes the download, resuming
where it stopped. Until then, requests are read by rules alone.

Cleanup knows what fills a gaming Linux disk: Proton prefixes and shader
caches of uninstalled Steam games (across every Steam library), the pacman
cache, AUR build files, node_modules, unused Flatpak runtimes, big files
untouched for a year, and identical files (checked by hash). `clean` only
accepts paths the cleanup list currently names.

The index (SQLite, FTS5) lives in `~/.local/share/forge-mind/` and is
refreshed by a user timer at idle priority; it waits while GameMode is
active. Apps use it over D-Bus (`org.forgeos.Mind`: `Ask`, `Search`,
`Stats`, `Cleanup`, `Clean`, `Index`, all returning JSON), which starts it on
demand; it exits after ten idle minutes.

## Post-install script (faster path, no ISO)

If a full custom ISO is more than you need right now, `post-install/setup.sh`
gives you the same NVIDIA/gaming/optimization cherry-picks as a script you
run on top of a plain Arch install (e.g. straight after `archinstall`):

```sh
./post-install/setup.sh
```

It's an interactive menu (built on [gum](https://github.com/charmbracelet/gum),
which it installs itself) for: NVIDIA driver choice, a gaming-tools
multi-select (Steam, Lutris, Heroic, GameMode, MangoHud, vkBasalt,
ProtonUp-Qt, Gamescope, ...), system optimizations (zram, ananicy-cpp,
irqbalance, reflector, linux-zen), and a default browser. Safe to re-run.

## Building the ISO

**On GitHub** (no disk space needed locally): Actions → **Build ISO** → Run
workflow. It runs the same `build/build.sh build` on GitHub's runner and keeps
the ISO and its checksum as an artifact of the run (14 days by default) for
download from the run's page. See `.github/workflows/iso.yml`.

Arch's own tooling (`mkarchiso`, `pacstrap`) only runs on Arch Linux, so the
build runs inside a Docker container and works from any distro:

```sh
build/build.sh init    # one-time: seed profile/ from upstream archiso releng
build/build.sh build   # produce the ISO into out/
build/build.sh shell   # interactive shell in the build container, for debugging
```

The first `build` run compiles Calamares from its AUR PKGBUILD (it's not
in the official repos or Chaotic-AUR), builds the Forge apps, and downloads the full desktop + gaming
package set, so it's slow. A persistent Docker volume
(`forge-os-pkgcache`) caches downloaded packages across retries. A full build
takes about 40 minutes; the ISO lands in `out/forge-os-<version>-<date>-x86_64.iso`.

## Layout

- `build/` — the Docker build environment (`Containerfile`, `build.sh`).
- `profile/` — the archiso profile: package list, pacman config, and the
  `airootfs/` overlay that becomes both the live session and (via Calamares)
  the installed system.
- `profile/airootfs/etc/calamares/` — the installer configuration.
- `profile/airootfs/usr/local/bin/` — Forge OS's own tools: `forge`,
  `forge-thermal` (its app is `apps/forge-thermal`), and `forge-postinstall.sh`
  (run by the installer).
- `apps/` — Forge OS's in-house apps (see "Forge apps"), each with a
  PKGBUILD; `apps/build-packages.sh` builds every one into the local repo
  during `build/build.sh build`, before mkarchiso.
- `utils/` — scripts for working on a real machine: install an app or
  `forge-thermal` from the checkout, check a gaming setup, catch and report
  hard freezes, switch the default kernel, pin the NVIDIA driver (see
  `utils/README.md`).
- `packages/` — Forge's builds of other packages, built the same way:
  `packages/konsole` is Konsole with a fix (open terminals kept turning
  opaque when the desktop switched between light and dark), until KDE has it.
- `branding-source/` — the logo source and the Forge Glass generators.
- `docs/ROADMAP.md` — what's built, what's deferred, and why.

## Testing the ISO

```sh
build/run-qemu.sh live      # boot the newest out/*.iso (UEFI + KVM)
build/run-qemu.sh install   # same, with a 60G test disk attached for Calamares
build/run-qemu.sh disk      # boot the installed test disk
build/run-qemu.sh reset     # wipe the test disk and its UEFI vars
```

Needs `qemu-full` (or `qemu-desktop`) and `edk2-ovmf`. The test disk lives
in `vm/` (gitignored); `MEM`, `CPUS` and `DISK_SIZE` env vars override the
defaults.

NVIDIA driver behavior, the gamescope session, and secure boot can't be
verified this way — they need real hardware.
