# The Forge desktop

Forge's own desktop environment, replacing KDE Plasma. It has the Forge
Glass look throughout: pastel liquid glass with no outlines, Plus Jakarta
Sans, a slim floating top bar, a compact centred dock, the Super+Space
command bar and rounded corners. Colours, accent, blur and corners come
from the theme (`~/.config/forge/theme.json`, the Theming Kit).

Until it can do everything Plasma does for Forge, it is a second session
at the login screen ("Forge", beside "Plasma"), and Plasma stays installed.

## Forge Terminal, Files and Calendar; the wallet (2026-10-31, late night)

**KWallet asked for its password in the Forge session.** pam_kwallet5
opens the wallet with the login password at login and leaves
`ksecretd --pam-login` waiting for the session's environment, which
`/usr/lib/pam_kwallet_init` hands over. Plasma runs that as
plasma-kwallet-pam.service; the Forge session never did, so the first app
wanting a secret started a second, locked ksecretd that asked again (seen
live: two ksecretd processes). `forge-session-start` now runs
pam_kwallet_init first thing. The same look found that
`systemctl --user start xdg-desktop-autostart.target` had always failed
("may be requested by dependency only"), so no autostart entry (KDE
Connect, Forge Control, Launcher) ever ran in a Forge session: the new
`forge-session.target` (usr/lib/systemd/user) pulls in
graphical-session.target and the autostart target, and forge-session-start
starts that. Tested live by starting the target. Needs
`pkexec utils/dev-install-session.sh`, and only works if the wallet's
password is the login password (kwallet-pam's rule).

**Forge Terminal** (apps/forge-terminal): Flutter on forge_ui, xterm.dart
for the emulation, our own pseudo-terminals (linux/runner/pty.cc, forkpty
in C, called through dart:ffi). Colours are the Theming Kit's terminal
scheme with the accent for cursor and selection, the theme's terminal
opacity, the desktop's fixed font; restyles live on theme changes. Tabs,
find, links, zoom, settings sheet. Tested in a headless KWin
(colours, 256 colours, wide glyphs, Nerd Font icons, full-screen apps).

**Forge Files** (apps/forge-files): places, GTK bookmarks, drives
(udisks mount/eject), trash with restore, icon and list views, thumbnails
(pictures, ffmpeg for videos, pdftoppm for PDFs), search, drag and drop,
copy/cut/paste, Open with, Properties. Tested in a headless KWin.

**Forge Calendar** (apps/forge-calendar): month/week/day/agenda; local
calendars as .ics in ~/.local/share/forgeos/calendar, .ics subscriptions
(Google's secret address), repeats with per-occurrence exceptions,
reminders. Runs hidden at login (`--background`) so reminders come on
time. The Forge session has **no notification server yet** (the Plasma
activation file only waits for plasmashell, so Notify hangs): until D2's
own server exists, an undelivered reminder brings the calendar's window up
with a banner instead (tested).

Wired in: the dock's and start menu's default pins, the desktop menu's
Terminal/Files (falling back to Konsole/Dolphin), "Open Calendar" in the
clock's calendar, mimeapps (folders, .ics), kdeglobals' terminal and
xdg-terminals.list in skel, and the ISO's package list.

## Forge's own popups (2026-10-31, night)

The user asked for "custom UI for all interactions in the main UI (custom
dialogue boxes including custom start menu)". A fourth shell part,
`forge-shell popups` (`apps/forge-shell/lib/popups/`), draws all of it on
one screen-sized overlay layer (`forge-popups`, keyboard exclusive) that is
mapped only while something is open:

| What | Opened by |
|---|---|
| Start menu: search, categories, app grid, you, power buttons; right-click an app to pin it to Start (`~/.config/forge/start.json`) or the Dock | the bar's emblem; a tap on Super (Forge Compositor) |
| Calendar: time, date, month to page through | the bar's clock |
| Dock menu: the app's windows, New window, Keep in / Remove from Dock, Close (all) windows | right-clicking a dock icon |
| Desktop menu: Change wallpaper, Appearance, Terminal, Files, Power | right-clicking the wallpaper |
| Wallpaper picker (`/usr/share/wallpapers`, `~/Pictures(/Wallpapers)` → `~/.config/forge/wallpaper`) | the desktop menu |
| Power: Lock, Sleep, Log out, Restart, Shut down; the last three ask, with a 30 s countdown | start menu, desktop menu, `forge-dialog power` |
| Dialogs: info / warning / error / question / text / password | `forge-dialog` (replaces kdialog/zenity for Forge's scripts) |
| polkit's password prompt (replaces polkit-kde-agent in the Forge session) | any app needing an administrator |

- D-Bus `org.forgeos.Popups` `/org/forgeos/Popups`: `StartMenu()`,
  `Calendar()`, `Wallpapers()`, `Power(s)`, `Menu(s json) → s id`,
  `Dialog(s json) → s json`. Client: `lib/popups/client.dart`; scripts:
  `forge-dialog` (`profile/airootfs/usr/local/bin`).
- polkit: `linux/runner/polkit_agent.cc` is a `PolkitAgentListener`
  (libpolkit-agent-1 does PAM through polkit's helper socket); the dialog
  is Dart. If polkit refuses the registration in a Forge session, the part
  starts KDE's agent instead. `FORGE_NO_POLKIT=1` skips it;
  `FORGE_POLKIT_PROCESS=<pid>` registers for one process (tests).
- `FORGE_DRY_POWER=1` logs power commands instead of running them (a
  nested test shares the real login session, so Log out would end it).
- Compositor test input grew `{"button":"press","right":true}` and
  `{"key":<evdev code>}`.
- Tested nested (Forge Compositor, 2026-10-31): start menu (emblem, Super
  tap, typing, Enter, Esc, categories, right-click menu over it), calendar,
  dock menu (Open, window list, Close window), desktop menu, wallpaper
  picker, power card and countdown confirm (Cancel; Restart dry-run ran
  `systemctl reboot`), question dialog, polkit with pkexec (prompt, wrong
  password rejected by PAM, Esc → pkexec "Request dismissed").
- Not yet: under KWin (no Super tap there: KWin's Meta-alone shortcut is
  shared with Plasma's kwinrc); Forge's own file chooser (portals are still
  KDE's; Forge Shot's Save as still uses kdialog); notifications (D2).

## Forge Compositor by default again (2026-10-31, late)

The user wants the session on our own compositor, not KWin. `forge-session`
now runs Forge Compositor; KWin is only the safety net:
- `forge-session --kwin` or `FORGE_COMPOSITOR=kwin` by hand. The
  "Forge (safe mode)" login entry (`forge-kwin.desktop`) was removed
  2026-10-31: the first real login picked it, so the user got KWin and
  thought Forge was still on someone else's compositor;
- automatically, when forge-compositor is missing or fails within 20 s of
  starting (no screen, no GPU, an early crash).
- The compositor's watchdog thread aborts it when the event loop hasn't
  turned for 12 s (`FORGE_NO_WATCHDOG=1` turns it off), so a stuck frame
  ends at the login screen rather than a frozen picture. Logs:
  `journalctl -t forge`.
- The first `--startup` command is the session: when forge-session-start
  ends, Forge Compositor quits (KWin's `--exit-with-session`).
- Still untested on the real screen since the switch to KWin; the one
  hardware run (2026-10-31 00:10, possibly still Hyprland) froze.

## KWin underneath (2026-10-31)

Hyprland felt like a WM and Forge Compositor froze and mishandled windows
on hardware, so the Forge session now runs **KWin** (`kwin_wayland_wrapper
--xwayland`), with Forge Shell in place of plasmashell. KWin brings title
bars, snapping, Alt+Tab, XWayland, screen sharing and virtual desktops.

- `apps/forge-shell/lib/kwin.dart`: a KWin script (the bridge, loaded by
  the first shell part) pushes windows and desktops to each part
  (`org.forgeos.Shell.p<pid>`, method `Windows`) and holds Forge's
  shortcuts (Meta+Space launcher, Meta+A control, volume and media keys),
  which it runs through a part (`Run`). The shell acts through one-off
  scripts (activate, switch desktop).
- `forge-session-start` also starts powerdevil (brightness keys, lid,
  battery; forged's brightness) and KDE's portal; portals are all KDE's.
- `FORGE_COMPOSITOR=forge` still picks Forge Compositor. Hyprland is gone
  from the session and the shell (hyprland.conf and forge-hyprbars remain
  in the tree, unused).
- Tested in a headless KWin (`kwin_wayland --virtual`): bar, dock,
  wallpaper, focus title, dock dots, minimise. Not yet: blur behind the
  bar and dock (KWin needs the org_kde_kwin_blur protocol from the runner).

## Forge Compositor (2026-10-30: replacing Hyprland)

The user wants the desktop built, not assembled from someone else's
desktop: "use bits and pieces from other platforms but using entirely
their software is boring". So the compositor is our own, `compositor/`
(Rust), built on **Smithay 0.7** as a toolkit (Wayland protocols, DRM/KMS,
GBM/EGL, libinput, the GLES renderer). Window management, title bars,
effects, shortcuts and IPC are Forge's. Forge Shell runs on it unchanged
(wlr-layer-shell). The Hyprland session stays as the fallback until
Forge Compositor runs a real session and games.

| Module | What |
|---|---|
| `state.rs` | protocols, the space of windows, minimised list, per-window `WinData` (id, server-side bar, restore rect, parked spot, fullscreen) |
| `handlers.rs` | commits, xdg-shell (windows, popups, move/resize/maximise/minimise/fullscreen requests), xdg-decoration + KDE server-decoration (who draws the title bar), wlr-layer-shell, seat, clipboard |
| `wm.rs` | floating WM: centred placement in the free area, focus, minimise/activate, maximise, fullscreen, hit-testing (layers, bars, edges, content) |
| `deco.rs` | Forge title bars painted with tiny-skia + fontdue (Plus Jakarta Sans), cached per window |
| `grabs.rs` | move and resize (adapted from Smithay's smallvil) |
| `render.rs` | frame order: top layers, windows with bars, bottom layers |
| `input.rs` | shortcuts (Super+Q/Up/Down/M/Space/A/Return/E, Alt+F4, Alt+Space, Ctrl+Alt+Backspace quits), clicks on bars/buttons/edges, double-click maximise |
| `ipc.rs` | `$FORGE_COMPOSITOR_SOCKET`, JSON lines: windows, activate/minimize/maximize/close, spawn, subscribe, screenshot; `FORGE_TEST_INPUT=1` adds pointer/button for tests |
| `theme.rs` | theme.json (dark, accent, corners, glass), re-read every 2 s |
| `winit.rs` | nested backend (`--nested`); screenshots rendered offscreen (reading the window's own EGL surface back broke it on NVIDIA) |

Try it: `cd compositor && cargo build && target/debug/forge-compositor --nested --startup "forge-shell wallpaper" --startup "forge-shell bar" --startup "forge-shell dock"`

**Done 2026-10-30:** dock and bar on Forge IPC (`apps/forge-shell/lib/wm.dart`:
one interface, Forge and Hyprland behind it); glass (`glass.rs`: wallpaper
blurred with dual Kawase into a texture, panes behind windows/bar/dock,
rounded content corners; the blur is updated *before* the output's
framebuffer is bound, binding other targets mid-frame lost the EGL surface
on NVIDIA); the real-screen backend (`udev.rs`: libseat, one GPU, DRM
output manager, libinput with tap/natural scroll, Breeze cursor, VT
switching, dmabuf) **not yet run on hardware**; XWayland (`xwayland.rs`,
`win.rs` hides Wayland/X11 differences; tested with Konsole as an X11 app:
title bar, focus on surface association, maximise); wlr-screencopy
(`capture.rs`, tested with grim, full and region; nested output is
Flipped180 so copies are sent flipped). Session: `forge-session` runs
Forge Compositor (Hyprland only if it's missing) with
`forge-session-start`; keys for screenshots, sound, brightness, media,
Super+L lock.

**Glass fix (2026-11-01):** big windows had a hard-edged black wedge in
their glass (bottom right) on NVIDIA. The glass shaders ran at `mediump`,
which NVIDIA's GLES gives as 16-bit floats; the grain hash
`fract(sin(dot(p, (12.9898, 78.233))) * 43758)` passes 65504 a few
hundred pixels into a pane, turns NaN and paints black. Now the shaders use
`highp` where the GPU has it and the grain hash stays in small numbers.
Also: the wallpaper is only blurred again when it changed (the background
tracker drew at age 0, so it re-blurred every frame), and each pane has its
own element id (one shared id confused the damage tracker when windows
moved). IPC `{"glass_dump":"/dir"}` saves the blur textures for debugging.

**App integration audit (2026-10-30):** Qt/KDE apps (most) take the Forge
Glass colours through Darkly + plasma-integration and get Forge title bars.
Out of place: GTK apps with header bars (Lutris, Heroic) → a Forge GTK
3/4 theme; Discover / Add-Remove Software (Forge Store), Spectacle (Forge
Shot) → hidden in the Forge session; KDE System Settings, Welcome Center,
Info Center → **Forge Settings** (to build); Steam, Discord and Brave draw
their own UI and can't be restyled (Forge Browser is the default browser).

**C1 (nested, done 2026-10-30, tested with FORGE_TEST_INPUT):** Forge Shell's
layers, Konsole and Dolphin with Forge title bars, drag by the bar, hover
shows −/+/×, maximise to the free area and back, minimise and IPC activate,
close, next window focused.
**Next:** Forge Shell talks to Forge IPC (dock dots, activate, bar title);
blur behind translucent windows (C3; without it windows show each other
through); a real session on DRM/KMS + libinput + cursor (C2); XWayland;
screencopy for Forge Shot.

## The parts (Hyprland session)

| Part | What it is | Where |
|---|---|---|
| Compositor | **Hyprland**, configured only by Forge: draws windows, blur, rounded corners, animations, tiling, workspaces, gestures | `/usr/share/forge/hyprland.conf`; the theme's part `~/.config/forge/hypr/theme.conf` (`forge-theme-sync`); the user's `~/.config/forge/hypr/user.conf` |
| Session | `forge-session`: environment (Qt theme, portals, NVIDIA), then Hyprland, which starts the rest; `forge-keep` restarts a part that crashes | `profile/airootfs/usr/local/bin`, `usr/share/wayland-sessions/forge.desktop` |
| Shell | **Forge Shell** (Flutter on forge_ui, gtk-layer-shell): one process per part, `forge-shell bar\|dock\|wallpaper` | `apps/forge-shell` |
| System state | `forged` (D-Bus `org.forgeos.Forged`): Wi-Fi, Bluetooth, sound, brightness, power, battery, thermal, dark mode | already built for Plasma |
| Control Center | Forge Control (already layer-shell) | `apps/forge-control` |
| Command bar | Forge Launcher | `apps/forge-launcher` |
| Portals | KDE's (file pickers, settings), Hyprland's (screen sharing, screenshots, global shortcuts) | `usr/share/xdg-desktop-portal/forge-portals.conf` |

Hyprland talks to the shell over its sockets (`apps/forge-shell/lib/hyprland.dart`):
`.socket.sock` for requests (`j/clients`, `dispatch workspace 2`) and
`.socket2.sock` for events (`openwindow>>…`, `workspace>>2`).

## Milestones

**D1: a usable session** (started 2026-10-30)
- [x] Session entry, `forge-session`, Forge's `hyprland.conf` (keys, glass rules, animations, gestures, media keys)
- [x] Theme sync writes Hyprland's corners and blur from theme.json
- [x] Top bar: Forge emblem (opens Launcher), workspaces, focused app, clock, Wi-Fi / Bluetooth / sound / battery (opens Forge Control)
- [x] Dock: pins (`~/.config/forge/dock.json`) and running apps, focus or launch, cycle windows, running dots
- [x] Wallpaper: Forge Glass light/dark, or `~/.config/forge/wallpaper`
- [x] Tried in a nested Hyprland (2026-10-30, Hyprland 0.56.2): config passes `--verify-config` (which does reject unknown rule names); bar, dock and wallpaper map as layers, frosted; `forge-keep` restarts killed parts; dock dots and `focuswindow address:` work
- [x] Forge Launcher (floating, centred, `stay_focused`) and Forge Control (layer under the bar) work under Hyprland. Control needed a fix: Hyprland sends a focus-out to a layer it never focused, which hid the panel as it opened; it now hides only after a real focus-in
- [x] No tiling (the user's choice, 2026-10-30): every window floats, moved by its title bar or Super+drag, resized from its edges
- [x] Title bars with minimise, maximise and close: hyprbars (packages/forge-hyprbars, pinned to Hyprland 0.56.2), glass in the theme's colours, double-click to maximise. Loaded only when installed (forge-session sets FORGE_BARS; `# hyprlang if` in the conf; `--verify-config` doesn't load plugins, so it flags `hyprbars:no_bar` with FORGE_BARS set; the running session takes it). Seen in the nested session 2026-10-30. New windows open centred: placed by Hyprland, a window's bar ended up under the top bar
- [x] The bar starts the Launcher and Control Center through the runner (`g_spawn_command_line_async`): Dart's detached `Process.start` left a zombie per click
- [x] Minimise = the hidden workspace `special:minimized` (Hyprland has no minimise); the dock keeps the app's dot and brings the window back to the current workspace. Maximise = `fullscreen 1` (keeps the bar and dock). Super+Up / Super+Down / Super+M
- [x] Breeze cursor (XCURSOR_THEME). Don't force `cursor:no_hardware_cursors = false`: on NVIDIA it crashed Hyprland in renderHWCursorBuffer; the default (auto) is right
- [x] `forge-keep` ends with its own Hyprland (hyprctl to its instance), so a crashed-and-restarted Hyprland doesn't get two of each part
- [ ] As a real session from the login screen on the dev machine

**D2: everyday basics**
- Notifications (our own `org.freedesktop.Notifications` server, glass toasts, history in Forge Control)
- Lock screen (ext-session-lock) and idle: dim, lock, screen off, suspend
- Volume / brightness pop-ups (OSD)
- Tray (StatusNotifierItem) in the bar, for Steam, Discord and the like
- forged without KDE: brightness (logind/brightnessctl), dark mode (theme.json, not kdeglobals), tiling (Hyprland's layout, not kwinrc)
- Forge Shot capturing through the screencopy protocol, not KWin
- One bar and dock per screen, following screens plugged in and out
- Dock: right-click menu (pin, new window, quit), drag to reorder, app names on hover

**D3: Forge Settings**, replacing System Settings: displays, network,
Bluetooth, sound, appearance (the Theming Kit inside it), wallpaper,
keyboard and shortcuts, mouse and touchpad, power, users, default apps,
about.

**D4: the everyday apps** (the 3.0 plan in RELEASES.md): Forge Files,
Terminal, text editor, image viewer. Then Plasma comes off the ISO.
- [x] Forge Terminal, Forge Files, Forge Calendar (2026-10-31)
- [ ] Text editor, image viewer
- [ ] Forge Files: tabs, a FileManager1 D-Bus service (browsers' "Show in folder"), drag to other apps

## Not decided yet
- Whether windows get Forge title bars (Hyprland has none; GTK and Flutter
  apps draw their own, Qt apps have none).
- Whether to fork Hyprland later (for Forge's own liquid-glass shader), or
  do it as a Hyprland plugin.
