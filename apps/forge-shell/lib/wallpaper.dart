// The wallpaper: the one named in ~/.config/forge/wallpaper (a path), else
// Forge Glass's own, light or dark with the theme. Fades between them when
// either changes. Live wallpapers (2.2) will draw here too. Right-click:
// the desktop's menu (wallpaper, appearance, terminal, files, power).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'native.dart';
import 'popups/client.dart';

const _forgeGlass = '/usr/share/wallpapers/ForgeGlass/contents';

class Wallpaper extends StatelessWidget {
  const Wallpaper({super.key, required this.palette});

  final ForgePalette palette;

  String _path() {
    final chosen = File('${ForgeTheme.currentFile.parent.path}/wallpaper');
    try {
      final path = chosen.readAsStringSync().trim();
      if (path.isNotEmpty && File(path).existsSync()) return path;
    } on FileSystemException catch (_) {}
    final dir = Directory(
      '$_forgeGlass/${palette.dark ? 'images_dark' : 'images'}',
    );
    try {
      final images = dir.listSync().whereType<File>().toList()
        ..sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
      if (images.isNotEmpty) return images.first.path;
    } on FileSystemException catch (_) {}
    return '';
  }

  static final _popups = Popups();

  Future<void> _menu(Offset at) async {
    final picked = await _popups.menu(
      x: at.dx,
      y: at.dy,
      items: const [
        MenuItem('wallpaper', 'Change wallpaper…', icon: 'wallpaper'),
        MenuItem('appearance', 'Appearance…', icon: 'appearance'),
        MenuItem.separator(),
        MenuItem('terminal', 'Open Terminal', icon: 'terminal'),
        MenuItem('files', 'Open Files', icon: 'files'),
        MenuItem.separator(),
        MenuItem('power', 'Power…', icon: 'power'),
      ],
    );
    switch (picked) {
      case 'wallpaper':
        await _popups.wallpapers();
      case 'appearance':
        await Native.run('forge-themekit');
      case 'terminal':
        // Forge Terminal; Konsole where it isn't installed yet.
        await Native.run('sh -c "command -v forge-terminal >/dev/null && exec forge-terminal; exec konsole"');
      case 'files':
        await Native.run('sh -c "command -v forge-files >/dev/null && exec forge-files; exec dolphin"');
      case 'power':
        await _popups.power();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: (d) => _menu(d.globalPosition),
      child: _image(),
    );
  }

  Widget _image() {
    final path = _path();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      child: path.isEmpty
          ? ColoredBox(
              key: const ValueKey(''),
              color: palette.dark
                  ? const Color(0xFF1B1F33)
                  : const Color(0xFFE6E9F5),
            )
          : Image.file(
              File(path),
              key: ValueKey(path),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              filterQuality: FilterQuality.medium,
            ),
    );
  }
}
