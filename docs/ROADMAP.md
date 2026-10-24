# forge-os roadmap

## Feature cherry-pick map

| Feature | Source of inspiration | Status |
|---|---|---|
| Chaotic-AUR as a secondary repo | CachyOS / Garuda | Done — bootstrapped in `build/Containerfile`, carried into the shipped system via `chaotic-keyring`/`chaotic-mirrorlist` |
| Automatic NVIDIA driver install | Nobara | Partial — `nvidia-open-dkms` is installed unconditionally (NVIDIA's current default for Turing/2018+ GPUs). No runtime GPU-generation detection yet; see "Deferred" below |
| Btrfs + snapper + grub-btrfs snapshots | Garuda | Done, but **untested on real hardware** — Calamares' partition/mount modules default to a btrfs `@`/`@home`/`@cache`/`@log`/`@snapshots` layout, and `forge-postinstall.sh` runs `snapper create-config` + enables the timers |
| Calamares installer with branding/slideshow | Garuda / EndeavourOS | Done — see "Calamares isn't packaged anywhere" below for how it's actually built |
| Minimal, curated package base | EndeavourOS | Done — see "kde-applications-meta was a trap" below |
| Gaming stack (Steam, Lutris, Heroic, gamemode, mangohud, goverlay, vkBasalt, ProtonUp-Qt, Discord, controller udev rules) | Bazzite / Nobara / CachyOS | Done |
| zram, ananicy-cpp, irqbalance, reflector, parallel pacman + ILoveCandy | Common across modern spins | Done. ananicy-cpp ran with no rules until `cachyos-ananicy-rules-git` was added |
| Nobara-style tuning (2026-10-23) | Nobara / Bazzite / CachyOS | Done, **not yet verified on hardware**: AMD/Intel Vulkan (64+32-bit) and VA-API drivers (only NVIDIA's were installed, so games couldn't start on other GPUs), `libva-nvidia-driver`, gstreamer good/bad/ugly/libav codecs, `power-profiles-daemon` (Plasma power profiles), `xpadneo-dkms`; `/etc/sysctl.d/90-forge-os.conf` (split-lock mitigation off, ArchWiki zram swap values) and `/etc/udev/rules.d/60-ioschedulers.rules`. `ntsync-autoload` was already pulled in. Not done: xone (wireless dongle; only a -git package), scx schedulers |
| Forge Thermal: CPU/GPU clock profiles | User request ("regulate temperature, CPU at 90% by default") | Done, **root paths not yet verified on hardware**: `forge-thermal` caps every cpufreq policy's `scaling_max_freq` and the GPU (NVIDIA `nvidia-smi -lgc`, AMD `power1_cap`, Intel i915/xe max freq) by profile (`/etc/forge-thermal/profiles`: Silent 60/60, Cool 75/80, **Balanced 90/100, the default**, Performance 100/100, plus Custom). `forge-thermal.service` re-applies it at boot (after the display manager, since an NVIDIA clock lock only lasts while the GPU is held open), a system-sleep hook after resume. App: `forge-thermal-gui` (PySide6), CLI: `forge thermal`; polkit `org.forgeos.thermal` needs no password at the machine. Hybrid laptops may lose the NVIDIA cap when the dGPU powers off |
| macOS-style dock dots | User request | Done: `branding-source/glass/desktoptheme.py` writes the `forge-glass` Plasma theme, which only overrides `widgets/tasks` (dot under running apps, solid when active). Rendered with KSvg offscreen; not yet checked in a built ISO |
| Default browser | Common across modern spins | **Forge Browser** (`apps/forge-browser`, 2026-10-24): Qt WebEngine with built-in EasyList/EasyPrivacy/Peter Lowe blocking, Forge Glass new tab page, Darkly glass chrome. Brave stays installed for Widevine DRM sites |
| KWallet + KWalletManager (keyring) | KDE default | Done |
| App store: **Forge Store** (`apps/forge-store`, 2026-10-24) on libpamac, in place of the Pamac GUI (not Discover), + Flathub remote | Manjaro / Garuda | Done — Flutter UI in Forge Glass colours; queries via libpamac, transactions via the pamac CLI (polkit). Repo updates only as a whole (no partial upgrades). Pamac browses core/extra/multilib/Chaotic-AUR and Flatpak in one GUI, unlike Discover's more limited pacman/Flatpak-only view. `customize_airootfs.sh` adds the Flathub remote so it isn't empty on first boot |
| fwupd, secure boot via sbctl | CachyOS | Partial — packages installed and fwupd enabled; sbctl itself needs a per-machine `sbctl create-keys`/`sbctl enroll-keys`, which can't be done at ISO-build time |
| BORE-scheduler kernel, x86-64-v3 packages | CachyOS | Deferred (see below) |
| Gamescope session (SteamOS-style boot option) | Bazzite / SteamOS | Done, **not yet verified** — `gamescope-session-git` + `gamescope-session-steam-git` (Chaotic-AUR, built by Garuda's own packager) add a "Gamescope Session" entry to SDDM's session dropdown. Never actually selected it and booted into it in this session |
| EndeavourOS-style Welcome app | EndeavourOS | Deferred (Phase 2) — Plasma's own generic `plasma-welcome` already runs on first login, but isn't forge-os-specific content |
| ~~macOS-style default look (WhiteSur)~~ → **Forge Glass** (pastel liquid-glass look: own look-and-feel package, colour schemes, wallpaper, SDDM theme, splash, Plymouth; Plus Jakarta Sans type; floating top bar + compact centred dock; Super+Space command bar; rounded corners; optional auto-tiling) | User request (revamp after the "Nava OS 1.0" trailer's design language, with original assets) | See "Forge Glass revamp" below |
| zsh default shell: Oh My Zsh (plugins only) + autosuggestions + syntax-highlighting + completions, Forge Glass prompt (`user ~/path branch ›`) | User request | Prompt replaced agnoster in the Forge Glass revamp; plugins unchanged |
| Real branding: logo, desktop wallpaper, GRUB background, Plymouth boot splash | User-provided logo image | Calamares installer branding is done (same mechanism as the already-verified slideshow/theme config). **Plymouth boot splash (logo + live progress bar) is done and verified live in QEMU** — replaces the scrolling systemd unit list entirely on the live medium. GRUB background is still unverified (only applies post-install through GRUB, which a live-ISO QEMU boot never exercises). The **desktop wallpaper does not work** — tried twice, confirmed broken by direct visual inspection, root cause not found; see "Desktop wallpaper never actually applied" below |
| Replace WhiteSur's Apple branding: Kickoff launcher icon, SDDM login screen, Plasma login→desktop splash | User request ("remove apple and add some other logo"), later refined to use the second (transparent, flame/anvil) logo everywhere ("current one looks out of place") | **Kickoff icon: done and re-verified live in QEMU** with the new transparent logo — the top-left launcher icon now shows the flame/anvil emblem cleanly, confirmed by cropping and looking directly at it. **SDDM login logo and the Plasma splash screen: updated to the new logo via the identical proven mechanism, but still not visually confirmed** — the live medium autologins straight past SDDM's screen, and the Plasma splash is too brief to reliably catch in a screenshot. Both need a real install (autologin off) or a manual logout to actually see. See "Two logo variants, matched to context" below for why Kickoff and SDDM don't use the identical source image |
| NetworkManager VPN plugins (OpenVPN, vpnc, OpenConnect, WireGuard) | User request ("do we have network driver/software") | Done — NetworkManager/plasma-nm/iwd/wpa_supplicant/bluez were already present, but without these the Plasma network applet had no way to actually configure a VPN. WireGuard needs no plugin, NM has supported it natively since 1.16 |
| Bottom dock centered instead of full-width | User request ("taskbar needs central, it looks weird") | **Fixed by the Forge Glass revamp**: the panel is now created by a look-and-feel `layout.js` through Plasma's scripting API (`lengthMode = "fit"`, `alignment = "center"`), not a hand-written appletsrc. See below |

## Forge Glass revamp (2026-10-22)

A full visual revamp modelled on the design language of the "Nava OS 1.0"
trailer (youtube.com/watch?v=v2MOPr2SoD0): pastel "liquid glass", a slim
top bar, a floating dock, a summoned command bar, a navy terminal, a
one-word package tool, tiling and workspaces. Nava OS is someone else's
project, so only the *language* is borrowed. Every asset is forge-os's own:
the wallpaper is procedurally generated glass **flames** (not their
mountains), the logo is our flame/anvil emblem re-rendered as a glass tile,
and the tagline is ours ("Built hot. Runs cool.").

| Trailer element | forge-os implementation |
|---|---|
| Pastel liquid glass | `ForgeGlassLight`/`ForgeGlassDark` colour schemes with translucent (alpha) backgrounds; Darkly widget style + window decoration, which turn those into translucent windows, titlebars and menus; `kwin-effects-glass` (replacing the stock blur/contrast) frosts everything translucent: a clear, saturated blur, glass that runs right to the edge with the background bent gently there and no coloured border (`forge glass calm|liquid|bold` switches looks); Konsole at 64% opacity; translucent floating panels; Plus Jakarta Sans (shipped in `/usr/share/fonts`, not packaged). GTK/Chromium apps (Brave, Steam, Pamac) stay opaque |
| Theming | Forge Theming Kit (`apps/forge-themekit`, 2026-10-24): built-in themes and sliders for colour and the liquid glass, applied live; themes as JSON (`~/.config/forge/theme.json`, `themes/`); `forge theme <name>`. Shared Flutter code in `apps/forge_ui` |
| Glass wallpaper | `/usr/share/wallpapers/ForgeGlass` (light `images/` + dark `images_dark/`; Plasma picks by scheme) |
| Top bar + dock | `org.forgeos.glass` look-and-feel `contents/layouts/org.kde.plasma.desktop-layout.js` |
| Control center | Plasma system tray in the top bar |
| Command bar | **Forge Launcher** (`apps/forge-launcher`, Flutter) on Super+Space and Alt+Space: apps, files (Baloo), Forge actions, power, maths, `>` commands, `?` web. Starts hidden at login; a KWin rule (`kwinrulesrc`) makes it a borderless centred card. KRunner keeps Alt+F2 |
| Terminal + package tool | `ForgeGlass` Konsole scheme (translucent navy), zsh prompt, `/usr/local/bin/forge` (`install`/`remove`/`update`/`search`/`theme`/`tile`/`about`, on top of pamac) |
| Tiling, workspaces | `kwin-polonium` (off by default; `forge tile on`), 3 desktops |
| Lock/login | SDDM theme `forge-glass` (Qt 6: thin clock, `MultiEffect`-blurred glass card, session picker); lock screen uses the ForgeGlass wallpaper |
| Splash, boot | `org.forgeos.glass` `Splash.qml`; Plymouth `forge-os` theme restyled; Calamares branding + slideshow |

Light/dark: `org.forgeos.glass.dark` shares the layout and splash
(symlinks) and only swaps scheme + icons. `forge theme dark` switches.

**Assets are generated, not drawn.** `branding-source/glass/generate.py`
renders the wallpapers, logo tile, emblem, Plymouth lockup and progress
bar; `colors.py` writes the KDE and Konsole schemes from one palette;
`desktoptheme.py` writes the Plasma theme (dock dots); `install.sh`
copies renders into `profile/airootfs`. Re-run them after
changing the look. `out/` is gitignored.

**Why a look-and-feel package fixed the two old bugs.** plasmashell builds a
new user's desktop by running `layouts/org.kde.plasma.desktop-layout.js`
from the look-and-feel named in `kdeglobals`, and startplasma copies that
package's `defaults` into `~/.config/kdedefaults` on first login (confirmed
in this machine's `startplasma-wayland`/`libklookandfeel` strings). Our old
skel appletsrc pre-empted the layout script, and WhiteSur's look-and-feel
then won over the wallpaper we'd written. With the appletsrc gone, Plasma
writes the panel geometry itself. Checked by running a fresh-user
`plasmashell` in a headless nested `kwin_wayland --virtual`: the
`plasmashellrc` it saved has the dock at `panelLengthMode=1`, `alignment=132`,
`floating=1`, `panelOpacity=2`, and the desktop containment's wallpaper
points at ForgeGlass.

**Kept from before:** `whitesur-icon-theme` (its rounded-square icons fit
the look; its Apple `start-here` icons are still replaced with our emblem in
`customize_airootfs.sh`). **Dropped:** `whitesur-gtk-theme`,
`whitesur-kde-theme`, `mcmojave-cursors-git`, `ttf-meslo-nerd`, and the
WhiteSur splash/SDDM overrides in `customize_airootfs.sh`.

**Build gotcha:** the WhiteSur `RUN` step in `build/Containerfile` used
`pacman -S` on top of a weeks-old cached base layer and 404'd on moved
packages; it now runs `pacman -Syu`.

**Verified in a QEMU VM (virtio-gpu with GL, 2026-10-22).** The first boot
showed Konsole translucent but not blurred: KWin logged `Effect "glass" was
built for a different version of KWin`, because Chaotic-AUR's
`kwin-effects-glass-git` targeted KWin 6.8.0 and the ISO shipped 6.8.1.
`build/Containerfile` now builds it from AUR against the shipped KWin (see
the comment there), and `forge-glass-check` (an autostart) loads the stock
blur for the session whenever Glass fails to load. After the fix: Glass
loads, Konsole and Dolphin are frosted, Plus Jakarta Sans and the Plymouth
splash are right, and Darkly titlebars are rounded. **Limits:** QtQuick apps
(Welcome Center) and GTK/Chromium apps (Brave, Steam, Pamac) stay opaque:
they don't paint translucent backgrounds from the KDE colour scheme.

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

**WhiteSur's installer needs a fake TERM.** `whitesur-gtk-theme`'s
`install.sh` calls `setterm` for its spinner animation; with no TTY (a
Docker `RUN` step), that fails outright and — because the script wraps
everything in `set -e` and swallows its own stderr into a temp log it
prints only if non-empty — it aborts completely silently, no diagnostic
at all. `build/Containerfile` sets `TERM=xterm` before building it.
Cost real time to track down: had to strip the script's own
`exec 2> logfile` redirect to see the actual `setterm: $TERM is not
defined` error underneath.

**The Plasma panel layout is hand-authored ini, not run through
Plasma.** WhiteSur's look-and-feel packages ship a `layout.js` (Plasma's
scripted layout format) for the top menu bar, but applying that requires
a running `plasmashell`/D-Bus session — not available in a chroot during
the ISO build. Instead, `airootfs/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc`
is a directly-authored copy of what that JS *would* produce (same widget
plugins: kickoff, appmenu, panelspacer, systemtray, digitalclock), plus a
second hand-built bottom-panel containment (`icontasks`) for the dock with
Dolphin/Brave/Steam/Pamac/Konsole/System Settings pinned. This format is
easy to get subtly wrong; **verify it actually renders correctly in a
QEMU boot before trusting it**, and fix forward here if not. (It did,
first try — confirmed live in QEMU.)

*(Superseded by the Forge Glass revamp above: Plasma now creates the dock
itself from a layout script. Kept as a record of what didn't work.)*

**Dock centering took three attempts; the third is sourced from KDE's
actual C++ source, in the right config location this time.**

1. Bare `icontasks`, no constraints at all: rendered full-width, icons
   crammed to one side (the "looks weird" the user flagged).
2. Added `minimumLength`/`maximumLength=560` + `lengthMode=2` +
   `alignment=132` directly under `[Containments][10]`, reasoning from
   [`shell/panelview.h`](https://github.com/KDE/plasma-workspace/blob/master/shell/panelview.h)'s
   `Q_PROPERTY` declarations (`LengthMode { FillAvailable=0, FitContent,
   Custom }`, `Qt::Alignment` with `Qt.AlignCenter`=132). Rebuilt,
   boot-tested, **still full-width** — confirmed via cropping the exact
   panel strip out of a QEMU screenshot and looking at it directly (a
   rounded pill-shape with a visible border ran edge-to-edge). Pixel
   color-sampling alone was **not** a reliable test here once blur is
   enabled — a translucent panel picks up the wallpaper's own color
   underneath, so even a genuinely full-width panel can show a smooth
   gradient with no sharp edges. Crop-and-look-directly was the test that
   actually worked.
3. Fetched [`shell/panelview.cpp`](https://github.com/KDE/plasma-workspace/blob/master/shell/panelview.cpp)'s
   actual save/load code (not just the header's property declarations)
   and found the real problem: `lengthMode`/`minimumLength`/`maximumLength`/
   `alignment` aren't containment properties at all from KConfig's point of
   view — `PanelView::panelConfig()`/`resolutionIndependentConfig()` write
   them to a **separate** group tree, `[PlasmaViews][Panel <id>]` (same
   physical file, `corona->applicationConfig()` resolves to the same
   `plasma-org.kde.plasma.desktop-appletsrc`), under different key names:
   `panelLengthMode` (not `lengthMode`), `minLength`/`maxLength` (not
   `minimumLength`/`maximumLength`, and resolution-*dependent* — nested
   under a further `Horizontal<screen-width-in-px>` group, which only
   applies to one specific monitor resolution). `alignment` is the one key
   that does match by name, but still lives in `[PlasmaViews][Panel 10]`,
   not `[Containments][10]`.

   Current config uses `[PlasmaViews][Panel 10]` with `alignment=132` and
   `panelLengthMode=1` (`FitContent`, not `Custom`) — deliberately avoiding
   `Custom` mode's resolution-*dependent* `minLength`/`maxLength`, since a
   value hardcoded for one screen resolution would be wrong on any other
   monitor. `FitContent` needs no pixel width at all; it just shrinks to
   its content (now just `icontasks` alone — the flanking `panelspacer`
   applets from attempt 2 were removed since `FitContent` + `alignment`
   together already handle both sizing and centering).

   **Rebuilt and boot-tested — still full-width.** Confirmed properly
   this time: cropped the dock row into left-half and right-half images
   and looked at each directly (not pixel-sampling, which had given a
   misleading read earlier in this same investigation — a blurred/
   translucent panel picks up the wallpaper's color underneath it, so
   don't trust color continuity as a proxy for "no panel here"). The
   right-half crop shows one continuous gradient bar with a rounded
   corner only at the true screen edge (x=1280), i.e. the panel still
   spans the full width; `panelLengthMode=1` in `[PlasmaViews][Panel 10]`
   did not change that.

   **Status: unresolved after three attempts, deliberately not attempting
   a fourth blind guess.** Each attempt was reasoned from something
   concrete (a first guess from the JS layout reference, then the actual
   `panelview.h` property declarations, then the actual `panelview.cpp`
   save/load code) and each still didn't work, which suggests either a
   remaining wrong assumption in the group path/key name, or that a
   PanelView's on-disk config genuinely isn't read the same way for a
   freshly-created live-session containment as it is for one that already
   has a running view (i.e. a static pre-seeded file may not be enough —
   it may need to go through Plasma's own save path at least once). The
   reliable way to actually resolve this: from a live KDE session with a
   working mouse (a real machine, or QEMU with a properly-functioning
   graphical console — this session's QEMU setup could take screenshots
   but never got mouse clicks working, see the entry on that further
   down), manually set the panel to a custom/centered width through
   System Settings' own panel-editing UI, then read back whatever
   `plasma-org.kde.plasma.desktop-appletsrc` (and possibly
   `plasmashellrc` — worth checking whether `applicationConfig()` for a
   live corona really does resolve to the same file as assumed here)
   actually contains afterward. That's ground truth; everything in this
   entry is still inference from source code, not observation.

**`grml-zsh-config` (inherited from releng's base rescue-CD package list)
conflicts with a custom `.zshrc`.** It ships its own `/etc/skel/.zshrc`,
which collides with ours (airootfs overlay files aren't pacman-owned, so
pacman refuses to let a package overwrite one — `failed to commit
transaction (conflicting files)`). Removed it from `packages.x86_64`
outright, since it's a minimal rescue-shell config we don't need on a
full desktop system anyway.

*(Root cause found in the Forge Glass revamp above: the skel appletsrc
skipped the look-and-feel layout script, and WhiteSur's look-and-feel
defaults then won.)*

**Desktop wallpaper never actually applied — tried twice, root cause not
found.** `airootfs/usr/share/backgrounds/forge-os/wallpaper.png` exists in
the shipped system, and `plasma-org.kde.plasma.desktop-appletsrc` has an
explicit `[Containments][20]` desktop containment pointing
`Wallpaper/org.kde.image/General/Image` at it — but two rebuilds in a row
still showed WhiteSur's stock wallpaper on boot, confirmed by direct visual
inspection (WhiteSur's wallpaper has a very distinct pink/purple/blue swirl;
ours is a plain dark background with a centered logo — impossible to
mistake one for the other). First attempt used `plugin=org.kde.plasma.folder`
for the containment (wrong — that's the folder-view *applet* id, not a
*containment* id); switched to `plugin=org.kde.desktopcontainment`
(the actual containment plugin), rebuilt, **still didn't apply**. Given how
late this was caught, the second failure wasn't root-caused — ran out of
session time. Worth checking next: whether `[Containments][20]` is even
being read at all (maybe Plasma is auto-creating its own desktop
containment with a different ID before/instead of reading this one — try
dumping a live session's actual `~/.config/plasma-org.kde.plasma.desktop-appletsrc`
after manually setting the wallpaper through System Settings, the same
"let Plasma tell you the ground truth" method that eventually solved the
dock-centering problem below), or whether `LookAndFeelPackage=com.github.vinceliuice.WhiteSur-dark`
in `kdeglobals` is causing WhiteSur's own wallpaper default to get
re-applied over this on every login rather than only on first login.

**Plymouth boot splash: verified working on the live medium; GRUB
background still isn't.** Initially both were assumed untestable without
a real disk boot, but that was wrong for Plymouth specifically — the live
ISO boots through its own initramfs (systemd-boot/syslinux, not GRUB), so
enabling Plymouth there was both possible and worth doing:
- Added the `plymouth` hook to `airootfs/etc/mkinitcpio.conf.d/archiso.conf`
  (right after `udev`, matching the ArchWiki-recommended order) and `quiet
  splash nvidia-drm.modeset=1` to both live boot entries (`syslinux` and
  `systemd-boot`).
- `plymouthd.conf` can't be pre-seeded via the airootfs overlay (the
  `plymouth` package owns that path — another `grml-zsh-config`-class
  conflict), so `customize_airootfs.sh` calls `plymouth-set-default-theme
  forge-os` + `mkinitcpio -P` there instead, same pattern
  `forge-postinstall.sh` already used for the installed system. This runs
  *before* mkarchiso copies `/boot` out of the airootfs, so the
  regenerated initramfs is what actually ships.
- Added a real progress bar to the theme script (`progress_box.png`/
  `progress_bar.png`, generated with ImageMagick, `Scale()`d by
  `progress_callback` — same pattern as Arch's own stock "script" theme).
- **Confirmed live in QEMU**: boots straight to the forge-os logo with a
  visibly filling progress bar, completely replacing the scrolling
  systemd unit list.

GRUB background remains unverified — it only applies post-install through
GRUB, which a live-ISO boot never touches. `GRUB_BACKGROUND` in
`airootfs/etc/default/grub` points at
`/usr/share/backgrounds/forge-os/wallpaper.png`, which does exist in the
shipped system, but confirming it actually renders still needs a real (or
virtual-machine-with-a-disk) install through Calamares.

**Gamescope session is installed but never actually launched.** Adding
`gamescope-session-git` + `gamescope-session-steam-git` should make
"Gamescope Session" appear in SDDM's session dropdown, but this wasn't
selected and booted into during this session (the same blind-mouse-input
problem — selecting a non-default session in SDDM needs a working click,
see above). Confirm it actually appears and starts before relying on it.

**Replacing WhiteSur's Apple branding: found by grepping the actual
package contents, not guessing.** Kickoff's launcher icon turned out not
to be a per-applet setting at all — its `metadata.json` just declares
`Icon: start-here-kde`, a standard XDG icon name resolved through
whatever icon theme is active (WhiteSur-dark). Confirmed by listing
`whitesur-icon-theme`'s actual package contents (`tar -tf` the built
`.pkg.tar.zst`) rather than guessing: it ships `start-here-kde.svg` (and
several size/symbolic variants) styled as an Apple logo. Fix: overwrite
every `start-here*.svg` under `WhiteSur-dark/places/*/` with our own logo
wrapped in a trivial SVG (`<image>` element, PNG base64-embedded — needed
because these are raster PNGs, not real SVGs, but the filenames are
hardcoded with a `.svg` extension in the theme). Same technique reused for
Plasma's splash screen (`Splash.qml` hardcodes `images/logo.svg`) and
SDDM's login screen, the latter via `theme.conf.user` — WhiteSur-dark's
own sanctioned override file (confirmed by reading `Main.qml`'s
`config.background`/`config.logo` bindings back to `theme.conf`), so no
package file needed overwriting there at all, just a background/logo path
override. All three overwrites happen in `customize_airootfs.sh`
(post-install, since these are pacman-owned paths — pre-seeding them via
the airootfs overlay would hit the same file-conflict error
`grml-zsh-config` did).

**Two logo variants, matched to context, both derived from the same
transparent source (`branding-source/forge-os-logo-transparent.png`).**
The user provided a second, better logo (flame/anvil "F" emblem + "FORGE OS"
wordmark, transparent background) and asked for it to replace the boot
splash first, then later the SDDM login logo and the Kickoff icon too
("current one looks out of place"). The boot splash (`plymouth/themes/
forge-os/logo.png`) uses the full logo with the wordmark, resized — it
has enough room and confirmed cleanly. For Kickoff and SDDM, using the
same full logo verbatim would be wrong for one of the two: Kickoff's icon
renders as small as 16-24px, where the "FORGE OS" text underneath the mark
is illegible and just adds visual noise. Found the emblem/wordmark split
point programmatically (summing non-transparent pixels per row with
Pillow found a clean ~20px all-transparent gap at y=1040 in the trimmed
1189x1202 source) and cropped there:
- `forge-os-kickoff-icon.png` (512x512, emblem only, padded to square) —
  used for the Kickoff `start-here*.svg` overrides.
- `forge-os-sddm-logo.png` (700x708, full logo with wordmark) — used for
  SDDM's `theme.conf.user` `logo=` path, since SDDM shows it at a large
  enough size for the wordmark to read fine, same as the boot splash.

The old square badge-crop (`forge-os-logo.png`, a crop of the *first*
logo image with an opaque dark background) is no longer referenced
anywhere and was deleted from `airootfs/usr/share/pixmaps/`.

Watch for one `set -e` trap that would have been easy to ship broken: a
bare `[[ -f "$f" ]] && cp ...` as a **standalone statement** (not inside
an `if`) aborts the whole script under `set -e` the moment the test is
false — which, for a `for f in *.svg` loop, means the very first
non-matching glob expansion kills `customize_airootfs.sh` entirely, with
no error message pointing at why. Rewritten as `if [[ -f "$f" ]]; then
cp ...; fi`, which `set -e` does not treat the same way.

## Deferred (not built this session)

- **KRunner didn't initially list Pamac as an application**, only as a
  "Run pamac" raw command-line match — but running `pamac-manager` directly
  worked fine (it's a real, working install). Likely the KDE application
  cache (`kbuildsycoca6`) just hadn't indexed newly-installed `.desktop`
  files yet in that fresh live session; worth either confirming this
  resolves itself after a normal boot (not our synthetic KRunner-immediately-
  after-desktop-loads test) or forcing a `kbuildsycoca6` run at the end of
  `customize_airootfs.sh` if it doesn't.
- **CachyOS kernel / x86-64-v3 packages**: needs its own separate repo +
  keyring bootstrap (parallel to the Chaotic-AUR one) plus CPU-microarch
  detection to pick v3 vs v4 vs baseline. `linux-zen` ships today as a
  lower-risk performance win; swap it out once the CachyOS repo is wired up
  the same way Chaotic-AUR is.
- **NVIDIA generation detection**: `nvidia-open-dkms` is installed
  unconditionally. Confirmed correct for Turing-and-newer cards, including
  an RTX 3050 (Ampere) — the user testing this has one. Pre-Turing GPUs
  (GTX 16-series and older) still need one of Chaotic-AUR's legacy
  `nvidia-4xxxx-dkms` packages instead — a first-boot or Calamares-time
  `lspci`-based check should pick the right package.
- **Legacy proprietary NVIDIA / secure boot enrollment / any other
  per-machine step**: inherently can't be baked into the ISO; belongs in
  first-boot tooling.
- **kbuildsycoca6 for Pamac/KRunner indexing**: still unresolved from the
  bullet above — deliberately not forced in `customize_airootfs.sh` since
  it's unconfirmed whether it's a real problem on a normal boot (vs. our
  synthetic immediately-after-desktop-loads test) rather than a genuine
  fix-needed gap.

## Phase 2 — Identity & UX

Logo, desktop wallpaper, GRUB background, and a Plymouth boot theme are
now in place (see the feature table and the verification caveats above).
SDDM's login background and logo are now set to forge-os branding via
`theme.conf.user`, applied but not yet visually confirmed (autologin
skips the screen on the live medium — needs a real install with autologin
off, or a manual logout). Still open: an EndeavourOS-style Welcome app for
post-install choices (Flathub opt-in, NVIDIA re-check, optional extra
codecs/DEs) is still just Plasma's generic `plasma-welcome`.

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

### First real install (2026-09-26): what broke, and what's still open

The first install to real hardware (Lenovo laptop, RTX 3050, NVIDIA-only
display) hit ten problems. Fixed in the profile: unpackfs losing its source
under copytoram, `pacman -Rs` aborting on an uninstalled package, an empty
`/boot`, the archiso-only `linux.preset`, `mkinitcpio -P || true` hiding
failures, GRUB unable to read kernels off btrfs (`/boot` is now the ESP),
and 222–327MiB initramfs images overflowing the ESP (now 512MiB minimum,
1GiB recommended). Still to check on a fresh install from the rebuilt ISO:

- **grub rescue from the fallback path.** `bootloader.conf` now sets
  `installEFIFallback: true`, so `EFI/BOOT/BOOTX64.EFI` is written by the
  same install as the NVRAM entry. Check both entries boot, e.g. by picking
  the disk itself (not "forge-os") from the firmware boot menu.
- **Black screen / login loop after SDDM login: likely explained.** A QEMU
  install from the rebuilt ISO showed SDDM preselects "Steam Big Picture"
  (`gamescope-session-steam.desktop` sorts before `plasma.desktop`) on a
  fresh install, and remembers it after a failed login, so every retry
  loops. In QEMU gamescope aborts for lack of Vulkan; on real hardware Steam
  isn't set up yet for a new user either. `forge-postinstall.sh` now
  preselects Plasma via `/var/lib/sddm/state.conf`, and Plasma logs in
  fine that way. Still to confirm on the laptop: that a fresh install goes
  straight to Plasma, and whether the Steam session works once Steam has
  been set up from Plasma.
- **Encrypted and LVM installs.** `forge-postinstall.sh` now adds the
  `encrypt`/`lvm2` hooks and `cryptdevice=` itself; never tested.
- **snapper.** `snapper create-config /` refuses to run when `/.snapshots`
  already exists, and mount.conf always creates it as `@snapshots`. The
  `|| true` hid that: the first install has no snapper config at all.
  `forge-postinstall.sh` now writes the config directly; verified in QEMU
  (`snapper list-configs` shows `root`).
- **Verified in QEMU (2026-09-26)**: install with `copytoram=y` forced
  (unpackfs OK), try_remove, kernels + 15MiB initramfs images on a 1GiB ESP
  (81MiB used), `EFI/boot/bootx64.efi` fallback written, GRUB boots the
  installed disk, no failed units, TTY login works. Also found and fixed
  there: `pacman -Sy` in the post-install chroot couldn't resolve DNS, so
  installs shipped with no repo databases.
