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
- **Top-bar button:** a Plasma widget (`data/plasmoid`, `org.forgeos.control`)
  just left of the tray. The look-and-feel layout puts it there for new users.
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
