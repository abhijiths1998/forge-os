// The Forge Glass themes must reproduce the shipped Forge Glass colour
// schemes (branding-source/glass/colors.py's output), so applying "Forge
// Glass" in the Theming Kit changes nothing.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';

Map<String, String> entries(String scheme) {
  final out = <String, String>{};
  var group = '';
  for (final line in scheme.split('\n')) {
    if (line.startsWith('[')) {
      group = line;
    } else if (line.contains('=') && !line.startsWith('#')) {
      final i = line.indexOf('=');
      out['$group ${line.substring(0, i)}'] = line.substring(i + 1);
    }
  }
  return out;
}

/// Equal, or within 1 per channel (HSL round trips).
bool close(String want, String? got) {
  if (got == null) return false;
  final a = want.split(',').map(int.tryParse).toList();
  final b = got.split(',').map(int.tryParse).toList();
  if (a.length != b.length || a.contains(null) || b.contains(null)) return want == got;
  for (var i = 0; i < a.length; i++) {
    if ((a[i]! - b[i]!).abs() > 1) return false;
  }
  return true;
}

void main() {
  const shipped = '../../profile/airootfs/usr/share/color-schemes';
  for (final (theme, file) in [
    (forgeGlass, 'ForgeGlassDark.colors'),
    (builtInThemes[1], 'ForgeGlassLight.colors'),
  ]) {
    test('${theme.name} matches $file', () {
      final want = entries(File('$shipped/$file').readAsStringSync());
      final got = entries(kdeColourScheme(theme, ident: 'x'));
      final differ = <String>[];
      for (final key in want.keys) {
        // Names differ by design.
        if (key.startsWith('[General]')) continue;
        if (!close(want[key]!, got[key])) differ.add('$key: ${want[key]} vs ${got[key]}');
      }
      expect(differ, isEmpty, reason: differ.join('\n'));
    });
  }
}
