// Forge Shell: the parts of the Forge desktop that are always on screen.
// Each runs as its own process, named by the first argument (see the
// runner): the top bar, the dock, the wallpaper, and the popups (start
// menu, menus, dialogs, polkit's prompt). The compositor manages the
// windows; this draws everything around them, in the Forge Glass look.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'bar.dart';
import 'dock.dart';
import 'popups/popups.dart';
import 'wallpaper.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ShellApp(role: args.isEmpty ? 'bar' : args.first));
}

/// The desktop's palette, kept current: the Theming Kit rewrites
/// ~/.config/forge/theme.json, and every part follows within a moment.
class ThemeWatch extends ValueNotifier<ForgePalette> {
  ThemeWatch() : super(ForgePalette.current()) {
    final dir = ForgeTheme.currentFile.parent;
    try {
      dir.createSync(recursive: true);
      _watch = dir.watch().listen((_) {
        _debounce?.cancel();
        _debounce = Timer(
          const Duration(milliseconds: 300),
          () => value = ForgePalette.current(),
        );
      });
    } on FileSystemException catch (_) {}
  }

  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _debounce;

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }
}

class ShellApp extends StatefulWidget {
  const ShellApp({super.key, required this.role});

  final String role;

  @override
  State<ShellApp> createState() => _ShellAppState();
}

class _ShellAppState extends State<ShellApp> {
  final _theme = ThemeWatch();

  @override
  void dispose() {
    _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ForgePalette>(
      valueListenable: _theme,
      builder: (context, palette, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: palette.materialTheme(),
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: switch (widget.role) {
            'dock' => Dock(palette: palette),
            'wallpaper' => Wallpaper(palette: palette),
            'popups' => PopupsHost(palette: palette),
            _ => Bar(palette: palette),
          },
        ),
      ),
    );
  }
}
