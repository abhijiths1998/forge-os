// Network & VPN page: open nm-connection-editor (the packaged tool Forge OS
// ships for Wi-Fi, VPN and advanced settings). Forge Settings itself doesn't
// reimplement a network manager — Hyprland has no settings app of its own,
// and nm-connection-editor is the right tool.
import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../main.dart';

class NetworkPage extends StatelessWidget {
  const NetworkPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return SettingsPage(
      title: 'Network & VPN',
      sub: 'Wi-Fi, Ethernet and VPN. Opens nm-connection-editor (installed).',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Connections', palette: p),
          Text(
            'nm-connection-editor lets you add, edit and remove connections: '
                'Wi-Fi networks, Ethernet, VPN (OpenVPN, OpenConnect, vpnc, '
                'WireGuard), and 802.1X. It also handles secrets (passwords, '
                'keys) through NetworkManager’s secret agent.',
            style: TextStyle(fontSize: 13, color: p.text),
          ),
          const SizedBox(height: 10),
          OpenEditorButton(
            label: 'Open nm-connection-editor',
            command: const ['nm-connection-editor'],
          ),
          const SizedBox(height: 20),
          SectionLabel('Quick toggles', palette: p),
          Text(
            '• Wi-Fi on/off and connect/disconnect live in the Control Center '
                '(Super+A) and in the bar’s Wi-Fi popup.\n'
            '• Bluetooth on/off and paired devices live in the Control Center '
                'and Forge Settings’ Bluetooth page.\n'
            '• VPN and 802.1X prompts use network-manager-applet’s secret '
                'agent (its tray icon is filtered out of the bar).',
            style: TextStyle(fontSize: 12.5, color: p.dimText),
          ),
        ],
      ),
    );
  }
}
