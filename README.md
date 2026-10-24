# Forge OS

*Built hot. Runs cool.*

Forge OS is an Arch-based Linux distro for gaming on KDE Plasma, with
first-class NVIDIA support. It cherry-picks ideas from CachyOS, Nobara,
Garuda, Bazzite and EndeavourOS instead of copying any one of them. See
`docs/ROADMAP.md` for the feature rationale and what's still ahead.

**Forge OS 2** arrives in steps: 2.0 is the Forge look and the first Forge
apps, then one theme per release (Control Center, living wallpapers, the
Forge Assistant, safe updates and a Game Hub, Focus) up to 3.0, where the
everyday apps are all Forge apps. The plan is in `docs/RELEASES.md`; the
version is set in `forge-os-release` (`forge about` shows it).

## What you get

- **Gaming, ready to go:** Steam, Lutris, Heroic, Wine, Proton tooling
  (ProtonUp-Qt, ntsync), GameMode, MangoHud, vkBasalt, Gamescope and a
  SteamOS-style Big Picture session in the login screen's session list.
- **Drivers for any GPU:** NVIDIA (open kernel modules), plus AMD and Intel
  Vulkan (64- and 32-bit) and hardware video decode, gstreamer codecs, and
  Xbox controllers over Bluetooth (xpadneo).
- **Tuned like Nobara/Bazzite/CachyOS:** linux-zen kernel, zram swap,
  ananicy-cpp with CachyOS's rules, irqbalance, split-lock throttling off,
  per-drive I/O schedulers, Plasma power profiles.
- **Forge Thermal:** CPU and GPU clock profiles to keep temperatures down,
  from the app or `forge thermal`. The default, Balanced, runs the CPU at
  90% of its maximum.
- **Safe to tinker:** btrfs with snapper snapshots you can boot from GRUB
  (grub-btrfs).
- **Installer:** Calamares, for UEFI and legacy BIOS machines.

## The look: Forge Glass

A calm pastel "liquid glass" desktop on KDE Plasma 6: a slim floating top
bar, a compact floating dock, frosted glass windows, menus, panels and
terminal, macOS-style dots under running apps in the dock, Plus Jakarta Sans
type, and a light and a dark variant. Press **Super+Space** or **Alt+Space** for the command
bar. In a terminal:

```sh
forge install obs-studio   # repos, Chaotic-AUR, AUR (via pamac)
forge update               # packages + Flatpaks
forge theme dark           # or light; no argument toggles
forge tile on              # auto-tiling (Polonium)
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
| **Forge Launcher**: Super+Space / Alt+Space command bar for apps, files, Forge actions, power, maths, `> command` and `? web search` | KRunner | Flutter + GTK runner |
| **Forge Store**: Discover, categories, search (repos, Chaotic-AUR, AUR), installed, updates | Pamac GUI | Flutter + libpamac (C++) |
| **Forge Browser**: tabs (across the top or vertical), bookmarks, history, downloads, built-in ad and tracker blocking (EasyList, EasyPrivacy, Peter Lowe) | Brave as the default | C++ / Qt WebEngine |
| **Forge Control**: the Control Center, a glass panel from the top bar: Wi-Fi, Bluetooth, quiet, dark mode, tiling, brightness, volume, power and cooling profiles, now playing; `forged state` / `forged set` | Plasma's tray popups, in one place | Flutter (forge_ui) + `forged` (Python, D-Bus) |
| **Forge Theming Kit**: themes (Forge Glass, Frost, Midnight, Ember, Aurora, Mint...) and sliders for colour (accent, glass tint, light/dark) and liquid glass (blur, vibrancy, lens, bevel, inner bending, colour split, grain), opacities and corners; `forge theme <name>` | System Settings' colour and effect pages, for the Forge look | Flutter (forge_ui) |

Each is translucent, so KWin's Glass effect frosts it like the rest of the
desktop. Brave stays installed for sites that need Widevine DRM.

## Forge Thermal

Caps the CPU's and GPU's maximum clocks at a share of what the hardware
allows, so the machine runs cooler and quieter:

| Profile | CPU | GPU | For |
|---|---|---|---|
| Silent | 60% | 60% | reading, video |
| Cool | 75% | 80% | lower temperatures, most of the speed |
| **Balanced** (default) | 90% | 100% | everyday use |
| Performance | 100% | 100% | no limits |
| Custom | 30–100% | 30–100% | your own, set with sliders in the app |

The CPU limit works with amd-pstate, intel_pstate and acpi-cpufreq. On the
GPU it's a clock lock on NVIDIA, a power cap on AMD and a maximum frequency
on Intel. The choice is kept across reboots and suspend, and the user at the
machine can switch without a password. Profiles live in
`/etc/forge-thermal/profiles/` and are plain `KEY=value` files.

The artwork is generated: `branding-source/glass/generate.py` (wallpapers,
logo, boot assets), `colors.py` (colour schemes) and `desktoptheme.py`
(Plasma theme: dock dots), then `install.sh`
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

Arch's own tooling (`mkarchiso`, `pacstrap`) only runs on Arch Linux, so the
build runs inside a Docker container and works from any distro:

```sh
build/build.sh init    # one-time: seed profile/ from upstream archiso releng
build/build.sh build   # produce the ISO into out/
build/build.sh shell   # interactive shell in the build container, for debugging
```

The first `build` run compiles Calamares from its AUR PKGBUILD (it's not
in the official repos or Chaotic-AUR), builds the Forge apps, and downloads the full KDE + gaming
package set, so it's slow. A persistent Docker volume
(`forge-os-pkgcache`) caches downloaded packages across retries. A full build
takes about 40 minutes; the ISO lands in `out/forge-os-<date>-x86_64.iso`.

## Layout

- `build/` — the Docker build environment (`Containerfile`, `build.sh`).
- `profile/` — the archiso profile: package list, pacman config, and the
  `airootfs/` overlay that becomes both the live session and (via Calamares)
  the installed system.
- `profile/airootfs/etc/calamares/` — the installer configuration.
- `profile/airootfs/usr/local/bin/` — Forge OS's own tools: `forge`,
  `forge-thermal` and its app `forge-thermal-gui`, and `forge-postinstall.sh`
  (run by the installer).
- `apps/` — Forge OS's in-house apps (see "Forge apps"), each with a
  PKGBUILD; `apps/build-packages.sh` builds every one into the local repo
  during `build/build.sh build`, before mkarchiso.
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
