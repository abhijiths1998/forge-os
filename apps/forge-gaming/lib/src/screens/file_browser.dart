// Picking a file with a pad: a list of folders and files, A opens or picks,
// B goes up a folder (or closes at the top), LB/RB jump to Home and /.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../pad.dart';
import '../widgets/glass.dart';

/// The entries of [dir] to show: folders first, then files, hidden ones
/// left out, each group sorted case-insensitively.
List<FileSystemEntity> browseEntries(Directory dir, {bool Function(String path)? fileFilter}) {
  List<FileSystemEntity> all;
  try {
    all = dir.listSync(followLinks: true);
  } on FileSystemException {
    return const [];
  }
  String name(FileSystemEntity e) => e.path.split('/').last;
  final dirs = all.whereType<Directory>().where((d) => !name(d).startsWith('.')).toList();
  final files = all
      .whereType<File>()
      .where((f) => !name(f).startsWith('.') && (fileFilter == null || fileFilter(f.path)))
      .toList();
  int byName(FileSystemEntity a, FileSystemEntity b) => name(a).toLowerCase().compareTo(name(b).toLowerCase());
  dirs.sort(byName);
  files.sort(byName);
  return [...dirs, ...files];
}

Future<String?> pickFile(
  BuildContext context, {
  required ForgePalette palette,
  String? start,
  String title = 'Choose a file',
  bool Function(String path)? filter,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (_) => _FileBrowser(palette: palette, start: start, title: title, filter: filter),
  );
}

class _FileBrowser extends StatefulWidget {
  const _FileBrowser({required this.palette, required this.title, this.start, this.filter});
  final ForgePalette palette;
  final String title;
  final String? start;
  final bool Function(String path)? filter;

  @override
  State<_FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<_FileBrowser> {
  static final _home = Platform.environment['HOME'] ?? '/';
  late Directory _dir = _initial();
  bool _all = false;

  Directory _initial() {
    final s = widget.start;
    if (s != null && s.isNotEmpty) {
      final d = FileSystemEntity.isDirectorySync(s) ? Directory(s) : File(s).parent;
      if (d.existsSync()) return d;
    }
    return Directory(_home);
  }

  void _go(Directory d) => setState(() => _dir = d);

  void _up() {
    final parent = _dir.parent;
    if (parent.path == _dir.path) {
      Navigator.of(context).pop();
    } else {
      _go(parent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final entries = browseEntries(_dir, fileFilter: _all ? null : widget.filter);
    return PadShortcuts(
      bindings: {
        PadButton.b: () {
          _up();
          return true;
        },
        PadButton.lb: () {
          _go(Directory(_home));
          return true;
        },
        PadButton.rb: () {
          _go(Directory('/'));
          return true;
        },
        PadButton.x: () {
          setState(() => _all = !_all);
          return true;
        },
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 48),
        child: Glass(
          palette: p,
          strength: 1.6,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text)),
            const SizedBox(height: 4),
            Text(_dir.path, style: TextStyle(fontSize: 12.5, color: p.dimText)),
            const SizedBox(height: 14),
            Expanded(
              child: FocusTraversalGroup(
                child: ListView(
                  key: ValueKey(_dir.path),
                  children: [
                    _row(p, Icons.arrow_upward_rounded, '..', _up, autofocus: entries.isEmpty),
                    for (final (i, e) in entries.indexed)
                      _row(
                        p,
                        e is Directory ? Icons.folder_rounded : Icons.insert_drive_file_outlined,
                        e.path.split('/').last,
                        () => e is Directory ? _go(e) : Navigator.of(context).pop(e.path),
                        autofocus: i == 0,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: PadHintBar(palette: p, hints: [
                  const PadHint(PadButton.a, 'Open'),
                  const PadHint(PadButton.b, 'Up'),
                  const PadHint(PadButton.lb, 'Home'),
                  const PadHint(PadButton.rb, 'Root folder'),
                  if (widget.filter != null) PadHint(PadButton.x, _all ? 'Likely files only' : 'Show all files'),
                ]),
              ),
              ExcludeFocus(
                child: GlassButton(palette: p, label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _row(ForgePalette p, IconData icon, String name, VoidCallback onTap, {bool autofocus = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Focusable(
        autofocus: autofocus,
        onActivate: onTap,
        builder: (context, focused, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: focused
                ? p.accent.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: hovered ? 0.1 : 0),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Icon(icon, size: 18, color: focused ? p.onAccent : p.dimText),
            const SizedBox(width: 12),
            Expanded(
              child: Text(name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: focused ? p.onAccent : p.text, fontSize: 14)),
            ),
          ]),
        ),
      ),
    );
  }
}
