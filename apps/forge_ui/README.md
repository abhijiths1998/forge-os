# forge_ui

What every Forge app shares, so they look and behave alike:

- `ForgeTheme` (`src/theme.dart`): everything the Theming Kit sets: dark
  or light, accent, glass tint, the liquid glass settings, surface
  opacities and corner radius. The desktop's current theme is
  `~/.config/forge/theme.json`; saved themes are in `~/.config/forge/themes/`.
  Built-in themes start from Forge Glass, the desktop as shipped.
- `ForgePalette` (`src/palette.dart`): a theme's colours for Flutter UI,
  from Forge Glass's base palette (`branding-source/glass/colors.py`)
  tinted and accented. `ForgePalette.current()` follows the desktop.
- `kdeColourScheme` / `konsoleColourScheme` (`src/scheme.dart`): the
  theme as KDE and Konsole colour scheme files, in colors.py's format.
- Widgets (`src/widgets.dart`): `GlassCard`, `PillButton`, `ForgeSlider`,
  `Segmented`, `SectionLabel`.

Not an app: Forge apps depend on it with `path: ../forge_ui`, and
`apps/build-packages.sh` builds them with it alongside.
