# Forge OS on Hyprland: audit and design (Milestone 0)

Forge OS moves from KDE Plasma to Hyprland. Plasma goes away completely and
Hyprland becomes the only session. The shell (the bar, popups, desktop
widgets, overlays and notifications) is built in Quickshell. Forge Glass and
every Forge app have to keep working. KF6 libraries stay only where Calamares
needs them.

This document covers four things. First, everything that depends on KDE
today and what replaces it. Second, what KDE gave us for free. Third, which
glass sliders have no Hyprland equivalent. Fourth, the package diff, the repo
layout, the release numbering and the risks. It changes no code. Each later
milestone has its own PR, and each waits for an OK before it starts.

Audited on 2026-11-14, against branch `forge-apps-and-glass` (e6de42d) and
the sibling repos `games` (2a19cdc) and `my_linux_configs`. Package versions
come from this machine's sync databases on the same day (`pacman -Si`).

## Findings that change the plan

1. **Hyprland no longer reads `hyprland.conf`.** Arch ships Hyprland
   **0.57.2** (`extra`). The Lua config (`hyprland.lua`) replaced hyprlang in
   0.55, and 0.57.0 removed `.conf` support altogether ("config: remove
   legacy config support"; [hypr.land news](https://hypr.land/news/update57/),
   [Lua-ification](https://hypr.land/news/26_lua/)). This machine's Hyprland
   0.56 already installs `/usr/share/hypr/hyprland.lua` as its only example.
   The M1 spec (`env.conf`, `bindd = ...`, `source`) therefore can't be built
   as written. The same design in Lua is under "Session layout". Only
   Hyprland's own config moved to Lua: hypridle and hyprlock still read
   hyprlang `.conf` files.
   - `bindd` becomes `hl.bind(keys, dispatcher, { description = "..." })`.
     `HL.Keybind` has `description` and `has_description` fields, so
     `hyprctl binds -j` still carries the text that the shortcut panel needs.
   - A comment can't carry the category: comments never reach `hyprctl`. The
     category goes into the description instead, as `[Windows] Close window`.
     A Forge helper adds it, and a lint test fails the build if any bind
     skips the helper.
   - Lua helps in places. Window snapping, per-workspace tiling and the game
     rules can be small Lua functions and `hl.on(...)` event handlers instead
     of shell scripts. The bind options also include `long_press`, which may
     cover "hold Super" in M2 (to verify).
2. **Hyprland draws no titlebars.** Forge Store, Files, Terminal, Theming Kit
   and Thermal deliberately have no GTK header bar today: their runners say
   "KWin draws the titlebar (Darkly...)". On Hyprland they would have no
   title, no close button and no drag area. A newcomer needs those, so
   `forge_ui` gets a client-side title strip: drag, double-click to
   maximise, close, and a hide rule for tiled windows. The other route is
   the `hyprbars` plugin, but `hyprland-plugins` isn't packaged in Arch, and
   plugins have to be rebuilt on every Hyprland update. Not recommended.
3. **Quickshell has no generic D-Bus module for QML.** The panel QML in
   `apps/forge-control/data/qml/org/forgeos/panel` talks to `forged` through
   Plasma's own `org.kde.plasma.workspace.dbus`, and draws with Kirigami.
   Neither exists without Plasma, so this QML can't be reused as it is. Its
   layout and logic port over; its imports don't. Proposal: a new `forged
   watch` command prints the whole state as one JSON line on every `Changed`
   signal, and forge-shell reads it through a Quickshell `Process`. Writes
   go through `forged set` / `forged do`. Everything still goes over
   `forged`'s D-Bus API, unchanged. A small C++ QML D-Bus plugin is the
   fallback if a process turns out too slow.
4. **Darkly needs KDE Frameworks.** `darkly-qt6-git` depends on
   `kdecoration`, `kcmutils`, `kcolorscheme`, `kconfig` and other KF6
   packages, so it goes. Qt apps (Forge Browser, Calamares,
   hyprpolkitagent) get a Kvantum theme instead, generated from
   `theme.json`.
5. **The DND switch relies on a KDE extension.** `Inhibit`, `UnInhibit` and
   the `Inhibited` property are KDE's additions to
   `org.freedesktop.Notifications`, not part of the freedesktop spec.
   Proposal: `forged` keeps the DND state itself (the `dnd` key and its
   API stay the same), and forge-shell's notification server reads it from
   `forged` and holds popups back. Implementing KDE's Inhibit in Quickshell
   isn't needed, because nothing outside Forge in the image calls it.
6. **The Forge configs have to be a package.** The spec wants Forge defaults
   in `/usr/share/forge/hypr` that updates can replace. Files in the airootfs
   overlay aren't owned by pacman and never update. So the session files ship
   in a new `forge-session` package (see "Repo layout"). The same is true
   today of `forged`, `forge` and `forge-theme-sync`, which live in the
   overlay. Moving them into a package would make them updatable as well.
   That's proposed for M3.
7. **Some apps already exist.** `apps/forge-terminal` is a Flutter terminal
   with its own PTY, and the default since `425a7a4`. `apps/forge-files` is
   a Flutter file manager. M5 asks for a new GTK4 + VTE terminal. That means
   replacing the Flutter one, which is your call (see "Open questions").
   Forge Files is the file manager answer below.
8. **The game facts differ from the brief.** Only **Port Calder** and
   **Hardlight** use OpenGL: they link `gl` and ask for a 3.3 context.
   **Ember Isle** links only `sdl2`, like the other vintage games. The games'
   Makefiles have `install` targets but no `DESTDIR`. `PREFIX=$pkgdir/usr`
   would bake the build path into each `.desktop` file's `Exec=`, because
   it's written with `sed 's|@BIN@|$(PREFIX)/bin/...'`. The top-level
   Makefile has no `install` target either. The M4 PKGBUILD has to work
   around this, or the games repo gains `DESTDIR` (a change in that repo).
9. **swww is now awww.** Arch's `extra` ships `awww` 0.12.1; `swww` isn't
   in the repos. Every other piece of the stack is in `extra`: `hyprland`,
   `quickshell` 0.3.2, `hyprpolkitagent`, `xdg-desktop-portal-hyprland`,
   `hypridle`, `hyprlock`, `hyprpicker`, `hyprsunset`, `uwsm`,
   `gpu-screen-recorder`, `cliphist`, `grim`, `slurp`, `qt6ct`, `kvantum`,
   `greetd-regreet`, `nwg-displays`, `udiskie`, `blueman`,
   `nm-connection-editor`, `neovide`, `fastfetch`, `chafa`, `vte4` and
   `gtk4-layer-shell`. Nothing new needs the AUR.

## 1. What depends on KDE today, and what replaces it

### profile/packages.x86_64

| Today | Used for | Replacement |
|---|---|---|
| `plasma-meta` | the whole desktop | `hyprland`, `uwsm`, `quickshell` + `forge-shell`, and the pieces in section 2 |
| `konsole` + `packages/konsole` (keep-translucency patch) | terminal; the Launcher's `> command`, Files' "open terminal" | Forge Terminal (already the default in `xdg-terminals.list`), and `foot` as a small fallback terminal. Remove `packages/konsole` and its build deps in `build/Containerfile` (M5, or M1 if you agree) |
| `kwin-effect-rounded-corners-git`, `kwin-effects-glass-git` | rounded corners, glass | Hyprland's `decoration` block: `rounding`, `rounding_power`, `blur` (size, passes, vibrancy, noise, contrast, brightness, popups), `shadow`. 0.57 adds blur variants (to evaluate in M1). See section 3 for what's lost |
| `kwin-polonium` | auto-tiling (`forge tile`) | Hyprland tiles natively (dwindle). Tiling becomes per workspace, see "Tiling model" |
| `darkly-qt6-git` | Qt style + window decoration (translucent Qt windows) | Kvantum theme generated from `theme.json`, via `qt6ct` |
| `xdg-desktop-portal-kde` | portals | `xdg-desktop-portal-hyprland` (screencast, screenshot, global shortcuts) + `xdg-desktop-portal-gtk` (file chooser, appearance settings), with `hyprland-portals.conf` choosing `hyprland;gtk` |
| `plasma-nm` | Wi-Fi/VPN applet and NM secret agent | Forge Control's Wi-Fi popup (forged); `nm-connection-editor` for VPN and advanced settings; `network-manager-applet` only as the secret agent for VPN and 802.1X prompts, its tray icon filtered out by forge-shell, until forge-shell or forged carries its own agent |
| `kdeconnect` | phone link | dropped (it's a KDE app). Optional later |
| `kdegraphics-thumbnailers`, `ffmpegthumbs`, `kimageformats` | Dolphin thumbnails, extra image formats | Forge Files already thumbnails through `ffmpeg` and `poppler`; `qt6-imageformats` for Qt |
| `spectacle` | screen recording (Forge Shot took the screenshots) | `gpu-screen-recorder` (NVENC), driven by Forge Shot (M3) |
| `dolphin`, `dolphin-plugins` | file manager; Forge Shot's "Show in folder" | Forge Files, which also implements `org.freedesktop.FileManager1` (ShowItems) so "Show in folder" works from any app |
| `kate`, `ark`, `gwenview`, `okular`, `kcalc`, `filelight`, `partitionmanager`, `print-manager`, `kwalletmanager` | everyday apps | stopgaps until Forge versions exist: `gnome-text-editor` (until Forge Code, M8), `file-roller`, `loupe`, `papers`, `gnome-calculator`, `forge space` (Forge Mind) for disk use, `gparted`, `system-config-printer`, `seahorse`. All GTK4/GTK3, all in `extra`. Your call; see "Open questions" |

`sddm` stays (see "SDDM or greetd"). `pipewire`, `networkmanager` and its
VPN plugins, `bluez`, `power-profiles-daemon`, `whitesur-icon-theme` and the
gaming stack don't depend on KDE.

### etc/skel KDE files

| File | Today | Replacement |
|---|---|---|
| `kdeglobals` | colour scheme, fonts, icons, look-and-feel | `~/.config/forge/theme.json` (already the Forge apps' source); GTK `settings.ini` + gsettings for fonts and icons; `qt6ct.conf` + Kvantum for Qt |
| `kwinrc` | glass, corners, Polonium, 3 desktops | `/usr/share/forge/hypr/look.lua`; workspaces are dynamic in Hyprland |
| `kwinrulesrc` | Launcher as a borderless centred card | the Launcher becomes a layer-shell surface and needs no rule; window rules in `rules.lua` |
| `kglobalshortcutsrc` | Launcher, Forge Shot keys; Spectacle's off | `keybinds.lua` |
| `krunnerrc` | KRunner settings | dropped (the Launcher replaced KRunner; Alt+F2 moves to the Launcher) |
| `kscreenlockerrc` | lock screen wallpaper | `hyprlock.conf` |
| `konsolerc`, `.local/share/konsole/forge-os.profile` | Konsole profile | dropped with Konsole |
| `darklyrc` | Darkly opacities, corner radii | dropped; Kvantum config generated by forge-theme-sync |
| `mimeapps.list`, `xdg-terminals.list` | Forge apps as defaults | kept as they are |

Also KDE-only and to be removed: `usr/share/plasma/look-and-feel/org.forgeos.glass{,.dark}`,
`usr/share/plasma/desktoptheme`, `usr/share/color-schemes/ForgeGlass*.colors`,
`usr/share/konsole/ForgeGlass.colorscheme`, `etc/xdg/autostart/forge-glass-check.desktop`.

### forged

| Today | Replacement |
|---|---|
| brightness through `org.kde.ScreenBrightness` (read, set, `BrightnessChanged`) | read `/sys/class/backlight/*/{brightness,max_brightness}`; set with logind's `org.freedesktop.login1.Session.SetBrightness` on the caller's session (no root, no new package). Brightness keys call `forged set brightness +5/-5`, so forged signals `Changed` and forge-shell shows the OSD. `brightnessctl` stays as the CLI fallback |
| dark mode from `kreadconfig6 kdeglobals ColorScheme` (fallback) | `theme.json` only (it already reads it first) |
| tiling from `kreadconfig6 kwinrc poloniumEnabled` | Hyprland state: workspaces whose tiling is off, from `~/.local/state/forge/tiling.json`, which the Lua config also reads. Gains a per-workspace form; the old `tiling` key keeps working and means "the focused workspace" |
| file monitors on `kdeglobals` and `kwinrc` | monitor `theme.json` and `tiling.json` only |
| DND through `org.freedesktop.Notifications.Inhibit` (KDE extension) | forged holds the DND state; forge-shell's notification server follows it (finding 5) |
| (new) | `forged watch` for forge-shell (finding 3); a BlueZ `Agent1` so pairing a new device can confirm a PIN in the shell (M3) |

The D-Bus API (`State`, `Set`, `Do`, `Media`, `Changed`) stays as it is.
New keys and actions are additions.

### The forge CLI and the system tools

| Tool | KDE today | Hyprland |
|---|---|---|
| `forge tile [on\|off]` | writes `poloniumEnabled` to kwinrc, `qdbus6 org.kde.KWin /KWin reconfigure` | `forged set tiling on\|off` for the focused workspace; `forge tile <ws> on\|off`; `forge tile all on\|off` |
| `forge glass calm\|liquid\|bold` | writes `[Effect-blurplus]`, reloads the Glass effect over D-Bus | updates the glass preset in `theme.json`; forge-theme-sync writes `~/.config/forge/hypr/theme.lua`; `hyprctl reload` |
| `forge theme [light\|dark\|name]` | `plasma-apply-lookandfeel`, `kreadconfig6` | writes `theme.json`, runs forge-theme-sync |
| `forge-theme-sync` | reads light/dark and the accent from `kdeglobals` via `kreadconfig6`; leans on KDE for GTK colours.css and the portal | reads `theme.json` only and writes every target itself: Hyprland theme Lua, GTK 3/4 css, Kvantum/qt6ct, gsettings (color-scheme, accent: the GTK portal reads these for Firefox/Chromium/Electron/libadwaita), the terminal, Neovim, the SDDM theme, fastfetch, the shell prompt; then `hyprctl reload` |
| `forge-glass-check` | autostart that falls back to stock blur when KWin Glass fails to load | removed. Its role (tell the user the desktop config is broken) becomes the config-error notifier in M7 |
| `forge-theme-login` | writes the SDDM theme's `theme.conf.user` | unchanged if SDDM stays |
| `branding-source/glass` | `desktoptheme.py` (Plasma theme), `colors.py` (KDE + Konsole schemes) | delete `desktoptheme.py`; `colors.py` keeps the palette but writes Hyprland, GTK and Kvantum colours; `generate.py` (wallpapers, logo, Plymouth) and `install.sh` stay, with new targets |

### The Forge apps

| App | KDE today | Hyprland |
|---|---|---|
| **forge-control** | 5 Plasma widgets (`org.forgeos.control/battery/wifi/bluetooth/volume`), QML module `org.forgeos.panel` (Kirigami, Plasma components, `org.kde.plasma.workspace.dbus`), Flutter Control Center panel on gtk-layer-shell, `PlasmaCore.Dialog` popups | the bar widgets and popups are rewritten in Quickshell inside forge-shell. The logic and the look of `Forged.qml`, `BarButton.qml`, `ListRow.qml` and the popups carry over; Kirigami and PlasmaCore are replaced by a `ForgeTheme` QML singleton (from `theme.json`) and Quickshell's `PopupWindow`. Recommended: the Control Center itself moves to Quickshell too, retiring the Flutter panel (one process, opens instantly, a real layer surface Hyprland can blur). Open question 5 |
| **forge-shot** | captures through `org.kde.KWin.ScreenShot2`, `X-KDE-DBUS-Restricted-Interfaces`, KWin's window picker, `kdialog` Save As, `dolphin --select` | `grim` captures the whole output first (keeps the "frozen screen" design, so `slurp` isn't needed for areas); the existing layer-shell overlay selects; a window comes from `hyprctl clients -j` geometry, clicked on the same overlay; Save As through the GTK/portal file chooser; "Show in folder" through `FileManager1`. Recording with `gpu-screen-recorder` (`-w screen` or `-w portal`), NVENC/VAAPI. `capture.cc` is replaced, the Flutter UI stays |
| **forge-launcher** | KWin rule centres it, `kglobalshortcutsrc` binds it, `konsole --hold` for commands, `qdbus6 org.kde.Shutdown` for log out, reboot and shut down, Baloo when Forge Mind is missing; depends on `konsole`, `baloo` | gtk-layer-shell (overlay layer, exclusive keyboard, no anchors = centred); bound in `keybinds.lua` to its existing toggle; commands in Forge Terminal; `loginctl`/`systemctl` for power and `uwsm stop` to log out; Forge Mind only (Baloo is KDE) |
| **forge-themekit** (`lib/apply.dart`) | `kwriteconfig6` kwinrc/darklyrc, `qdbus6` KWin reconfigure and effect reloads, `plasma-apply-colorscheme`, `plasma-changeicons`, Konsole scheme writes; PKGBUILD needs `kconfig`, `qt6-tools`, `plasma-workspace`, `kwin-effects-glass-git` | writes `theme.json` and runs forge-theme-sync, which writes everything else. The sliders are remapped (section 3) |
| **forge_ui** | `palette.dart` falls back to kdeglobals for dark; `scheme.dart` writes KDE and Konsole colour schemes; comments assume KWin frosts the window | `theme.json` only; `scheme.dart` writes the Kvantum and terminal colours instead; a client-side title strip (finding 2) |
| **forge-terminal** | reads `kdeglobals` for dark and the fixed-width font; colours from the Konsole scheme | `theme.json` and fontconfig's `monospace`; then M5 |
| **forge-files** | "open terminal here" runs `konsole --workdir`; no header bar | Forge Terminal; title strip; gains `FileManager1` |
| **forge-store**, **forge-thermal**, **forge-calendar** | no header bar ("KWin draws the titlebar") | title strip; the Store's pamac transactions get their password prompt from hyprpolkitagent |
| **forge-browser** | Qt Widgets with Darkly | Kvantum; `QT_WAYLAND_DISABLE_WINDOWDECORATION=1` so Qt draws no fallback titlebars |

### Build, installer and first boot

| File | KDE today | Change |
|---|---|---|
| `build/Containerfile` | builds `kwin-effects-glass-git` against the shipped KWin (`KWIN_VERSION`); Konsole build deps (`konsole extra-cmake-modules kdoctools`) for `packages/konsole` | remove both steps. Calamares' build (`kcoreaddons kpmcore extra-cmake-modules libpwquality`) stays |
| `build/build.sh` | queries archlinux.org for KWin's version to bust the cache | remove |
| `apps/build-packages.sh` | builds `packages/*` (Konsole) and the apps | builds the new packages (`forge-session`, `forge-shell`, later `forge-games` and the rest); no logic change |
| `customize_airootfs.sh` | enables sddm; replaces WhiteSur's Apple `start-here` icons ("Kickoff's default icon"); installs `org.gtk.Gtk3theme.Breeze` for Flatpak | sddm stays; the icon replacement stays (other apps ask for `start-here` too); Flatpak gets `org.gtk.Gtk3theme.adw-gtk3` instead of Breeze; add `systemctl --global enable` for the session's user units (see "Session layout") |
| `forge-postinstall.sh` | pre-selects `/usr/share/wayland-sessions/plasma.desktop` in `/var/lib/sddm/state.conf` | pre-select `hyprland-uwsm.desktop`. **An installer change: needs your OK** |
| `etc/sddm.conf.d/autologin.conf` | live user, `Session=plasma` | `Session=hyprland-uwsm` |
| `etc/calamares/modules/displaymanager.conf` | `sddm` | unchanged with SDDM |
| Live session | Plasma; the user opens Calamares from the desktop | the live user's `hyprland.lua` starts Calamares on login (`sudo -E calamares`, already passwordless in the live image), with the Forge bar still up so Wi-Fi can be joined first. **An installer change: needs your OK** |

### SDDM or greetd

**Recommendation: keep SDDM.** The Forge Glass theme
(`usr/share/sddm/themes/forge-glass`) imports only `QtQuick`,
`QtQuick.Controls.Basic` and `QtQuick.Effects`, with no KDE modules, so it
works unchanged. Calamares' `displaymanager` module already configures
SDDM. Live autologin and the session pre-selection already work through
it. `forge-theme-login` already themes it. greetd + ReGreet would mean a
new GTK4 greeter theme, a new autologin path, a Calamares config change and
a new way for the login screen to follow the theme. That's a lot of risk to
the installer for no visible gain. Revisit only if SDDM's own (X11 or
Wayland) greeter misbehaves on NVIDIA.

## 2. What KDE gave us for free

| Need | KDE had | Replacement |
|---|---|---|
| Session start, systemd integration, XDG autostart | startplasma | **uwsm** (`hyprland-uwsm.desktop`): Hyprland runs as a systemd user unit, user services and D-Bus activation get the right environment (forged and Forge Mind are D-Bus-activated), and `/etc/xdg/autostart` entries run, which matters because Launcher, Control and Calendar ship autostart files |
| Polkit agent | polkit-kde-agent | `hyprpolkitagent` (Qt6/QML, `extra`), as a user service |
| Portals | xdg-desktop-portal-kde | `-hyprland` + `-gtk`, with `hyprland-portals.conf` |
| Qt theming | Plasma platform theme + Darkly | `qt6ct` platform theme + Kvantum "ForgeGlass" (generated) |
| GTK theming | kde-gtk-config writing colours.css, Breeze GTK | `adw-gtk-theme` + forge-theme-sync writing `gtk.css` colour overrides for GTK 3 and 4; gsettings for color-scheme, accent, font, icons, cursor |
| File manager | Dolphin | Forge Files (already the default for folders) |
| Network and VPN editor | plasma-nm, its KCM, its secret agent | Forge Control + `nm-connection-editor` + `nm-applet`'s agent (see above) |
| Idle and lock | PowerDevil, kscreenlocker | `hypridle` + `hyprlock` (Forge Glass); `hypridle` honours D-Bus and systemd inhibitors, and gamemode's start/stop hooks hold an idle inhibitor (`systemd-inhibit --what=idle`) while a game runs |
| Volume, brightness, caps lock OSDs | Plasma OSD | forge-shell (M2). In M1, keys work without an OSD |
| Clipboard history | Klipper | `cliphist` + `wl-clipboard` (Super+V picker in M2); `wl-clip-persist` keeps a copy after its app closes, as Klipper did |
| Auto-mount | Solid/KIO device notifier | `udiskie --no-tray --notify` (udisks2), as a user service |
| Bluetooth pairing | bluedevil wizard and agent | Forge Control's popup + a BlueZ agent in forged (M3); `blueman-manager` as the interim pairing UI |
| Display settings | KScreen | `nwg-displays` interim → Forge Settings' displays page (M7), writing `~/.config/hypr/monitors.lua` |
| Night light | KWin Night Light | `hyprsunset` (a Control Center toggle in M2) |
| Secrets (browser passwords, git, NM) | KWallet + pam_kwallet | `gnome-keyring` + `libsecret`, unlocked at login by PAM (`pam_gnome_keyring` in SDDM's PAM stack) |
| Notifications | Plasma's server (with Inhibit) | forge-shell (Quickshell `NotificationServer`), M2. In M1 a stopgap is needed. Proposed: no daemon; apps that require one queue silently. Or `mako` for M1 only, if you'd rather see them |
| Fonts and emoji | pulled in by plasma-meta | listed explicitly: `noto-fonts`, `noto-fonts-emoji` (the emoji picker needs them), `noto-fonts-cjk` |
| UPower, ddcutil, kscreen helpers | pulled in by plasma-meta | `upower` listed explicitly (forged reads the battery from it) |
| Cursor theme | Breeze cursors | a cursor theme in `extra` or Chaotic-AUR, chosen in M1 (hyprcursor + xcursor) |
| Recovery when the shell dies | plasmashell restarts itself | forge-shell runs as a systemd user unit with `Restart=on-failure`; a "restart shell" bind; `foot` reachable on a bind even if forge-shell is down |

## 3. Glass sliders with no Hyprland equivalent

The Theming Kit's liquid-glass sliders drive KWin Glass (`[Effect-blurplus]`).
Hyprland's `decoration:blur` is a plain dual-Kawase blur with `vibrancy`,
`noise`, `contrast` and `brightness`. It has no refraction, so:

| Slider (theme.json key) | KWin Glass key | Hyprland | Proposal |
|---|---|---|---|
| Blur (`blur`) | BlurStrength 1–15 | `blur.size` + `blur.passes` | **map**: a table from the 1–15 scale to size/passes, tuned by eye |
| Vibrancy (`saturation`) | Saturation | `blur.vibrancy` (+ `vibrancy_darkness`) | **map** |
| Grain (`grain`) | NoiseStrength | `blur.noise` | **map** |
| Lens width (`lensWidth`) | RefractionEdgeSize | none | **approximate as an "edge sheen"**: a thin `col.active_border` gradient from the glass tint to transparent, with lens width setting its width and lens strength its alpha. It reads as a lit edge, not bent light. If it doesn't look right in M1, drop it |
| Lens strength (`lensStrength`) | RefractionStrength | none | folded into the edge sheen above, or dropped with it |
| Bevel (`bevel`) | RefractionBevelIntensity | none | **drop** |
| Inner bending (`innerBend`) | BodyRefractionStrength | none | **drop** (already off in Forge Glass) |
| Colour split (`colourSplit`) | RefractionRGBFringing | none | **drop** (already 0 in Forge Glass) |
| Corners (`cornerRadius`) | Round-Corners Size | `decoration.rounding` | **map**; also a new **corner shape** slider (`rounding_power`, a squircle as on macOS) |
| Window / menu / terminal opacity | colour scheme alpha, Darkly, Konsole | per-app alpha (theme.json) + `active_opacity`/`inactive_opacity` rules | **map** |
| (new) Shadow | — | `decoration.shadow` | **add** |
| (new) Blur behind popups and the bar | — | `blur.popups`, layer rules for the `forge-*` namespaces | **add** (on) |

The kit hides dropped sliders instead of deleting their keys, so a
`theme.json` from 2.x still loads. A "true refraction" Hyprland plugin
(custom shader) is possible, but plugins break on every Hyprland release and
aren't packaged; not proposed. Hyprland 0.57's new blur variants get
evaluated in M1 in case one is closer to the KWin look.

## 4. Design for the next milestones

### Session layout (M1, in Lua)

```
/usr/share/forge/hypr/        (package forge-session; replaced on update)
  forge.lua         entry: loads the modules below in order
  env.lua           NVIDIA and toolkit env (see below)
  look.lua          Forge Glass: blur, rounding, shadows, animations, gaps;
                    reads ~/.config/forge/hypr/theme.lua (generated)
  input.lua         keyboard, touchpad (natural scroll, tap), gestures
  rules.lua         window and layer rules, game rules
  keybinds.lua      every bind, through forge.bind()
  autostart.lua     hl.on("hyprland.start", ...) for what systemd can't own
  lib/bind.lua      forge.bind(category, keys, description, dispatcher, opts)
  lib/snap.lua      Super+arrows: snap a floating window to halves/quarters
  lib/tiling.lua    per-workspace tiling from tiling.json
  hypridle.conf, hyprlock.conf   (hyprlang: these tools didn't move to Lua)

~/.config/hypr/               (from /etc/skel; never written by an update)
  hyprland.lua      3 lines: add /usr/share/forge/hypr to package.path,
                    require("forge"), then load user.lua if it exists
  user.lua          the user's overrides (empty, commented)
  keybinds.user.lua written by Forge Settings (M7)
  monitors.lua      written by Forge Settings (M7)
  hypridle.conf, hyprlock.conf   `source` the Forge defaults, then overrides
~/.config/forge/hypr/theme.lua   generated by forge-theme-sync (colours, glass)
```

`colors.conf` from the spec becomes `theme.lua`, under `~/.config/forge`
because a script writes it, and the user never edits it. Before M1 is
built, a quick check covers whether Hyprland's Lua allows `package.path`
changes and `dofile` (the example config documents `require`).

Each bind looks like this:

```lua
-- Windows
forge.bind("Windows", "SUPER + Q", "Close window", hl.dsp.window.close())
```

That gives `hyprctl binds -j` the description `[Windows] Close window`. A
test (M1) loads the bind modules with a stub `hl` and fails when a bind has
no category or description, or when two binds share a key.

### Keymap draft (for review before M1)

Windows/macOS habits first. Everything is visible on the shortcut panel and
the Super+/ cheat sheet.

| Category | Keys | Action |
|---|---|---|
| Apps | Super+Return | Terminal |
| Apps | Super+E | Files |
| Apps | Super+B | Browser |
| Apps | Super+Space, Alt+Space, Alt+F2 | Launcher |
| Apps | Super+\` | Drop-down terminal (M5) |
| Apps | Super+I | Settings (Theming Kit until M7) |
| Apps | Super+G | Forge Arcade / game overlay (M4) |
| Apps | Ctrl+Shift+Esc | System monitor |
| Shell | Super+A | Control Center |
| Shell | Super+N | Notifications |
| Shell | Super+/ | Shortcut cheat sheet (M2) |
| Shell | hold Super | Which-key popup (M2) |
| Shell | Super+V | Clipboard history (M2) |
| Shell | Super+. | Emoji picker (M2) |
| Shell | Super+Shift+C | Colour picker |
| Windows | Super+Q, Alt+F4 | Close window |
| Windows | Super+Up | Maximise |
| Windows | Super+Down | Restore, or minimise (to a hidden special workspace) |
| Windows | Super+Left / Right | Snap to the left/right half (floating) or move left/right (tiled) |
| Windows | Super+Alt+arrows | Focus the window in that direction |
| Windows | Super+F | Full screen |
| Windows | Super+T | Float or tile this window |
| Windows | Super+Shift+T | Tiling on or off for this workspace |
| Windows | Alt+Tab, Alt+Shift+Tab | Switch windows (cycle in M1, the switcher in M2) |
| Windows | Super+R | Resize mode: arrows resize, Enter/Esc leave (hint on screen) |
| Windows | Super+M | Move mode: arrows move, Enter/Esc leave (hint on screen) |
| Windows | Super+drag, Super+right-drag | Move, resize |
| Workspaces | Super+1…9 | Go to workspace |
| Workspaces | Super+Shift+1…9 | Move window to workspace |
| Workspaces | Super+Ctrl+Left / Right | Previous / next workspace |
| Workspaces | Super+Tab | Overview (M2) |
| Workspaces | 3-finger swipe, Super+scroll | Previous / next workspace |
| Screenshots | Print, Super+Shift+S | Screenshot an area |
| Screenshots | Shift+Print | Screenshot the screen |
| Screenshots | Super+Print | Screenshot a window |
| Screenshots | Super+Alt+R | Start / stop recording |
| System | Super+L | Lock |
| System | Ctrl+Alt+Delete | Power menu (lock, log out, restart, shut down) |
| System | Super+Shift+N | Do not disturb |
| System | media, volume, brightness keys | through forged (OSD in M2) |

### NVIDIA (env.lua)

The RTX 3050 laptop drives its display from the NVIDIA GPU (ROADMAP: "NVIDIA-only
display"). Other hybrid laptops render on the iGPU. Setting the NVIDIA GLX/GBM
variables everywhere would force every app onto the dGPU and drain the
battery. So a small `forge-gpu-env` runs at session start (a uwsm env
hook, since uwsm sessions read env from there rather than from `hl.env`).
It looks at which DRM card has the connected outputs and sets:

- NVIDIA drives the display: `LIBVA_DRIVER_NAME=nvidia`,
  `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `NVD_BACKEND=direct`,
  `ELECTRON_OZONE_PLATFORM_HINT=auto`.
- Hybrid: `AQ_DRM_DEVICES` with the iGPU first, and no NVIDIA GLX override.
  Games already pick the dGPU through PRIME offload (`prime-run`, Steam's
  launch options).
- Always: `QT_QPA_PLATFORM=wayland;xcb`, `QT_QPA_PLATFORMTHEME=qt6ct`,
  `QT_WAYLAND_DISABLE_WINDOWDECORATION=1`, `GDK_BACKEND=wayland,x11`,
  `SDL_VIDEODRIVER=wayland,x11`, `XCURSOR_*`/`HYPRCURSOR_*`.

Explicit sync needs driver 560 or newer. The pinned 610.57.04 qualifies, and
Hyprland turns it on by default. The kernel needs `nvidia-drm.modeset=1`
(the ISO already sets it) and `fbdev=1`. Suspend needs the
`nvidia-suspend/hibernate/resume` services and
`NVreg_PreserveVideoMemoryAllocations=1`. M1 checks all of this on the
laptop, including VRR and tearing in games, and hyprlock after resume.

### Tiling model

New users start with tiling **off** (windows float, Super+arrows snap, as on
Windows). That matches 2.x, where Polonium was off. Hyprland has no
per-workspace "float everything" switch, so `lib/tiling.lua` keeps a set of
floating workspaces in `tiling.json`. A window rule floats new windows that
open there, and a toggle floats or tiles the windows already there. forged
reads the same file. M1 verifies that this works without flicker; the
fallback is a dynamic window rule per workspace.

### Game mode

- Rules in `rules.lua` for `steam_app_*`, `gamescope`, Lutris, Heroic and the
  forge-games binaries: full screen allowed, `immediate` (tearing) on, idle
  inhibited while full screen.
- An `hl.on` handler for full-screen changes turns blur, shadows and
  animations off while a game is full screen and back on after. This is Lua
  inside Hyprland, so no process is involved.
- `forge-gamewatch`, a small script on Hyprland's event socket (as the brief
  asks), pauses the live wallpaper (forge-shell) and switches the thermal
  profile through forged while a game is full screen, and puts both back
  afterwards. The thermal half could live in forged instead, which already
  watches everything else. Your call.
- GameMode's start/end hooks hold the idle inhibitor (section 2).

### forge-shell (M2) shape

One Quickshell config under `/usr/share/forge/shell` (package `forge-shell`).
Its parts: `Bar`, `ControlCenter`, `Popups/{Wifi,Bluetooth,Volume,Battery}`,
`Notifications`, `Osd`, `ShortcutPanel`, `CheatSheet`, `WhichKey`,
`Overview`, `Switcher`, `Pickers/{Clipboard,Emoji}`, and `Wallpaper` (the
background layer, so it can pause shader and video wallpapers itself).

- State: `Forged.qml` runs `forged watch` (finding 3).
- Theme: `ForgeTheme.qml` watches `theme.json`.
- Workspaces and focused window: `Quickshell.Hyprland`.
- Battery: UPower. Media: MPRIS. The rest: forged.
- Overview previews: Quickshell's `ScreencopyView` (hyprland-toplevel-export).
- Shortcut data: `hyprctl binds -j`, reloaded on Hyprland's `configreloaded`
  event.
- It runs as a uwsm/systemd user service.

## 5. Package list diff (proposed)

**Remove** (KDE): `plasma-meta dolphin dolphin-plugins konsole kate ark
gwenview okular spectacle kcalc kdeconnect filelight partitionmanager
ffmpegthumbs kdegraphics-thumbnailers kimageformats print-manager
xdg-desktop-portal-kde plasma-nm kwalletmanager kwin-effect-rounded-corners-git
kwin-effects-glass-git darkly-qt6-git kwin-polonium`; the local
`packages/konsole` build.

**Keep**: `sddm`, `pipewire*`, `wireplumber`, `networkmanager` and its VPN
plugins, `wireguard-tools`, `bluez*`, `power-profiles-daemon`,
`whitesur-icon-theme`, `ttf-jetbrains-mono-nerd`, the gaming stack,
`calamares` (and the KF6 libraries it pulls in: kpmcore, kcoreaddons, etc.),
all Forge apps.

**Add, M1** (all in `extra` unless noted): `hyprland uwsm
xdg-desktop-portal-hyprland xdg-desktop-portal-gtk hyprpolkitagent hypridle
hyprlock hyprpicker hyprsunset hyprland-guiutils qt6-wayland qt5-wayland
qt6ct kvantum adw-gtk-theme grim slurp wl-clipboard cliphist wl-clip-persist
brightnessctl playerctl udiskie gnome-keyring libsecret upower
nm-connection-editor network-manager-applet blueman foot nwg-displays
noto-fonts noto-fonts-emoji noto-fonts-cjk`, a cursor theme, the new
`forge-session` package. Stopgap apps if you agree: `gnome-text-editor
file-roller loupe papers gnome-calculator gparted system-config-printer
seahorse`.

**Add, later**: `quickshell` + `forge-shell` (M2), `gpu-screen-recorder`
(M3), `forge-games` + `forge-arcade` (M4), `vte4` + `fastfetch` + `chafa`
(M5), `awww` + `forge-wallpapers` (M6), `forge-settings` (M7), `neovim`,
`forge-code` and the language servers as Arch packages (M8; repo packages
instead of mason downloads, so it works offline from the ISO), `neovide`
(M8, optional).

To check in M1 against the built image: what `plasma-meta` was pulling in
that something else silently relied on (UPower and the fonts are known; a
`pacman -Qi` diff between the 2.x image and the new one will show the rest).

## 6. Repo layout for the new parts

```
apps/forge-session/      Hyprland defaults (/usr/share/forge/hypr), skel
                         stubs, forge-gpu-env, forge-gamewatch, hypridle and
                         hyprlock defaults, user units; tests/ for the bind
                         lint (M1)
apps/forge-shell/        Quickshell QML (/usr/share/forge/shell), user unit (M2)
apps/forge-arcade/       Flutter on forge_ui (M4)
packages/forge-games/    PKGBUILD building github.com/abhijiths1998/games (M4)
apps/forge-terminal/     GTK4 + VTE rewrite (M5), if you choose it
apps/forge-wallpapers/   Flutter on forge_ui (M6)
branding-source/cast/    Forge cast SVG sources + export script (M6)
apps/forge-settings/     Flutter on forge_ui (M7)
packages/forge-code/     Neovim distribution (/usr/share/forge/nvim) (M8)
apps/forge-welcome/      Welcome screen + Keyboard Dojo (M9)
tests/                   forged and forge-theme-sync tests (M3)
```

Each app keeps a README, a PKGBUILD and a `.desktop` file, and builds
through `apps/build-packages.sh`.

`apps/forge-shell/` (untracked build output: `build/`, `linux/`) and
`compositor/` (`target/`) are left over from the dropped Flutter shell and
Rust compositor, whose source is on `archive/forge-desktop`. The new
`apps/forge-shell` needs that path, so the leftovers have to go first. They
aren't KDE-specific, so this needs your OK (open question 7).

## 7. Release numbering (proposal)

2.0 (built, not released) and 2.1 (in progress) are KDE releases. The move
to Hyprland is a new base, so it starts a new major line:

| Version | Content | Milestones |
|---|---|---|
| 2.x | KDE line: frozen. No 2.x ISO is released unless you want one last KDE image | — |
| **3.0** | Hyprland base, forge-shell, every Forge app ported, theme sync | M1–M3 |
| 3.1 | Forge Arcade + Forge Terminal + fastfetch | M4–M5 |
| 3.2 | Forge cast + Forge Wallpapers (the old 2.2 "living desktop") | M6 |
| 3.3 | Forge Settings + keybind editor (part of the old 3.0) | M7 |
| 3.4 | Forge Code | M8 |
| 3.5 | Onboarding: Welcome + Keyboard Dojo | M9 |
| 3.6+ | the old 2.3 Assistant, 2.4 safe updates and Game Hub, 2.5 Focus and Dynamic Island, in that order | — |

`forge-os-release` moves to `VERSION=3.0` when M1 lands, marked as a
development build until M3 is accepted. RELEASES.md is rewritten to this
table once you approve it. Until then it only points here.

## 8. Risks

1. **Hyprland changes under us.** The config format changed twice in three
   releases (Lua in 0.55, `.conf` removed in 0.57), and 0.57.1 fixed NVIDIA
   black screens. An Arch update can break the session. Mitigation: hold
   `hyprland`, `aquamarine` and `hyprutils` in `IgnorePkg`, as the NVIDIA
   driver already is, and move the pin only after checking a new release
   on the laptop. The real fix is the Forge repo (ROADMAP Phase 3).
2. **NVIDIA.** There are three ways to get it wrong: hybrid vs dGPU-only
   setup, explicit sync, and suspend/resume. On top of that, the hard game
   freezes are still unexplained (the 615 driver froze games; 610 is
   pinned). Any freeze on the new session will look like Hyprland's fault
   whatever the cause. The freeze logger in `utils/` stays in the image.
3. **No titlebars** (finding 2). Every Forge app needs the forge_ui title
   strip before it's usable floating. This has to be done before M2's
   acceptance, not at M3.
4. **Liquid glass gets weaker.** No refraction (section 3). The look will
   read as "frosted" rather than "liquid". Worth a side-by-side screenshot
   review in M1.
5. **Quickshell is 0.x.** Its API changes between releases, and it has no
   generic D-Bus module (finding 3). Pin it the same way as Hyprland.
6. **Calamares as root on Wayland.** It needs the right `WAYLAND_DISPLAY`
   and `XDG_RUNTIME_DIR`, a polkit agent and Qt's Wayland plugin. Testable
   in QEMU.
7. **There is no upgrade path from 2.x.** Moving an installed KDE system
   to Hyprland would mean migrating skel-era configs and KWallet secrets
   (Brave passwords, Wi-Fi keys stored per user). Proposed: 3.0 is
   fresh-install only. Open question 3.
8. **QEMU can't test what matters most.** It can't test NVIDIA. Mouse
   clicks didn't work in this setup's QEMU before (ROADMAP), and Hyprland
   in QEMU needs virtio-gpu with GL. Keybinds can be driven through
   `hyprctl dispatch` over the serial console. Real keypresses on the
   laptop are yours to try; I can't press keys on it.
9. **The KDE-free goal leaks through Calamares.** It keeps kpmcore and
   some KF6 libraries, as agreed.
10. **The cast art (M6).** I can write clean, simple vector SVG characters
    procedurally, but "polished anime-style mascots" at wallpaper quality is
    at the edge of what generated SVG reaches. Expect simple, flat designs.
    If you want illustration quality, an artist would have to draw the
    finals.
11. **Scope.** Nine milestones, each with a full ISO, QEMU and laptop cycle.
    A full ISO build takes about 40 minutes.

## 9. Open questions (your decisions)

1. **Lua instead of `.conf`**: approve the "Session layout" above (forced by
   Hyprland 0.57), with categories in descriptions as `[Category] text`?
2. **Release numbering**: approve section 7?
3. **Fresh install only** for 3.0, with no in-place move from a KDE install?
4. **Plasma as a fallback session during M1**: keep Plasma installed beside
   Hyprland until M2 removes it, so the laptop always has a session that
   works?
5. **Control Center**: move it into Quickshell as well and retire the
   Flutter `forge-control` panel? (Recommended.)
6. **Forge Terminal**: M5 rewrites it in GTK4 + VTE, replacing today's
   Flutter terminal. Confirm?
7. **Delete the untracked leftovers** `apps/forge-shell/` and `compositor/`
   (build output only; the source is on `archive/forge-desktop`)?
8. **Stopgap apps**: the GNOME/GTK ones listed in section 5, until Forge
   versions exist?
9. **Game watcher**: a separate `forge-gamewatch` script as the brief says,
   or folded into forged?
10. **M1 notifications**: none until forge-shell, or `mako` for M1 only?

## 10. Not verified in Milestone 0

This milestone is documents only: no ISO was built and nothing was
installed. Several statements are based on reading code or documentation,
not on running anything:

- Hyprland 0.57's Lua API, checked against the 0.56 stubs on this machine
  (`/usr/share/hypr/stubs/hl.meta.lua`) and Hyprland's announcements, not
  run. Includes `package.path`/`dofile`, `long_press`, and the
  `description` field in `hyprctl binds -j`.
- Whether Quickshell 0.3 has a polkit, Bluetooth or networking module that
  would replace hyprpolkitagent or blueman.
- Logind `SetBrightness` on the laptop's backlight device.
- The tiling model and the edge-sheen approximation.
- Everything NVIDIA.

## 11. Decisions and progress

**2026-11-14: "go ahead and finish everything."** Taken as approval of this
document's recommendations for every open question in section 9: Lua and
`[Category]` descriptions, the 3.x numbering, fresh installs only, Plasma
kept as a fallback through M1, the Control Center in Quickshell, Forge
Terminal rewritten in GTK4 + VTE, the stopgap apps, `mako`-free M1. The
untracked `apps/forge-shell/` and `compositor/` build leftovers were moved,
not deleted, to `~/Projects/forge-os-leftovers/` on the dev machine.

### M1: the session (apps/forge-session)

Built and tested against Hyprland 0.57.2. What changed from the design
above while building it:

- **The theme is read, not generated.** `theme.lua` reads
  `~/.config/forge/theme.json` itself (`lib/json.lua`, a small JSON reader
  and writer), so there's no generated `theme.lua` to go stale. forge-theme-sync
  only needs to run `hyprctl reload`.
- **The game watcher is Lua plus a small script.** `game.lua` listens to
  Hyprland's own events (`window.fullscreen` and the rest), turns blur,
  shadows and animations off itself, and runs `forge-game fullscreen-on|off`
  for the wallpaper and the cooling profile. No socket-reading daemon.
  GameMode's hooks call `forge-game gamemode-start|end`.
- **Per-workspace tiling is window rules.** Floating a window from the
  `window.open_early` event had no effect in 0.57, so a rule floats every new
  window while tiling is off, and a rule per workspace that differs from
  the default overrides it. Toggling also floats or tiles the windows
  already there. State: `~/.local/state/forge/tiling.json`; forged writes
  it and runs `hyprctl eval 'forge.tiling.reload()'`.
- **uwsm's environment hook** is `/etc/xdg/uwsm/env-hyprland.d/50-forge.sh`,
  which `eval`s `forge-gpu-env`. The session is Hyprland's own
  `hyprland-uwsm.desktop`.
- **Hyprland isn't held back.** Pinning it in `IgnorePkg` without our own
  repo would leave it linked against libraries that `-Syu` moves on.
  Section 8's risk 1 stays open until the Forge repo exists.
- **Hyprland's own wallpapers are off** (`misc.force_default_wallpaper = 0`,
  `disable_hyprland_logo`). They feature Hyprland's anime mascot, and
  Forge's anime art is only its own cast.

Tests: `lua tests/check-binds.lua hypr` (no hl.bind outside forge.bind,
every bind categorised, no key bound twice, JSON round trip),
`Hyprland --verify-config` in `build/check.sh lua`, and `tests/smoke.sh`.
The smoke test runs the real config in Hyprland 0.57.2 nested on the dev
machine's desktop (Hyprland's headless backend needs a seat or a parent
compositor; Weston's and sway's protocols are too old for Aquamarine). It
checks the binds over `hyprctl`, that new windows float, Super+Left
snapping, tiling on and off per workspace, resize mode and workspaces.
All 13 pass.

Not verified yet: the ISO build, a QEMU install, the live session opening
Calamares, and anything on the NVIDIA laptop's own session (NVIDIA env,
explicit sync, VRR, suspend, hyprlock after resume, the touchpad gesture,
the hardware keys).

### M2: forge-shell (apps/forge-shell) and Plasma out

Built and tested against Quickshell 0.3.2 and Hyprland 0.57.2.

- **The shell**: the bar (Forge button, workspaces, window title, the
  island with clock and now playing, mode badge, do-not-disturb badge, tray,
  battery with the percentage inside, Wi-Fi, Bluetooth, sound, Control
  Center button), the Wi-Fi, Bluetooth, sound and battery popups, the
  Control Center, notifications (server, pop-ups, centre), OSDs, the desktop
  shortcut panel, the Super+/ cheat sheet, the hold-Super popup, overview
  with live previews, Alt+Tab with live previews, clipboard and emoji
  pickers, and the power menu.
- **Binds reach the shell as Hyprland global shortcuts**
  (`hl.dsp.global("forge:<name>")` to Quickshell's `GlobalShortcut`), not a
  process per key press. That gives key-release events for the hold-Super
  popup and for Alt+Tab (an `ALT + Alt_L` release bind commits).
- **forged** changed here rather than in M3, because the shell needs it:
  brightness through sysfs and logind (polled once a second, since sysfs
  can't be watched), dark from theme.json only, tiling from the shared
  `tiling.json` for the focused workspace (Hyprland's event socket says
  when that changes), do not disturb held by forged itself
  (`~/.local/state/forge/dnd.json`), `toggle` and `+N`/`-N` values, `forged
  watch`, and no crash without a system bus. The D-Bus API is unchanged.
  `tests/test_forged.py` has 8 tests.
- **Plasma is out of the ISO**: plasma-meta, the KDE apps, the KWin effects,
  Darkly, Polonium, the KDE portal, plasma-nm, KWallet, the skel KDE files,
  the look-and-feel and Plasma theme, the colour schemes, `forge-glass-check`,
  and the KWin glass build in `build/Containerfile`. The Flutter Forge
  Control panel and its Plasma widgets were retired (the Control Center is
  in the shell now). Konsole stays until M5. The stopgap apps are in.

Tests: `apps/forge-shell/tests/run.sh` runs the real shell with forged in
Forge's Hyprland session (nested) and checks 11 things: it starts without
QML errors, forged answers, Hyprland frosts its layers, notifications pop
up, do not disturb holds them back, the cheat sheet opens, the clipboard
history fills, a global shortcut opens the Control Center, Alt+Tab
switches windows, and no QML errors after using everything. It also takes
a screenshot of each panel and overlay. All pass.
`build/check.sh qml` (qmllint) passes. Its warnings are mostly qmllint
not knowing Quickshell's generated `qs.*` modules.

Not verified: the shell on the laptop (real Wi-Fi, Bluetooth, PipeWire,
UPower, backlight, tray apps), hold-Super's long press with a real
keyboard, and the ISO.

keyboard, and the ISO.

### M3: the Forge apps without KDE (forged was done in M2)

- **forge-theme-sync** now takes `theme.json` everywhere itself: Hyprland
  (`hyprctl reload`), GTK 3 and 4 (an imported `forge.css` with
  libadwaita's named colours, so a user's own `gtk.css` survives;
  `settings.ini`; GNOME's interface settings, which the GTK portal hands to
  browsers and Electron), Qt 5 and 6 (a 22-role Forge Glass palette through
  qt5ct/qt6ct, Fusion style), the shell prompt, Flatpak and the login
  screen. Files are only rewritten when they change. Kvantum was dropped in
  favour of the qt6ct palette: no SVG theme to maintain.
  `tests/test_theme_sync.py` has 4 tests.
- **forge CLI**: `forge tile` drives forged (per workspace; `all on|off`
  sets the default), `forge glass calm|liquid|bold` writes theme.json
  presets, and `forge theme` works without Plasma.
- **forge_ui**: the theme comes from theme.json only. Every Flutter app
  window gets a transparent GTK header bar (`apps/forge_ui/linux/forge_titlebar.h`):
  title, maximise, close, drag. That covers Store, Files, Theming Kit,
  Thermal, Calendar and Forge Shot's editor.
- **Theming Kit**: applies through theme.json and forge-theme-sync. The
  lens sliders are now "Edge width" and "Edge light"; bevel, inner bending
  and colour split are gone from the UI (themes keep their values).
- **Launcher**: a layer-shell surface (`forge-launcher` namespace, overlay
  layer, exclusive keyboard while it's up), commands in the user's terminal
  (xdg-terminal-exec), power through logind and `forge-logout`, and file
  names under home when Forge Mind isn't there (Baloo is gone). New action:
  record the screen.
- **Forge Shot**: grim captures (the focused screen, every screen, the
  active window, or a window picked with a click through `slurp -r` over
  Hyprland's window rectangles); GTK's save dialog for "Save as"; "Show in
  folder" through `org.freedesktop.FileManager1`, else the folder. Recording
  is `forge-record` (gpu-screen-recorder, NVENC/VA-API).
- **Files**: "open terminal here" uses Forge Terminal or xdg-terminal-exec.
- **Browser**: themed by the qt6ct palette.

Not done in M3: Forge Files doesn't serve `org.freedesktop.FileManager1`
yet, so "Show in folder" opens the folder. The Flutter Forge Terminal isn't
ported, since M5 replaces it. The Launcher can't close on a click outside
it (a layer surface with exclusive keyboard sees no focus-out), only on
Escape.

Tests for M3: `tests/test_theme_sync.py` (4) and `tests/test_forged.py` (8)
pass in `build/check.sh`. In the nested Hyprland session, Forge Shot's grim
captures (screen, every screen, active window) worked, and Forge Thermal
opened floating with its new glass title bar. While checking that, an
oversized window (980×800 on a 720-pixel-high screen) had its title bar
off the top. forge-session now shrinks any new floating window that's
bigger than its screen and centres it. All six changed Flutter apps pass
`flutter analyze` and build.

### M7: Forge Settings + keybind editor (apps/forge-settings)

Flutter on `forge_ui`. A settings app for newcomers, since Hyprland has none.

- **Pages:** displays (resolution, scale, refresh, VRR; writes
  `~/.config/hypr/monitors.lua`), keyboard layout and repeat, mouse/touchpad,
  default apps, startup apps, sound (wpctl), network/VPN
  (`nm-connection-editor` fallback), Bluetooth pairing (bluetoothctl), users,
  about.
- **Shortcuts page:** rebind any bind from `hyprctl binds -j`, with conflict
  detection (a key already bound elsewhere is rejected inline), writing
  `~/.config/hypr/keybinds.user.lua`, which `~/.config/hypr/hyprland.lua`
  loads after `keybinds.lua` so the user's overrides win. `forge keys`
  (CLI equivalent) lists binds and rebinds one: `forge keys set <category>
  <description> <new-key>`.
- **Config error notifier:** a bad monitor line or a bad bind lands Hyprland
  in its raw red bar. Forge Settings keeps the files it writes syntactically
  simple, and any failure shows a readable notification with file and line —
  never the raw red bar.

Tests: `flutter analyze` passes on `apps/forge-settings`. The
`forge-session` bind lint (`tests/check-binds.lua`) still runs on
`keybinds.lua` itself; `keybinds.user.lua` is user-owned and not linted by
the build.

Not verified: the app on a real session (Hyprland not running here, so
`hyprctl binds -j` and `hyprctl reload` can't be exercised), the ISO build,
the QEMU install, and anything on the NVIDIA laptop.
