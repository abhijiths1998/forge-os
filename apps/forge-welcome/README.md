# Forge Welcome: first-boot onboarding + Keyboard Dojo

The welcome screen for Forge OS on Hyprland. Shows first-boot choices
(Flathub opt-in, NVIDIA re-check, codecs, optional extra apps) plus the
Keyboard Dojo tutorial that teaches the 10 most important shortcuts through
guided, interactive exercises.

Flutter on forge_ui. The .desktop, PKGBUILD and README live next to this.

```sh
flutter analyze && flutter test
flutter build linux --release --no-tree-shake-icons
```

Not verified on hardware: the first-boot flow itself (Hyprland not running
here so `hyprctl` can't be exercised), the ISO build, the QEMU install.
