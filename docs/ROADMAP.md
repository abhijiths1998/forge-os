# forge-os roadmap

## Feature cherry-pick map

| Feature | Source of inspiration | Status |
|---|---|---|
| Chaotic-AUR as a secondary repo | CachyOS / Garuda | Done — bootstrapped in `build/Containerfile`, carried into the shipped system via `chaotic-keyring`/`chaotic-mirrorlist` |
| Automatic NVIDIA driver install | Nobara | Partial — `nvidia-open-dkms` is installed unconditionally (NVIDIA's current default for Turing/2018+ GPUs). No runtime GPU-generation detection yet; see "Deferred" below |
| Btrfs + snapper + grub-btrfs snapshots | Garuda | Done, but **untested on real hardware** — Calamares' partition/mount modules default to a btrfs `@`/`@home`/`@cache`/`@log`/`@snapshots` layout, and `forge-postinstall.sh` runs `snapper create-config` + enables the timers |
| Calamares installer with branding/slideshow | Garuda / EndeavourOS | Done — see "Calamares isn't packaged anywhere" below for how it's actually built |
| Minimal, curated package base | EndeavourOS | Done — see "kde-applications-meta was a trap" below |
| Gaming stack (Steam, Lutris, Heroic, gamemode, mangohud, goverlay, vkBasalt, ProtonUp-Qt, controller udev rules) | Bazzite / Nobara / CachyOS | Done |
| zram, ananicy-cpp, irqbalance, reflector, parallel pacman + ILoveCandy | Common across modern spins | Done |
| Flatpak preinstalled | Nobara / Bazzite | Done (package only; Flathub remote isn't auto-added yet, see Deferred) |
| fwupd, secure boot via sbctl | CachyOS | Partial — packages installed and fwupd enabled; sbctl itself needs a per-machine `sbctl create-keys`/`sbctl enroll-keys`, which can't be done at ISO-build time |
| BORE-scheduler kernel, x86-64-v3 packages | CachyOS | Deferred (see below) |
| Gamescope session (SteamOS-style boot option) | Bazzite / SteamOS | Deferred (see below) |
| EndeavourOS-style Welcome app | EndeavourOS | Deferred (Phase 2) |
| Real branding (name/logo/wallpapers/Plymouth/SDDM/GRUB theme) | — | Deferred (Phase 2) |

## Things discovered while building this that changed the plan

**Calamares isn't packaged anywhere usable.** It's in neither the official
Arch repos nor Chaotic-AUR — every distro that uses it (EndeavourOS, Garuda,
CachyOS) builds it themselves in their own repo. `build/Containerfile` now
compiles it from its AUR `PKGBUILD` once per image build and serves it from
a local `file://` repo (`forge-os-local`) that only `profile/pacman.conf`
(the *build-time* config) references — it's deliberately absent from
`profile/airootfs/etc/pacman.conf` (the config actually shipped on the live
system), since that path only exists inside the build container.

**`nvidia-dkms` doesn't exist anymore.** Arch has moved to `nvidia-open`/
`nvidia-open-dkms` as the default for Turing-and-newer GPUs; the legacy
proprietary driver only exists chaotic-aur-side as version-pinned packages
(`nvidia-470xx-dkms`, `nvidia-390xx-dkms`, etc.) for pre-Turing cards. See
Deferred.

**`kde-applications-meta` was a trap.** It doesn't mean "some useful KDE
apps" — it pulls in the *entire* KDE Applications release: Calligra-style
office apps, education apps, kdevelop, kde-games, the works. First build
attempt was still downloading gigabytes of unrelated packages when this was
caught. `packages.x86_64` now lists a specific, curated set of apps instead
(dolphin, konsole, kate, ark, gwenview, okular, spectacle, discover,
partitionmanager, etc.) alongside plain `plasma-meta`.

**`pacman.conf` in the profile root only controls the build.** It's what
`pacstrap` uses to install `packages.x86_64`; it is *not* automatically
copied to be the live/installed system's `/etc/pacman.conf` (that comes from
the `pacman` package's own default unless something overrides it). Hence
`profile/airootfs/etc/pacman.conf` exists as a separate, explicit file — it's
what the shipped system actually uses.

**`customize_airootfs.sh` is deprecated but still works** (as of this
archiso version — it prints a warning that support will be removed
eventually). It's what creates the `liveuser` account and enables the
baseline systemd services. Worth revisiting via a pacman-hook-based approach
if/when archiso actually drops it.

## Deferred (not built this session)

- **CachyOS kernel / x86-64-v3 packages**: needs its own separate repo +
  keyring bootstrap (parallel to the Chaotic-AUR one) plus CPU-microarch
  detection to pick v3 vs v4 vs baseline. `linux-zen` ships today as a
  lower-risk performance win; swap it out once the CachyOS repo is wired up
  the same way Chaotic-AUR is.
- **NVIDIA generation detection**: `nvidia-open-dkms` is installed
  unconditionally. Pre-Turing GPUs (GTX 16-series and older) need one of
  Chaotic-AUR's legacy `nvidia-4xxxx-dkms` packages instead — a first-boot
  or Calamares-time `lspci`-based check should pick the right package.
- **Gamescope session**: `gamescope` is installed, but there's no boot-menu
  or SDDM session entry wired up yet for a SteamOS-style Big Picture mode.
- **Flathub remote**: `flatpak` is installed but the Flathub remote isn't
  auto-added; either do it in `customize_airootfs.sh` or in the Welcome app
  (Phase 2).
- **Legacy proprietary NVIDIA / secure boot enrollment / any other
  per-machine step**: inherently can't be baked into the ISO; belongs in
  first-boot tooling.

## Phase 2 — Identity & UX

Real name/logo/wallpapers, Plymouth + SDDM + GRUB theming to match, and an
EndeavourOS-style Welcome app for post-install choices (Flathub opt-in,
NVIDIA re-check, optional extra codecs/DEs).

## Phase 3 — Own package repo

Host a small custom pacman repo (mirroring what `forge-os-local` does
inside the build container, but actually published) for forge-os-specific
meta-packages and tweaks, instead of relying on a locally-compiled Calamares
baked into one build container image.

## Phase 4 — Gaming polish

Gamescope session hardening, handheld/HDR support, a real controller udev
rules bundle review, CI (GitHub Actions) to build and publish ISOs on tag
push.

## Verification status

- ISO build: see the session's final report for whether `build/build.sh
  build` completed and what the resulting image looks like.
- QEMU boot / Calamares launch: to be verified after a successful build.
- NVIDIA driver behavior, gamescope session, secure boot, snapper rollback:
  **not verified** — all need real hardware or a real install run, not just
  a build or a QEMU boot.
