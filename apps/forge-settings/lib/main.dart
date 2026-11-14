// Forge Settings: the settings app for newcomers on Hyprland, where Hyprland
// itself has none. Pages: displays, keyboard, mouse, default apps, startup,
// sound, network/VPN, Bluetooth, users, about — plus a shortcuts editor that
// rebinds keys, detects conflicts and writes ~/.config/hypr/keybinds.user.lua.
//
// The shortcuts page reads `hyprctl binds -j`, which carries every Forge
// bind's "[Category] description", and lets the user change any key. Changes
// are validated (a key already bound elsewhere is a conflict) and written to
// keybinds.user.lua, which ~/.config/hypr/hyprland.lua loads after Forge's
// own keybinds.lua, so the user's overrides win.
//
// Config errors (a bad monitor line, a bad bind) surface as a readable
// notification with file and line, never the raw Hyprland red bar.
//
// Flutter on forge_ui. The .desktop, PKGBUILD and README live next to this.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'pages/about_page.dart';
import 'pages/bluetooth_page.dart';
import 'pages/default_apps_page.dart';
import 'pages/displays_page.dart';
import 'pages/keyboard_page.dart';
import 'pages/mouse_page.dart';
import 'pages/network_page.dart';
import 'pages/shortcuts_page.dart';
import 'pages/startup_page.dart';
import 'pages/sound_page.dart';
import 'pages/users_page.dart';

void main() => runApp(const SettingsApp());

class SettingsApp extends StatelessWidget {
  const SettingsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Forge Settings',
      color: Colors.transparent,
      theme: p.materialTheme(),
      home: const SettingsHome(),
    );
  }
}

class SettingsHome extends StatefulWidget {
  const SettingsHome({super.key});

  @override
  State<SettingsHome> createState() => _SettingsHomeState();
}

class _SettingsHomeState extends State<SettingsHome> {
  int _page = 0;

  static final _pages = <(String, WidgetBuilder)>[
    ('Displays', (_) => const DisplaysPage()),
    ('Keyboard', (_) => const KeyboardPage()),
    ('Mouse & touchpad', (_) => const MousePage()),
    ('Shortcuts', (_) => const ShortcutsPage()),
    ('Default apps', (_) => const DefaultAppsPage()),
    ('Startup apps', (_) => const StartupPage()),
    ('Sound', (_) => const SoundPage()),
    ('Network & VPN', (_) => const NetworkPage()),
    ('Bluetooth', (_) => const BluetoothPage()),
    ('Users', (_) => const UsersPage()),
    ('About', (_) => const AboutPage()),
  ];

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return Material(
      color: p.window,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Forge Settings',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: p.text),
                ),
                const SizedBox(height: 4),
                Text(
                  'Displays, keyboard, shortcuts and everything else Hyprland '
                  "doesn't have a settings app for.",
                  style: TextStyle(fontSize: 13, color: p.dimText),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                // Sidebar.
                SizedBox(
                  width: 220,
                  child: ListView.builder(
                    itemCount: _pages.length,
                    itemBuilder: (context, i) {
                      final selected = _page == i;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: GlassCard(
                          palette: p,
                          selected: selected,
                          radius: 10,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          onTap: () => setState(() => _page = i),
                          child: Row(
                            children: [
                              Text(
                                _pages[i].$1,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: selected ? p.onAccent : p.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: _pages[_page].$2(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The directory Forge Settings writes user overrides into:
///   $XDG_CONFIG_HOME/hypr  (default ~/.config/hypr)
/// It exists because ~/.config/hypr/hyprland.lua loads Forge's defaults and
/// then the user's files, which win.
String get hyprConfigDir {
  final home = Platform.environment['HOME'] ?? '';
  final xdg = Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config';
  return '$xdg/hypr';
}

/// A user override file in $XDG_CONFIG_HOME/hypr. The directory is created
/// if missing. The caller must make sure what it writes is syntactically
/// valid Lua, because a bad line lands Hyprland in the raw red bar — the
/// notifier turns that into a readable message with file and line.
File hyprFile(String name) {
  final dir = Directory(hyprConfigDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return File('$dir/$name');
}

/// Run a command and return its stdout, or throw with its stderr.
Future<String> runCommand(List<String> args) async {
  final r = await Process.run(args[0], args.sublist(1));
  if (r.exitCode != 0) {
    throw Exception((r.stderr as String).trim().isNotEmpty
        ? (r.stderr as String).trim()
        : 'command failed (exit ${r.exitCode})');
  }
  return (r.stdout as String).trim();
}
