// Startup apps page: what starts with the graphical session. Forge Settings
// writes ~/.config/autostart/*.desktop entries (the XDG autostart Forge
// session honours), so the user can add or drop a startup app without hand
// editing desktop files.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../widgets.dart';

/// One startup entry: name, command, whether it's enabled.
class StartupEntry {
  StartupEntry(this.name, this.command, {this.enabled = true});
  String name;
  String command;
  bool enabled;
}

class StartupPage extends StatefulWidget {
  const StartupPage({super.key});

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  final _entries = <StartupEntry>[];
  String? _error;
  bool _busy = false;
  final _nameC = TextEditingController();
  final _cmdC = TextEditingController();

  static const _autostartDir = 'autostart';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameC.dispose();
    _cmdC.dispose();
    super.dispose();
  }

  String get _dir {
    final home = Platform.environment['HOME'] ?? '';
    final config = Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config';
    return '$config/$_autostartDir';
  }

  Future<void> _load() async {
    final dir = Directory(_dir);
    final found = <StartupEntry>[];
    if (dir.existsSync()) {
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.desktop')) continue;
        final text = f.readAsStringSync();
        String name = f.uri.pathSegments.last.replaceAll('.desktop', '');
        String command = '';
        bool enabled = true;
        var inDesktopEntry = false;
        for (final line in text.split('\n')) {
          final t = line.trim();
          if (t == '[Desktop Entry]') {
            inDesktopEntry = true;
            continue;
          }
          if (t.startsWith('[') && t.endsWith(']')) {
            inDesktopEntry = false;
            continue;
          }
          if (!inDesktopEntry) continue;
          if (t.startsWith('Name=')) name = t.substring(5);
          if (t.startsWith('Exec=')) command = t.substring(5);
          if (t.startsWith('Hidden=')) enabled = t.substring(7).toLowerCase() != 'true';
        }
        found.add(StartupEntry(name, command, enabled: enabled));
      }
    }
    found.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!mounted) return;
    setState(() => _entries.addAll(found));
  }

  void _add() {
    final name = _nameC.text.trim();
    final command = _cmdC.text.trim();
    if (name.isEmpty || command.isEmpty) {
      setState(() => _error = 'Give it a name and a command.');
      return;
    }
    setState(() {
      _entries.add(StartupEntry(name, command));
      _nameC.clear();
      _cmdC.clear();
      _error = null;
    });
  }

  Future<void> _save() async {
    final dir = Directory(_dir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    try {
      if (dir.existsSync()) {
        for (final f in dir.listSync().whereType<File>()) {
          if (f.path.endsWith('.desktop')) f.deleteSync();
        }
      }
      for (final e in _entries) {
        final safe = e.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '-');
        final file = File('$_dir/$safe.desktop');
        await file.writeAsString('''[Desktop Entry]
Type=Application
Name=${e.name}
Exec=${e.command}
Hidden=${e.enabled ? 'false' : 'true'}
X-GNOME-Autostart-enabled=${e.enabled ? 'true' : 'false'}
''');
      }
      setState(() {
        _error = null;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = "Couldn't write autostart entries: $e";
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return SettingsPage(
      title: 'Startup apps',
      sub: 'What starts when you log in. Entries live in ~/.config/autostart/.',
      error: _error,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Startup apps', palette: p),
          if (_entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('None yet.', style: TextStyle(color: p.dimText)),
            ),
          for (final e in _entries) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                palette: p,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            e.name,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text),
                          ),
                          Text(
                            e.command,
                            style: TextStyle(fontSize: 12, color: p.dimText),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    SettingToggle(
                      value: e.enabled,
                      onChanged: (_) => setState(() => e.enabled = !e.enabled),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          SectionLabel('Add one', palette: p),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _nameC,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'e.g. Steam',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  width: 300,
                  child: TextField(
                    controller: _cmdC,
                    decoration: const InputDecoration(
                      labelText: 'Command',
                      hintText: 'steam',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PillButton(
                palette: p,
                label: 'Add',
                onTap: _add,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ApplyButton(
                label: 'Apply',
                onTap: () {
                  setState(() => _busy = true);
                  _save();
                },
                busy: _busy,
              ),
              const SizedBox(width: 8),
              Text(
                'Hidden apps still ship on the ISO; they just don’t start.',
                style: TextStyle(fontSize: 12, color: p.dimText),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
