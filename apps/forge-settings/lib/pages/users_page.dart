// Users page: who has an account on this machine. Read-only here — creating
// or removing users goes through the installer or `useradd`/`userdel` in a
// terminal (with polkit where Forge adds it later).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../widgets.dart';

class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  static bool _isReal(String line) {
    final f = line.split(':');
    if (f.length < 7) return false;
    final uid = int.tryParse(f[2]) ?? -1;
    if (uid < 1000) return false;
    final name = f[0];
    return name != 'nobody' && name != 'nfsnobody';
  }

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    final users = <Map<String, String>>[];
    try {
      final text = File('/etc/passwd').readAsStringSync();
      for (final line in text.split('\n')) {
        if (!_isReal(line)) continue;
        final f = line.split(':');
        users.add({
          'name': f[0],
          'uid': f[2],
          'shell': f[6],
          'home': f[5],
          'gecos': f[4].split(',').first,
        });
      }
    } catch (_) {}
    users.sort((a, b) => a['name']!.toLowerCase().compareTo(b['name']!.toLowerCase()));

    return SettingsPage(
      title: 'Users',
      sub: 'Accounts on this machine. Read-only; add users with useradd.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Users', palette: p),
          if (users.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('No users found.', style: TextStyle(color: p.dimText)),
            ),
          for (final u in users) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                palette: p,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    Icon(Icons.person_rounded, size: 20, color: p.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                u['gecos']!.isNotEmpty ? u['name']! : u['name']!,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'UID ${u['uid']}',
                                style: TextStyle(fontSize: 12, color: p.dimText),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            u['shell']!,
                            style: TextStyle(fontSize: 12, color: p.dimText),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      u['home']!.isEmpty ? '–' : u['home']!,
                      style: TextStyle(fontSize: 12, color: p.dimText),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 10),
          SectionLabel('Notes', palette: p),
          Text(
            '• This page lists real accounts (UID >= 1000) from /etc/passwd.\n'
            '• Creating or removing a user needs root: open a terminal and run '
                '`useradd` / `userdel` (Forge adds a polkit action for it later).\n'
            '• A user’s own Hyprland overrides live in ~/.config/hypr/ — '
                'keybinds.user.lua, monitors.lua, input.user.lua, user.lua.',
            style: TextStyle(fontSize: 12.5, color: p.dimText),
          ),
        ],
      ),
    );
  }
}
