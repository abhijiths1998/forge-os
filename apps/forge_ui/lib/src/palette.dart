// Colours from a ForgeTheme: the Forge Glass base palette (light or dark,
// as in branding-source/glass/colors.py) tinted and accented by the theme.
// The same values feed the KDE colour scheme (scheme.dart) and the Forge
// apps' own UI (ForgePalette), so they always match.
import 'dart:io';

import 'package:flutter/material.dart';

import 'theme.dart';

const fontFamily = 'Plus Jakarta Sans';

/// Forge Glass's colours before tinting (colors.py LIGHT / DARK).
class BasePalette {
  const BasePalette({
    required this.window,
    required this.windowFg,
    required this.inactiveFg,
    required this.view,
    required this.button,
    required this.header,
    required this.tooltip,
    required this.complementary,
    required this.complementaryFg,
    required this.negative,
    required this.neutral,
    required this.positive,
    required this.wmActive,
    required this.wmInactive,
    required this.accent,
    required this.focus,
    required this.hover,
    required this.link,
    required this.visited,
  });

  final (Color, Color) window;
  final Color windowFg;
  final Color inactiveFg;
  final (Color, Color) view;
  final (Color, Color) button;
  final (Color, Color) header;
  final Color tooltip;
  final (Color, Color) complementary;
  final Color complementaryFg;
  final Color negative;
  final Color neutral;
  final Color positive;
  final (Color, Color) wmActive; // background, foreground
  final (Color, Color) wmInactive;

  // Forge Glass's accent and the roles derived from it; a theme's own
  // accent gets the same offsets (ThemeColours.role).
  final Color accent;
  final Color focus;
  final Color hover;
  final Color link;
  final Color visited;

  static const dark = BasePalette(
    window: (Color(0xFF1A1C33), Color(0xFF20233D)),
    windowFg: Color(0xFFE4E6F4),
    inactiveFg: Color(0xFF9296B5),
    view: (Color(0xFF161830), Color(0xFF1E2139)),
    button: (Color(0xFF262A47), Color(0xFF2E3254)),
    header: (Color(0xFF1F2240), Color(0xFF1A1C33)),
    tooltip: Color(0xFF20233D),
    complementary: (Color(0xFF12142A), Color(0xFF1A1C33)),
    complementaryFg: Color(0xFFE4E6F4),
    negative: Color(0xFFF28B9B),
    neutral: Color(0xFFF6CFA8),
    positive: Color(0xFF8FD3A8),
    wmActive: (Color(0xFF1F2240), Color(0xFFE4E6F4)),
    wmInactive: (Color(0xFF1A1C33), Color(0xFF7C80A0)),
    accent: Color(0xFF7F8EF5),
    focus: Color(0xFF8A9BF7),
    hover: Color(0xFFA3B0FA),
    link: Color(0xFF9AAAFF),
    visited: Color(0xFFC3B7EE),
  );

  static const light = BasePalette(
    window: (Color(0xFFF3F2FA), Color(0xFFEAE8F6)),
    windowFg: Color(0xFF1E2140),
    inactiveFg: Color(0xFF6E7391),
    view: (Color(0xFFFBFBFE), Color(0xFFF3F2FA)),
    button: (Color(0xFFF7F6FC), Color(0xFFEAE8F6)),
    header: (Color(0xFFEDEBF8), Color(0xFFE4E1F4)),
    tooltip: Color(0xFFFBFBFE),
    complementary: (Color(0xFF232640), Color(0xFF2B2F4E)),
    complementaryFg: Color(0xFFE4E6F4),
    negative: Color(0xFFD9576E),
    neutral: Color(0xFFD98A3E),
    positive: Color(0xFF3E9E6C),
    wmActive: (Color(0xFFEDEBF8), Color(0xFF1E2140)),
    wmInactive: (Color(0xFFF3F2FA), Color(0xFF8A8EAA)),
    accent: Color(0xFF6C7CF0),
    focus: Color(0xFF6C7CF0),
    hover: Color(0xFF8A9BF7),
    link: Color(0xFF5A6BE0),
    visited: Color(0xFF9A6BD8),
  );
}

/// A theme's colours, resolved.
class ThemeColours {
  ThemeColours(this.theme) : base = theme.dark ? BasePalette.dark : BasePalette.light;

  final ForgeTheme theme;
  final BasePalette base;

  /// Rotate a Forge Glass colour's hue to the theme's tint and scale its
  /// colourfulness by the tint strength.
  Color tint(Color c) {
    if (theme.tintHue == ForgeTheme.referenceHue && theme.tintStrength == 1) return c;
    final hsl = HSLColor.fromColor(c);
    final hue = (hsl.hue + theme.tintHue - ForgeTheme.referenceHue) % 360;
    return hsl
        .withHue(hue < 0 ? hue + 360 : hue)
        .withSaturation((hsl.saturation * theme.tintStrength).clamp(0.0, 1.0))
        .toColor();
  }

  (Color, Color) tint2((Color, Color) p) => (tint(p.$1), tint(p.$2));

  Color get accent => theme.accent;

  /// A role colour (focus, hover...) for the theme's accent: Forge Glass's
  /// role, moved the way the accent moved from Forge Glass's accent (hue
  /// turned, saturation scaled, lightness shifted). Forge Glass's own accent
  /// gives its roles back exactly.
  Color role(Color baseRole) {
    final a = HSLColor.fromColor(accent);
    final b = HSLColor.fromColor(base.accent);
    final r = HSLColor.fromColor(baseRole);
    if (a.toColor() == b.toColor()) return baseRole;
    final sat = b.saturation == 0 ? r.saturation : r.saturation * a.saturation / b.saturation;
    return HSLColor.fromAHSL(
      1,
      (a.hue + r.hue - b.hue) % 360,
      sat.clamp(0.0, 1.0),
      (a.lightness + r.lightness - b.lightness).clamp(0.0, 1.0),
    ).toColor();
  }

  Color get focus => role(base.focus);
  Color get hover => role(base.hover);
  Color get link => role(base.link);
  Color get visited => role(base.visited);

  // Background alpha, from the window opacity: Forge Glass's 41% gives
  // colors.py's window 105, header 95, titlebar 100, view 145, tooltip 170.
  int get windowAlpha => (theme.windowOpacity * 2.55).round().clamp(20, 255);
  int get headerAlpha => (windowAlpha - 10).clamp(20, 255);
  int get titlebarAlpha => (windowAlpha - 5).clamp(20, 255);
  int get viewAlpha => (windowAlpha + 40).clamp(20, 255);
  int get tooltipAlpha => (windowAlpha + 65).clamp(20, 255);
}

/// Colours for the Forge apps' own (Flutter) UI.
class ForgePalette {
  ForgePalette._(this.colours);

  factory ForgePalette.of(ForgeTheme theme) => ForgePalette._(ThemeColours(theme));

  /// The desktop's current theme: the Theming Kit's if it was used, else
  /// stock Forge Glass, light or dark as Plasma's colour scheme is.
  static ForgePalette current() => ForgePalette.of(
      ForgeTheme.current() ?? (_plasmaIsDark() ? forgeGlass : builtInThemes[1]));

  final ThemeColours colours;

  ForgeTheme get theme => colours.theme;
  bool get dark => theme.dark;
  int get _alpha => colours.windowAlpha;

  Color _a(Color c, int alpha) => c.withAlpha(alpha.clamp(0, 255));

  /// App window background: translucent, so KWin's Glass effect frosts it.
  Color get window => _a(colours.tint(colours.base.window.$1), _alpha + 40);

  /// A floating card (the launcher): a little more solid than a window.
  Color get surface => _a(colours.tint(colours.base.window.$1), _alpha + 53);
  Color get sidebar => dark
      ? _a(colours.tint(colours.base.complementary.$1), 0x40)
      : _a(colours.tint(colours.base.window.$2), 0x4D);
  Color get card => dark
      ? _a(colours.base.windowFg, 0x14)
      : _a(colours.tint(colours.base.view.$1), 0x8C);
  Color get text => colours.base.windowFg;
  Color get dimText => colours.tint(colours.base.inactiveFg);
  Color get accent => colours.accent;
  Color get onAccent => Colors.white;

  /// Hairlines inside a surface (dividers), never around it.
  Color get rim => dark ? const Color(0x22FFFFFF) : const Color(0x70FFFFFF);
  Color get hover => _a(text, 0x14);
  Color get positive => colours.base.positive;
  Color get negative => colours.base.negative;
  int get cornerRadius => theme.cornerRadius;

  ThemeData materialTheme() {
    final brightness = dark ? Brightness.dark : Brightness.light;
    return ThemeData(
      fontFamily: fontFamily,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: brightness,
        primary: accent,
        onPrimary: onAccent,
        surface: Colors.transparent,
      ),
      scaffoldBackgroundColor: Colors.transparent,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: 0.35),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(dimText.withValues(alpha: 0.4)),
        radius: const Radius.circular(8),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: _a(text, 0x26),
        thumbColor: Colors.white,
        overlayColor: accent.withValues(alpha: 0.16),
        trackHeight: 4,
      ),
    );
  }
}

/// Plasma's colour scheme is dark: the user's kdeglobals if they picked
/// one, else the look-and-feel default.
bool _plasmaIsDark() {
  final home = Platform.environment['HOME'] ?? '';
  final config = Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config';
  for (final path in ['$config/kdeglobals', '$config/kdedefaults/kdeglobals']) {
    final scheme = iniValue(path, 'General', 'ColorScheme');
    if (scheme != null) return scheme.toLowerCase().contains('dark');
  }
  return true;
}

String? iniValue(String path, String group, String key) {
  final file = File(path);
  if (!file.existsSync()) return null;
  var inGroup = false;
  for (final line in file.readAsLinesSync()) {
    final t = line.trim();
    if (t.startsWith('[')) {
      inGroup = t == '[$group]';
    } else if (inGroup && t.startsWith('$key=')) {
      return t.substring(key.length + 1);
    }
  }
  return null;
}
