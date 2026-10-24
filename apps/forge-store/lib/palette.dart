// Forge Glass colours, from branding-source/glass/colors.py (keep in step),
// and which variant the desktop is using right now.
import 'dart:io';

import 'package:flutter/material.dart';

const fontFamily = 'Plus Jakarta Sans';

class Palette {
  const Palette({
    required this.dark,
    required this.window,
    required this.sidebar,
    required this.card,
    required this.text,
    required this.dimText,
    required this.accent,
    required this.onAccent,
    required this.rim,
    required this.hover,
    required this.positive,
    required this.negative,
  });

  final bool dark;

  /// Window and sidebar backgrounds: translucent, so KWin's Glass effect
  /// frosts what's behind them, like Darkly does for Qt apps.
  final Color window;
  final Color sidebar;
  final Color card;
  final Color text;
  final Color dimText;
  final Color accent;
  final Color onAccent;
  final Color rim;
  final Color hover;
  final Color positive;
  final Color negative;

  static const light = Palette(
    dark: false,
    window: Color(0x91F3F2FA),
    sidebar: Color(0x4DEAE8F6),
    card: Color(0x8CFBFBFE),
    text: Color(0xFF1E2140),
    dimText: Color(0xFF6E7391),
    accent: Color(0xFF6C7CF0),
    onAccent: Color(0xFFFFFFFF),
    rim: Color(0x80FFFFFF),
    hover: Color(0x141E2140),
    positive: Color(0xFF3E9E6C),
    negative: Color(0xFFD9576E),
  );

  static const darkPalette = Palette(
    dark: true,
    window: Color(0x911A1C33),
    sidebar: Color(0x40121428),
    card: Color(0x14E4E6F4),
    text: Color(0xFFE4E6F4),
    dimText: Color(0xFF9296B5),
    accent: Color(0xFF7F8EF5),
    onAccent: Color(0xFFFFFFFF),
    rim: Color(0x1FFFFFFF),
    hover: Color(0x14E4E6F4),
    positive: Color(0xFF8FD3A8),
    negative: Color(0xFFF28B9B),
  );

  /// Light or dark, from the colour scheme Plasma is using: the user's
  /// kdeglobals if they picked one, else the look-and-feel default.
  static Palette current() {
    final home = Platform.environment['HOME'] ?? '';
    final config = Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config';
    for (final path in ['$config/kdeglobals', '$config/kdedefaults/kdeglobals']) {
      final scheme = _iniValue(path, 'General', 'ColorScheme');
      if (scheme != null) {
        return scheme.toLowerCase().contains('dark') ? darkPalette : light;
      }
    }
    return darkPalette;
  }

  ThemeData theme() {
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
    );
  }
}

String? _iniValue(String path, String group, String key) {
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
