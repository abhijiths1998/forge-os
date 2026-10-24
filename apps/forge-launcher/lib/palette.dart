// Forge Glass colours, from branding-source/glass/colors.py (keep in step),
// and which variant the desktop is using right now.
import 'dart:io';

import 'package:flutter/painting.dart';

const fontFamily = 'Plus Jakarta Sans';

class Palette {
  const Palette({
    required this.dark,
    required this.surface,
    required this.text,
    required this.dimText,
    required this.accent,
    required this.onAccent,
    required this.rim,
    required this.hover,
  });

  final bool dark;

  /// Card background: translucent, so KWin's Glass effect shows through.
  final Color surface;
  final Color text;
  final Color dimText;
  final Color accent;
  final Color onAccent;

  /// Hairline around the card, like the glass edge lighting elsewhere.
  final Color rim;
  final Color hover;

  static const light = Palette(
    dark: false,
    surface: Color(0x9EF3F2FA),
    text: Color(0xFF1E2140),
    dimText: Color(0xFF6E7391),
    accent: Color(0xFF6C7CF0),
    onAccent: Color(0xFFFFFFFF),
    rim: Color(0x66FFFFFF),
    hover: Color(0x141E2140),
  );

  static const darkPalette = Palette(
    dark: true,
    surface: Color(0x9E1A1C33),
    text: Color(0xFFE4E6F4),
    dimText: Color(0xFF9296B5),
    accent: Color(0xFF7F8EF5),
    onAccent: Color(0xFFFFFFFF),
    rim: Color(0x26FFFFFF),
    hover: Color(0x14E4E6F4),
  );

  /// Light or dark, from the colour scheme Plasma is using: the user's
  /// kdeglobals if they picked one, else the look-and-feel default.
  static Palette current() {
    final home = Platform.environment['HOME'] ?? '';
    final config =
        Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config';
    for (final path in ['$config/kdeglobals', '$config/kdedefaults/kdeglobals']) {
      final scheme = _iniValue(path, 'General', 'ColorScheme');
      if (scheme != null) {
        return scheme.toLowerCase().contains('dark') ? darkPalette : light;
      }
    }
    return darkPalette;
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
