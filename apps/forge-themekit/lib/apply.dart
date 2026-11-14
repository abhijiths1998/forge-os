// Applying a ForgeTheme to the desktop. Everything follows
// ~/.config/forge/theme.json: Hyprland's look (forge-session's theme.lua
// reads it), Forge's shell (it watches it), the Forge apps and Forge Code.
// forge-theme-sync takes it to GTK and Qt apps, the terminal prompt,
// Flatpak and the login screen.
//   glass   - Hyprland's blur, edge and corners: cheap, so sliders apply
//             them as they move (`hyprctl reload`);
//   colours - everything else too: apps repaint, so this waits for a
//             slider's release.
import 'dart:io';

import 'package:forge_ui/forge_ui.dart';

class Applier {
  Future<void> _run(String cmd, List<String> args) async {
    try {
      await Process.run(cmd, args);
    } catch (_) {
      // not installed: the rest still applies
    }
  }

  Future<void> glass(ForgeTheme t) async {
    t.writeTo(ForgeTheme.currentFile);
    await _run('hyprctl', ['reload']);
  }

  Future<void> colours(ForgeTheme t) async {
    t.writeTo(ForgeTheme.currentFile);
    await _run('forge-theme-sync', []);
  }

  Future<void> all(ForgeTheme t) async {
    t.writeTo(ForgeTheme.currentFile);
    await _run('forge-theme-sync', []);
  }
}
