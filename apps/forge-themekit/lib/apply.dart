// Applying a ForgeTheme to the desktop, in two halves:
//   glass  - KWin's Glass and rounded-corners effects (kwinrc) and Darkly's
//            window corners: cheap, so sliders apply them as they move;
//   colours - a KDE colour scheme, icons for light or dark, Darkly's menu
//            opacities, Konsole's scheme, ~/.config/forge/theme.json, and
//            forge-theme-sync for the rest (login screen, shell, GNOME,
//            Flatpak): every app repaints, so this waits for a slider's release.
import 'dart:io';

import 'package:forge_ui/forge_ui.dart';

class Applier {
  String get _home => Platform.environment['HOME'] ?? '';
  String get _data =>
      Platform.environment['XDG_DATA_HOME'] ?? '$_home/.local/share';

  Future<void> _write(String file, String group, Map<String, Object> entries) async {
    for (final e in entries.entries) {
      await Process.run('kwriteconfig6',
          ['--file', file, '--group', group, '--key', e.key, '${e.value}']);
    }
  }

  Future<void> _qdbus(List<String> args) async {
    try {
      await Process.run('qdbus6', ['org.kde.KWin', ...args]);
    } catch (_) {}
  }

  Future<void> glass(ForgeTheme t) async {
    final r = t.cornerRadius;
    await _write('kwinrc', 'Effect-blurplus', {
      'BlurStrength': t.blur,
      'DecorationBlurStrength': t.blur,
      'DockBlurStrength': (t.blur + 1).clamp(1, 15),
      'Saturation': t.saturation.toStringAsFixed(2),
      'RefractionEdgeSize': t.lensWidth.toStringAsFixed(2),
      'RefractionStrength': t.lensStrength,
      'RefractionBevelIntensity': t.bevel,
      'BodyRefraction': t.innerBend > 0,
      'BodyRefractionStrength': t.innerBend,
      'BodyRefractionReach': 30,
      'RefractionRGBFringing': t.colourSplit,
      'NoiseStrength': t.grain,
      'DockNoiseStrength': t.grain,
      // The glass runs to the edge: nothing draws a border.
      'EdgeLighting': false,
      'EdgeLightingDock': false,
      'EdgeLightingTooltip': false,
      'RimSpecular': false,
      'TopCornerRadius': r,
      'BottomCornerRadius': r,
      'MenuCornerRadius': (r - 4).clamp(0, 24),
    });
    await _write('kwinrc', 'Round-Corners', {'Size': r, 'InactiveCornerRadius': r});
    // Darkly's titlebar corners are in units of 2px (at 1x).
    await _write('darklyrc', 'Windeco', {'OtherCornerRadius': (r / 2).round()});
    await _write('forgerc', 'Glass', {'preset': t.id});
    await _qdbus(['/KWin', 'reconfigure']);
    for (final effect in ['glass', 'kwin4_effect_shapecorners']) {
      await _qdbus(['/Effects', 'unloadEffect', effect]);
      await _qdbus(['/Effects', 'loadEffect', effect]);
    }
  }

  Future<void> colours(ForgeTheme t) async {
    // Plasma won't re-apply a scheme by the name it already uses, so the
    // kit alternates between two names and drops the other file.
    final current = iniValue('$_home/.config/kdeglobals', 'General', 'ColorScheme');
    final ident = current == 'ForgeKitA' ? 'ForgeKitB' : 'ForgeKitA';
    final other = ident == 'ForgeKitA' ? 'ForgeKitB' : 'ForgeKitA';
    final schemes = Directory('$_data/color-schemes')..createSync(recursive: true);
    File('${schemes.path}/$ident.colors').writeAsStringSync(kdeColourScheme(t, ident: ident));
    await Process.run('plasma-apply-colorscheme', [ident]);
    final old = File('${schemes.path}/$other.colors');
    if (old.existsSync()) old.deleteSync();

    // Icons to match light or dark.
    final icons = t.dark ? 'WhiteSur-dark' : 'WhiteSur';
    if (iniValue('$_home/.config/kdeglobals', 'Icons', 'Theme') != icons &&
        File('/usr/lib/plasma-changeicons').existsSync()) {
      await Process.run('/usr/lib/plasma-changeicons', [icons]);
    }

    // Darkly: menus, menubars, toolbars, tab bars, Dolphin's sidebar (apps
    // started after this pick it up).
    final m = t.menuOpacity;
    await _write('darklyrc', 'Style', {
      'MenuOpacity': m,
      'MenuBarOpacity': (m - 10).clamp(0, 100),
      'ToolBarOpacity': (m - 10).clamp(0, 100),
      'TabBarOpacity': (m - 10).clamp(0, 100),
      'DolphinSidebarOpacity': (m - 16).clamp(0, 100),
    });

    await _konsole(t);

    // For the Forge apps (launcher, store...): they read this for colours.
    t.writeTo(ForgeTheme.currentFile);

    // Everywhere KDE's colour scheme doesn't reach: the login screen, the
    // shell's prompt, GNOME's settings, Flatpak apps (forge-theme-sync).
    try {
      await Process.run('forge-theme-sync', []);
    } catch (_) {
      // not installed: the rest of the theme still applied
    }
  }

  /// Konsole: the user's ForgeGlass scheme (the forge-os profile's),
  /// colours and opacity. A Konsole process never re-reads a scheme it has
  /// loaded (checked with inotify), so windows already open keep their
  /// colours; new windows get the theme. Open windows turning opaque on a
  /// light/dark switch was Konsole itself (packages/konsole has the fix).
  /// Written whole and renamed into place, so no reader ever sees half.
  Future<void> _konsole(ForgeTheme t) async {
    final dir = Directory('$_data/konsole')..createSync(recursive: true);
    final scheme = File('${dir.path}/ForgeGlass.colorscheme');
    final tmp = File('${scheme.path}.new')..writeAsStringSync(konsoleColourScheme(t), flush: true);
    tmp.renameSync(scheme.path);
  }

  Future<void> all(ForgeTheme t) async {
    await glass(t);
    await colours(t);
  }
}
