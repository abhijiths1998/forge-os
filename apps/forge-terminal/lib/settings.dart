// Forge Terminal's own settings (~/.config/forge/terminal.json) and the
// colours it takes from the desktop's theme.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:xterm/xterm.dart';

enum CursorShape { block, bar, underline }

class TerminalSettings {
  const TerminalSettings({
    this.fontFamily,
    this.fontSize = 11,
    this.cursor = CursorShape.bar,
    this.opacity,
    this.scrollback = 10000,
    this.shell,
    this.confirmClose = true,
    this.lightFollowsDesktop = false,
  });

  /// Null: the desktop's fixed-width font (kdeglobals' "fixed").
  final String? fontFamily;
  final double fontSize;
  final CursorShape cursor;

  /// Background opacity, 0-100. Null: the theme's terminal opacity, as the
  /// Theming Kit sets it.
  final int? opacity;
  final int scrollback;

  /// Null: the account's shell.
  final String? shell;

  /// Ask before closing a tab that's running something.
  final bool confirmClose;

  /// Light colours when the desktop is light (otherwise always the navy
  /// glass terminals read best in).
  final bool lightFollowsDesktop;

  TerminalSettings copyWith({
    String? Function()? fontFamily,
    double? fontSize,
    CursorShape? cursor,
    int? Function()? opacity,
    int? scrollback,
    String? Function()? shell,
    bool? confirmClose,
    bool? lightFollowsDesktop,
  }) =>
      TerminalSettings(
        fontFamily: fontFamily != null ? fontFamily() : this.fontFamily,
        fontSize: fontSize ?? this.fontSize,
        cursor: cursor ?? this.cursor,
        opacity: opacity != null ? opacity() : this.opacity,
        scrollback: scrollback ?? this.scrollback,
        shell: shell != null ? shell() : this.shell,
        confirmClose: confirmClose ?? this.confirmClose,
        lightFollowsDesktop: lightFollowsDesktop ?? this.lightFollowsDesktop,
      );

  static File get file => File('${_configHome()}/forge/terminal.json');

  static TerminalSettings load() {
    try {
      final j = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return TerminalSettings(
        fontFamily: j['fontFamily'] as String?,
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 11,
        cursor: CursorShape.values.asNameMap()[j['cursor']] ?? CursorShape.bar,
        opacity: (j['opacity'] as num?)?.round(),
        scrollback: (j['scrollback'] as num?)?.round() ?? 10000,
        shell: j['shell'] as String?,
        confirmClose: j['confirmClose'] as bool? ?? true,
        lightFollowsDesktop: j['lightFollowsDesktop'] as bool? ?? false,
      );
    } catch (_) {
      return const TerminalSettings();
    }
  }

  void save() {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'cursor': cursor.name,
      'opacity': opacity,
      'scrollback': scrollback,
      'shell': shell,
      'confirmClose': confirmClose,
      'lightFollowsDesktop': lightFollowsDesktop,
    }));
  }

  String get resolvedFont => fontFamily ?? desktopFixedFont();

  TerminalCursorType get cursorType => switch (cursor) {
        CursorShape.block => TerminalCursorType.block,
        CursorShape.bar => TerminalCursorType.verticalBar,
        CursorShape.underline => TerminalCursorType.underline,
      };
}

String _configHome() {
  final home = Platform.environment['HOME'] ?? '';
  return Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config';
}

/// The desktop's fixed-width font family (kdeglobals [General] fixed).
String desktopFixedFont() {
  final fixed = iniValue('${_configHome()}/kdeglobals', 'General', 'fixed');
  final family = fixed?.split(',').first.trim();
  return (family == null || family.isEmpty) ? 'JetBrainsMono Nerd Font' : family;
}

/// Installed fixed-width font families, for the settings' font picker.
Future<List<String>> monospaceFonts() async {
  try {
    final r = await Process.run('fc-list', [':spacing=mono', 'family']);
    final names = <String>{};
    for (final line in (r.stdout as String).split('\n')) {
      final name = line.split(',').first.trim();
      if (name.isNotEmpty) names.add(name);
    }
    return names.toList()..sort();
  } catch (_) {
    return [desktopFixedFont()];
  }
}

/// The terminal's colours: Konsole's Forge Glass scheme (the one the
/// Theming Kit writes), the selection and cursor in the theme's accent.
class TerminalColours {
  TerminalColours(this.palette, this.settings);

  final ForgePalette palette;
  final TerminalSettings settings;

  bool get light => settings.lightFollowsDesktop && !palette.dark;

  double get opacity => (settings.opacity ?? palette.theme.terminalOpacity) / 100;

  Color get background => light ? const Color(0xFFF4F5FB) : konsoleColours(palette.theme)['Background']!;
  Color get foreground => light ? const Color(0xFF262A40) : konsoleColours(palette.theme)['Foreground']!;

  /// The window behind the tab strip and the terminal.
  Color get window => background.withValues(alpha: opacity);

  TerminalTheme get theme {
    if (light) return _lightTheme;
    final k = konsoleColours(palette.theme);
    return TerminalTheme(
      cursor: palette.accent,
      selection: palette.accent.withValues(alpha: 0.38),
      foreground: k['Foreground']!,
      // Painted by the window (with the opacity), not by the view.
      background: Colors.transparent,
      black: k['Color0']!,
      red: k['Color1']!,
      green: k['Color2']!,
      yellow: k['Color3']!,
      blue: k['Color4']!,
      magenta: k['Color5']!,
      cyan: k['Color6']!,
      white: k['Color7']!,
      brightBlack: k['Color0Intense']!,
      brightRed: k['Color1Intense']!,
      brightGreen: k['Color2Intense']!,
      brightYellow: k['Color3Intense']!,
      brightBlue: k['Color4Intense']!,
      brightMagenta: k['Color5Intense']!,
      brightCyan: k['Color6Intense']!,
      brightWhite: k['Color7Intense']!,
      searchHitBackground: const Color(0xFFF6CFA8),
      searchHitBackgroundCurrent: palette.accent,
      searchHitForeground: const Color(0xFF232640),
    );
  }

  // Light: the same hues, deep enough to read on a pale glass.
  TerminalTheme get _lightTheme => TerminalTheme(
        cursor: palette.accent,
        selection: palette.accent.withValues(alpha: 0.30),
        foreground: const Color(0xFF262A40),
        background: Colors.transparent,
        black: const Color(0xFF2E3254),
        red: const Color(0xFFC4334F),
        green: const Color(0xFF2A8A55),
        yellow: const Color(0xFFA86A16),
        blue: const Color(0xFF3F55D6),
        magenta: const Color(0xFF8A4FC8),
        cyan: const Color(0xFF2A7FAE),
        white: const Color(0xFF8A8DA6),
        brightBlack: const Color(0xFF5A5F86),
        brightRed: const Color(0xFFD9506A),
        brightGreen: const Color(0xFF38A56A),
        brightYellow: const Color(0xFFC0812A),
        brightBlue: const Color(0xFF5A6BE0),
        brightMagenta: const Color(0xFF9A6BD8),
        brightCyan: const Color(0xFF3B95C4),
        brightWhite: const Color(0xFF262A40),
        searchHitBackground: const Color(0xFFF6CFA8),
        searchHitBackgroundCurrent: palette.accent,
        searchHitForeground: const Color(0xFF262A40),
      );
}
