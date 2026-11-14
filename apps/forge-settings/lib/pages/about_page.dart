// About page: version, kernel, session, and what Forge OS is.
import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart' hide SectionLabel;

import '../widgets.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return SettingsPage(
      title: 'About',
      sub: 'What Forge OS is, and what’s running.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Forge OS', palette: p),
          SettingTile(
            icon: Icons.info_rounded,
            title: 'Version',
            value: Text(
              'Forge OS 3 (Hyprland) · dev build',
              style: TextStyle(color: p.text),
            ),
            sub: 'The desktop is Hyprland with Forge’s Quickshell shell. '
                'See forge about for the kernel and session details.',
          ),
          SettingTile(
            icon: Icons.build_rounded,
            title: 'Shell',
            value: Text(
              'forge-shell (Quickshell)',
              style: TextStyle(color: p.text),
            ),
            sub: 'Bar, Control Center, notifications, shortcuts.',
          ),
          SettingTile(
            icon: Icons.widgets_rounded,
            title: 'UI kit',
            value: Text(
              'forge_ui',
              style: TextStyle(color: p.text),
            ),
            sub: 'The theme, palette and widgets every Forge app shares.',
          ),
          const SizedBox(height: 10),
          SectionLabel('Apps', palette: p),
          SettingTile(
            icon: Icons.terminal_rounded,
            title: 'Terminal',
            value: Text('Forge Terminal', style: TextStyle(color: p.text)),
            sub: 'Super+Return opens it.',
          ),
          SettingTile(
            icon: Icons.folder_rounded,
            title: 'Files',
            value: Text('Forge Files', style: TextStyle(color: p.text)),
            sub: 'Super+E opens it.',
          ),
          SettingTile(
            icon: Icons.web_rounded,
            title: 'Browser',
            value: Text('Forge Browser', style: TextStyle(color: p.text)),
            sub: 'Super+B opens it.',
          ),
          const SizedBox(height: 10),
          SectionLabel('More', palette: p),
          SettingTile(
            icon: Icons.help_outline_rounded,
            title: 'Keyboard shortcuts',
            value: Text('Super+/', style: TextStyle(color: p.text)),
            sub: 'Every Forge shortcut, with search.',
          ),
          SettingTile(
            icon: Icons.contact_support_rounded,
            title: 'Report a problem',
            value: Text('forge-freeze', style: TextStyle(color: p.text)),
            sub: 'Log a hard GPU freeze to utils/.',
          ),
        ],
      ),
    );
  }
}
