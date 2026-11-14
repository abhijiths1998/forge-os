// Default apps page: which app opens terminals, files, the browser and
// settings. forge-open (used by the keybinds) honours these through
// xdg-settings / xdg-terminal-exec; this page lets the user pick the default
// web browser (the one thing xdg-settings actually tracks) and shows what
// forge-open does for the rest.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart' hide SectionLabel;

import '../widgets.dart';

class DefaultAppsPage extends StatefulWidget {
  const DefaultAppsPage({super.key});

  @override
  State<DefaultAppsPage> createState() => _DefaultAppsPageState();
}

class _DefaultAppsPageState extends State<DefaultAppsPage> {
  static const _browsers = <String>['forge-browser', 'brave', 'firefox', 'chromium'];

  String _currentBrowser = '';
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    String current = '';
    try {
      final r = await Process.run('xdg-settings', ['get', 'default-web-browser']);
      if (r.exitCode == 0) {
        final desktop = (r.stdout as String).trim();
        // desktop is like org.forgeos.browser.desktop; map back to a name.
        current = _browserFromDesktop(desktop);
        if (current.isEmpty) current = desktop;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _currentBrowser = current);
  }

  /// Map a .desktop file name to one of the known browsers, best effort.
  String _browserFromDesktop(String desktop) {
    final lower = desktop.toLowerCase();
    for (final b in _browsers) {
      if (lower.contains(b)) return b;
    }
    return '';
  }

  Future<void> _save() async {
    if (_currentBrowser.isEmpty) {
      setState(() {
        _error = 'Pick a browser first.';
        _busy = false;
      });
      return;
    }
    try {
      final desktop = '${_currentBrowser.toLowerCase().replaceAll(' ', '-')}.desktop';
      await Process.run('xdg-settings', ['set', 'default-web-browser', desktop]);
      setState(() {
        _error = null;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = "Couldn't set the default browser: $e";
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return SettingsPage(
      title: 'Default apps',
      sub: 'Which app opens what. forge-open (and the keybinds) use these.',
      error: _error,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingRow(
            label: 'Web browser',
            desc: 'Opened by Super+B and by links. Written through xdg-settings.',
            control: SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                value: _currentBrowser.isEmpty ? null : _currentBrowser,
                items: _browsers
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _currentBrowser = v);
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          SectionLabel('How forge-open decides', palette: p),
          Text(
            '• terminal: xdg-terminal-exec (Forge Terminal), falling back to foot.\n'
            '• files: xdg-open $HOME.\n'
            '• browser: the default-web-browser above, then forge-browser / brave / '
                'firefox / chromium.\n'
            '• settings: Forge Settings, then the Theming Kit.',
            style: TextStyle(fontSize: 12.5, color: p.dimText),
          ),
          const SizedBox(height: 10),
          ApplyButton(
            label: 'Apply',
            onTap: () {
              setState(() => _busy = true);
              _save();
            },
            busy: _busy,
          ),
        ],
      ),
    );
  }
}
