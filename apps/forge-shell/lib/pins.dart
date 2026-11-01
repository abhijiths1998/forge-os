// Pinned apps: the dock's (~/.config/forge/dock.json) and the start
// menu's (~/.config/forge/start.json), each a JSON list of desktop ids.
// Every shell part watches ~/.config/forge, so a change shows everywhere.
import 'dart:convert';
import 'dart:io';

import 'package:forge_ui/forge_ui.dart';

class Pins {
  const Pins._(this.name, this.defaults);

  final String name;
  final List<String> defaults;

  static const dock = Pins._('dock.json', [
    'org.forgeos.browser.desktop',
    'org.forgeos.files.desktop',
    'org.forgeos.terminal.desktop',
    'org.forgeos.store.desktop',
    'steam.desktop',
    'net.lutris.Lutris.desktop',
    'org.forgeos.themekit.desktop',
  ]);

  static const start = Pins._('start.json', [
    'org.forgeos.browser.desktop',
    'org.forgeos.files.desktop',
    'org.forgeos.terminal.desktop',
    'org.forgeos.calendar.desktop',
    'org.forgeos.store.desktop',
    'steam.desktop',
    'net.lutris.Lutris.desktop',
    'org.forgeos.themekit.desktop',
    'org.forgeos.thermal.desktop',
    'org.forgeos.shot.desktop',
    'org.kde.kate.desktop',
    'org.kde.gwenview.desktop',
    'org.kde.okular.desktop',
  ]);

  File get file => File('${ForgeTheme.currentFile.parent.path}/$name');

  List<String> read() {
    try {
      return [
        for (final id in jsonDecode(file.readAsStringSync()) as List)
          id as String,
      ];
    } catch (_) {
      return defaults;
    }
  }

  void write(List<String> ids) {
    try {
      file.parent.createSync(recursive: true);
      // Written beside and renamed over, so no part reads half a file.
      final tmp = File('${file.path}.tmp');
      tmp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(ids));
      tmp.renameSync(file.path);
    } on FileSystemException catch (_) {}
  }

  bool has(String id) => read().contains(id);

  void toggle(String id) {
    final ids = read();
    if (!ids.remove(id)) ids.add(id);
    write(ids);
  }
}
