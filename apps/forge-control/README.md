# Forge Control

The Control Center: a glass panel under the top bar with the switches people
reach for most. Wi-Fi and Bluetooth (with what they're connected to), Quiet
(do not disturb), dark mode and tiling, display brightness and volume, the
power profile and Forge Thermal's cooling profile, and what's playing.
Flutter UI on `forge_ui`; the window is translucent and KWin's Glass effect
frosts it.

- **State and switches** come from `forged` (D-Bus `org.forgeos.Forged`,
  `/usr/local/bin/forged` in the ISO profile), which listens to each part's
  own service, so the panel stays right whoever changes something: a volume
  key, KDE's applets, `forge theme`.
- **Top-bar widgets** (`data/plasmoids`, Plasma widgets the look-and-feel
  layout puts in the top bar for new users, in place of the tray's own;
  they share the QML module `org.forgeos.panel` in `data/qml`, installed to
  `/usr/lib/qt6/qml`, which talks to forged over D-Bus):
  - `org.forgeos.wifi`, `org.forgeos.bluetooth`, `org.forgeos.volume`:
    Wi-Fi, Bluetooth and Sound, each with a popup like the battery's. Wi-Fi:
    the switch, nearby networks (saved and strongest first), joining one
    with its password asked in place, leaving the one in use. Bluetooth:
    the switch and paired devices with their battery, connected with a
    click. Sound: the volume and mute, and the output (speakers,
    headphones, HDMI, Bluetooth); scrolling on its icon changes the volume,
    a middle click mutes. The tray stays, slim, for apps' icons; Plasma's
    items are hidden in its overflow, not switched off (volume keys and
    notification pop-ups live in them);
  - `org.forgeos.control`, the Control Center's button, just left of the tray;
  - `org.forgeos.battery`, **Forge Battery**, at the right end: a
    macOS-style battery with the percentage written inside it, in a
    contrasting colour where the fill reaches. Green while plugged in, red
    at 20% and below, a bolt while charging. A click opens its popup: the
    charge, the time left, health and model, and where the top bar shows
    the percentage (inside the battery, beside it or hidden), each choice
    previewed with the real charge. It takes no space without a battery,
    and Plasma's own battery icon moves to the tray's overflow.
- **Placement:** with gtk-layer-shell, the panel anchors under the top bar on
  the right. Without it, a KWin rule (`/etc/skel/.config/kwinrulesrc`) takes
  the border off and places it under the mouse, which is the button.
- It starts hidden at login (`forge-control --background`) and stays
  running, so the button only shows the window. Running `forge-control`
  again toggles it; clicking elsewhere or Escape closes it.

```sh
forge-control                 # toggle the panel
forged state                  # what it shows, as JSON
forged set dnd on             # what its switches do
```

Build: `flutter build linux --release` (gtk-layer-shell is optional at build
time; the bundle is in `build/linux/x64/release/bundle/`).
