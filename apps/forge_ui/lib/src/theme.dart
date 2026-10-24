// A Forge theme: everything the Theming Kit sets, as one value that can be
// saved, shared and applied. The desktop's current theme is
// ~/.config/forge/theme.json, which the Forge apps read for their colours.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';

class ForgeTheme {
  const ForgeTheme({
    required this.id,
    required this.name,
    this.dark = true,
    this.accent = const Color(0xFF7F8EF5),
    this.tintHue = referenceHue,
    this.tintStrength = 1.0,
    this.blur = 7,
    this.saturation = 1.7,
    this.lensWidth = 2.5,
    this.lensStrength = 10,
    this.bevel = 7,
    this.innerBend = 0,
    this.colourSplit = 0,
    this.grain = 0,
    this.windowOpacity = 41,
    this.menuOpacity = 58,
    this.terminalOpacity = 64,
    this.cornerRadius = 14,
  });

  /// The hue Forge Glass's own colours sit at; tinting rotates them away
  /// from it, so a tint of [referenceHue] at strength 1 is Forge Glass.
  static const double referenceHue = 235;

  final String id;
  final String name;

  // --- Colour
  final bool dark;
  final Color accent;

  /// Hue (0-360) the glass surfaces are tinted towards.
  final double tintHue;

  /// How coloured the glass is: 0 neutral grey, 1 Forge Glass, 2 vivid.
  final double tintStrength;

  // --- Liquid glass (KWin's Glass effect, [Effect-blurplus] in kwinrc)
  final int blur; // BlurStrength, 1-15
  final double saturation; // vibrancy, 0.5-2.5
  final double lensWidth; // RefractionEdgeSize, x10 px
  final int lensStrength; // RefractionStrength, 0-20
  final int bevel; // RefractionBevelIntensity, 5-15
  final int innerBend; // BodyRefractionStrength, 0 (off) - 100
  final int colourSplit; // RefractionRGBFringing, 0-20
  final int grain; // NoiseStrength, 0-14

  // --- Surfaces, in percent opaque
  final int windowOpacity; // colour scheme backgrounds
  final int menuOpacity; // Darkly menus, toolbars, tab bars
  final int terminalOpacity; // Konsole

  // --- Shape
  final int cornerRadius; // window corners, px

  ForgeTheme copyWith({
    String? id,
    String? name,
    bool? dark,
    Color? accent,
    double? tintHue,
    double? tintStrength,
    int? blur,
    double? saturation,
    double? lensWidth,
    int? lensStrength,
    int? bevel,
    int? innerBend,
    int? colourSplit,
    int? grain,
    int? windowOpacity,
    int? menuOpacity,
    int? terminalOpacity,
    int? cornerRadius,
  }) =>
      ForgeTheme(
        id: id ?? this.id,
        name: name ?? this.name,
        dark: dark ?? this.dark,
        accent: accent ?? this.accent,
        tintHue: tintHue ?? this.tintHue,
        tintStrength: tintStrength ?? this.tintStrength,
        blur: blur ?? this.blur,
        saturation: saturation ?? this.saturation,
        lensWidth: lensWidth ?? this.lensWidth,
        lensStrength: lensStrength ?? this.lensStrength,
        bevel: bevel ?? this.bevel,
        innerBend: innerBend ?? this.innerBend,
        colourSplit: colourSplit ?? this.colourSplit,
        grain: grain ?? this.grain,
        windowOpacity: windowOpacity ?? this.windowOpacity,
        menuOpacity: menuOpacity ?? this.menuOpacity,
        terminalOpacity: terminalOpacity ?? this.terminalOpacity,
        cornerRadius: cornerRadius ?? this.cornerRadius,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'dark': dark,
        'accent': hex(accent),
        'tintHue': tintHue,
        'tintStrength': tintStrength,
        'blur': blur,
        'saturation': saturation,
        'lensWidth': lensWidth,
        'lensStrength': lensStrength,
        'bevel': bevel,
        'innerBend': innerBend,
        'colourSplit': colourSplit,
        'grain': grain,
        'windowOpacity': windowOpacity,
        'menuOpacity': menuOpacity,
        'terminalOpacity': terminalOpacity,
        'cornerRadius': cornerRadius,
      };

  /// Missing or malformed fields fall back to Forge Glass's.
  factory ForgeTheme.fromJson(Map<String, dynamic> j) {
    const d = forgeGlass;
    num n(String k, num fallback) => j[k] is num ? j[k] as num : fallback;
    return ForgeTheme(
      id: j['id'] is String ? j['id'] as String : 'custom',
      name: j['name'] is String ? j['name'] as String : 'Custom',
      dark: j['dark'] is bool ? j['dark'] as bool : d.dark,
      accent: parseHex(j['accent']) ?? d.accent,
      tintHue: n('tintHue', d.tintHue).toDouble(),
      tintStrength: n('tintStrength', d.tintStrength).toDouble(),
      blur: n('blur', d.blur).round(),
      saturation: n('saturation', d.saturation).toDouble(),
      lensWidth: n('lensWidth', d.lensWidth).toDouble(),
      lensStrength: n('lensStrength', d.lensStrength).round(),
      bevel: n('bevel', d.bevel).round(),
      innerBend: n('innerBend', d.innerBend).round(),
      colourSplit: n('colourSplit', d.colourSplit).round(),
      grain: n('grain', d.grain).round(),
      windowOpacity: n('windowOpacity', d.windowOpacity).round(),
      menuOpacity: n('menuOpacity', d.menuOpacity).round(),
      terminalOpacity: n('terminalOpacity', d.terminalOpacity).round(),
      cornerRadius: n('cornerRadius', d.cornerRadius).round(),
    );
  }

  // --- Where themes live

  static String get _configDir {
    final home = Platform.environment['HOME'] ?? '';
    final config = Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config';
    return '$config/forge';
  }

  /// The desktop's theme, as last applied by the Theming Kit.
  static File get currentFile => File('$_configDir/theme.json');

  /// Themes the user saved.
  static Directory get savedDir => Directory('$_configDir/themes');

  /// The applied theme, or null if the kit was never used (the desktop is
  /// then stock Forge Glass, light or dark).
  static ForgeTheme? current() {
    try {
      return ForgeTheme.fromJson(
          jsonDecode(currentFile.readAsStringSync()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static List<ForgeTheme> saved() {
    final dir = savedDir;
    if (!dir.existsSync()) return [];
    final out = <ForgeTheme>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      try {
        out.add(ForgeTheme.fromJson(
            jsonDecode(f.readAsStringSync()) as Map<String, dynamic>));
      } catch (_) {}
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  void writeTo(File file) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(toJson()));
  }
}

String hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Color? parseHex(Object? v) {
  if (v is! String) return null;
  final h = v.replaceFirst('#', '');
  final n = int.tryParse(h, radix: 16);
  return n == null || h.length != 6 ? null : Color(0xFF000000 | n);
}

// --- Built-in themes ---------------------------------------------------------
// Forge Glass is the desktop as shipped (etc/skel/.config/kwinrc, the
// ForgeGlass colour schemes, darklyrc); the rest vary colour and glass.

const forgeGlass = ForgeTheme(id: 'forge-glass', name: 'Forge Glass');

const builtInThemes = <ForgeTheme>[
  forgeGlass,
  ForgeTheme(
    id: 'forge-glass-light',
    name: 'Forge Glass Light',
    dark: false,
    accent: Color(0xFF6C7CF0),
  ),
  ForgeTheme(
    id: 'frost',
    name: 'Frost',
    blur: 11,
    saturation: 1.8,
    lensWidth: 1.2,
    lensStrength: 5,
    bevel: 5,
    windowOpacity: 48,
  ),
  ForgeTheme(
    id: 'liquid-bold',
    name: 'Liquid Bold',
    blur: 6,
    lensWidth: 3,
    lensStrength: 12,
    bevel: 8,
    innerBend: 12,
    windowOpacity: 36,
  ),
  ForgeTheme(
    id: 'midnight',
    name: 'Midnight',
    accent: Color(0xFF5CC8FF),
    tintHue: 225,
    tintStrength: 0.35,
    blur: 9,
    windowOpacity: 55,
    menuOpacity: 66,
  ),
  ForgeTheme(
    id: 'ember',
    name: 'Ember',
    accent: Color(0xFFFF8A4C),
    tintHue: 18,
    tintStrength: 0.8,
  ),
  ForgeTheme(
    id: 'aurora',
    name: 'Aurora',
    accent: Color(0xFF4FE3C1),
    tintHue: 280,
    tintStrength: 1.1,
  ),
  ForgeTheme(
    id: 'mint',
    name: 'Mint',
    dark: false,
    accent: Color(0xFF22A884),
    tintHue: 160,
    tintStrength: 0.9,
  ),
  ForgeTheme(
    id: 'rose',
    name: 'Rosé',
    accent: Color(0xFFFF7AA8),
    tintHue: 335,
    tintStrength: 0.9,
  ),
];
