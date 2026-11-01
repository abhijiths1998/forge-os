// The wallpaper picker, from the desktop's right-click menu: the
// wallpapers installed on the system and the pictures in ~/Pictures, as
// thumbnails. Picking one writes its path to ~/.config/forge/wallpaper,
// which the wallpaper part follows; "Forge Glass" goes back to the
// default (light or dark with the theme).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'style.dart';

const _images = {'.jpg', '.jpeg', '.png', '.webp'};

File get _chosenFile =>
    File('${ForgeTheme.currentFile.parent.path}/wallpaper');

/// Every wallpaper on offer: KDE-style packages (the largest image of each,
/// the dark one too if it has one) and loose pictures.
List<String> findWallpapers() {
  final found = <String>[];
  bool isImage(String path) =>
      _images.any((e) => path.toLowerCase().endsWith(e));

  String? largest(Directory dir) {
    try {
      final files = dir.listSync().whereType<File>().where(
        (f) => isImage(f.path),
      );
      if (files.isEmpty) return null;
      return files
          .reduce((a, b) => a.lengthSync() >= b.lengthSync() ? a : b)
          .path;
    } on FileSystemException catch (_) {
      return null;
    }
  }

  final home = Platform.environment['HOME'] ?? '';
  for (final root in [
    '/usr/share/wallpapers',
    '$home/.local/share/wallpapers',
  ]) {
    try {
      for (final pkg in Directory(root).listSync().whereType<Directory>()) {
        if (pkg.path.endsWith('/ForgeGlass')) continue; // the default tile
        for (final sub in ['images', 'images_dark']) {
          final img = largest(Directory('${pkg.path}/contents/$sub'));
          if (img != null) found.add(img);
        }
      }
      for (final f in Directory(root).listSync().whereType<File>()) {
        if (isImage(f.path)) found.add(f.path);
      }
    } on FileSystemException catch (_) {}
  }
  for (final dir in ['$home/Pictures/Wallpapers', '$home/Pictures']) {
    try {
      for (final f in Directory(dir).listSync().whereType<File>()) {
        if (isImage(f.path)) found.add(f.path);
      }
    } on FileSystemException catch (_) {}
  }
  return found.toSet().toList();
}

class WallpaperPicker extends StatefulWidget {
  const WallpaperPicker({
    super.key,
    required this.palette,
    required this.onClose,
  });

  final ForgePalette palette;
  final VoidCallback onClose;

  @override
  State<WallpaperPicker> createState() => _WallpaperPickerState();
}

class _WallpaperPickerState extends State<WallpaperPicker> {
  final _all = findWallpapers();
  late String _chosen = _read();

  static String _read() {
    try {
      return _chosenFile.readAsStringSync().trim();
    } on FileSystemException catch (_) {
      return '';
    }
  }

  void _choose(String path) {
    try {
      if (path.isEmpty) {
        if (_chosenFile.existsSync()) _chosenFile.deleteSync();
      } else {
        _chosenFile.parent.createSync(recursive: true);
        _chosenFile.writeAsStringSync('$path\n');
      }
    } on FileSystemException catch (_) {}
    setState(() => _chosen = path);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return PopupCard(
      palette: p,
      width: 760,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: SizedBox(
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wallpaper_rounded, color: p.accent),
                const SizedBox(width: 10),
                Text(
                  'Wallpaper',
                  style: TextStyle(
                    color: p.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                DialogButton(
                  palette: p,
                  label: 'Done',
                  primary: true,
                  onTap: widget.onClose,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 16 / 10,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemCount: _all.length + 1,
                itemBuilder: (context, i) => i == 0
                    ? _Thumb(
                        palette: p,
                        path: null,
                        label: 'Forge Glass',
                        selected: _chosen.isEmpty,
                        onTap: () => _choose(''),
                      )
                    : _Thumb(
                        palette: p,
                        path: _all[i - 1],
                        selected: _chosen == _all[i - 1],
                        onTap: () => _choose(_all[i - 1]),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Add your own to ~/Pictures/Wallpapers.',
              style: TextStyle(color: p.dimText, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.palette,
    required this.path,
    required this.selected,
    required this.onTap,
    this.label,
  });

  final ForgePalette palette;
  final String? path;
  final bool selected;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final glass = '/usr/share/wallpapers/ForgeGlass/contents/'
        '${p.dark ? 'images_dark' : 'images'}';
    String? image = path;
    if (image == null) {
      try {
        image = Directory(glass).listSync().whereType<File>().first.path;
      } catch (_) {}
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected ? p.accent : Colors.transparent,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (image != null)
                  Image.file(
                    File(image),
                    fit: BoxFit.cover,
                    cacheWidth: 320,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, _, _) => ColoredBox(color: p.hover),
                  )
                else
                  ColoredBox(color: p.hover),
                if (label != null)
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Container(
                      margin: const EdgeInsets.all(6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        label!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
