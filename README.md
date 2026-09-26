# forge-os (placeholder name)

An Arch-based Linux distro for NVIDIA + gaming + KDE Plasma, cherry-picking
ideas from CachyOS, Nobara, Garuda, Bazzite, and EndeavourOS instead of
copying any one of them. See `docs/ROADMAP.md` for the feature rationale and
what's still ahead.

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

Arch's own tooling (`mkarchiso`, `pacstrap`) only runs on Arch Linux. If your
build machine isn't Arch (this was built from Nobara), everything runs
inside a Docker container instead:

```sh
build/build.sh init    # one-time: seed profile/ from upstream archiso releng
build/build.sh build   # produce the ISO into out/
build/build.sh shell   # interactive shell in the build container, for debugging
```

The first `build` run compiles Calamares from its AUR PKGBUILD (it's not
in the official repos or Chaotic-AUR) and downloads the full KDE + gaming
package set, so it's slow. A persistent Docker volume
(`forge-os-pkgcache`) caches downloaded packages across retries.

## Layout

- `build/` — the Docker build environment (`Containerfile`, `build.sh`).
- `profile/` — the archiso profile: package list, pacman config, and the
  `airootfs/` overlay that becomes both the live session and (via Calamares)
  the installed system.
- `profile/airootfs/etc/calamares/` — the installer configuration.
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
