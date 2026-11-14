// Bluetooth page: powered on/off, paired devices, connect/forget.
// Reads and writes through bluetoothctl (BlueZ). New devices are paired in
// blueman-manager (installed) or forged’s BlueZ agent in M3.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../main.dart';

class BluetoothPage extends StatefulWidget {
  const BluetoothPage({super.key});

  @override
  State<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  bool _powered = false;
  List<Map<String, String>> _devices = <Map<String, String>>[];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _powered();
    await _devices();
  }

  /// Whether Bluetooth is powered, from `bluetoothctl show`.
  Future<void> _powered() async {
    try {
      final r = await Process.run('bluetoothctl', ['show']);
      final out = (r.stdout as String);
      final m = RegExp(r'Powered:\s*(yes|no)').firstMatch(out);
      if (!mounted) return;
      setState(() => _powered = (m?.group(1) == 'yes'));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't read Bluetooth state (bluetoothctl).");
    }
  }

  /// Paired (or discovered) devices: `bluetoothctl devices`.
  Future<void> _devices() async {
    try {
      final r = await Process.run('bluetoothctl', ['devices']);
      final out = (r.stdout as String).trim();
      final found = <Map<String, String>>[];
      if (out.isNotEmpty) {
        for (final line in out.split('\n')) {
          final m = RegExp(r'^Device\s+([0-9A-F:]{17})\s+(.*)$').firstMatch(line);
          if (m != null) {
            found.add({'address': m.group(1)!, 'name': m.group(2)!});
          }
        }
      }
      if (!mounted) return;
      setState(() => _devices = found);
    } catch (_) {}
  }

  Future<void> _setPower(bool on) async {
    try {
      await Process.run('bluetoothctl', ['power', on ? 'on' : 'off']);
      if (!mounted) return;
      setState(() {
        _powered = on;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = "Couldn't ${on ? 'turn on' : 'turn off'} Bluetooth: $e");
    }
  }

  Future<void> _connect(String address) async {
    try {
      await Process.run('bluetoothctl', ['connect', address]);
      await _devices();
    } catch (e) {
      setState(() => _error = "Couldn't connect: $e");
    }
  }

  Future<void> _remove(String address) async {
    try {
      await Process.run('bluetoothctl', ['remove', address]);
      await _devices();
    } catch (e) {
      setState(() => _error = "Couldn't remove device: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return SettingsPage(
      title: 'Bluetooth',
      sub: 'On or off, paired devices, connect and forget. Through bluetoothctl.',
      error: _error,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Bluetooth', palette: p),
          Row(
            children: [
              Text(
                'Bluetooth',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text),
              ),
              const Spacer(),
              SettingToggle(
                value: _powered,
                onChanged: (v) {
                  setState(() => _busy = true);
                  _setPower(v).then((_) => setState(() => _busy = false));
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _powered ? 'On' : 'Off',
            style: TextStyle(fontSize: 12.5, color: p.dimText),
          ),
          const SizedBox(height: 16),
          SectionLabel('Paired devices', palette: p),
          if (_devices.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No paired devices yet. Pair new ones in blueman-manager '
                    '(installed) or the Control Center.',
                style: TextStyle(color: p.dimText),
              ),
            ),
          for (final d in _devices) ...[
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
                            d['name']!,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text),
                          ),
                          Text(
                            d['address']!,
                            style: TextStyle(fontSize: 12, color: p.dimText),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    PillButton(
                      palette: p,
                      label: 'Connect',
                      onTap: () {
                        setState(() => _busy = true);
                        _connect(d['address']!).then((_) => setState(() => _busy = false));
                      },
                    ),
                    const SizedBox(width: 6),
                    PillButton(
                      palette: p,
                      label: 'Forget',
                      onTap: () {
                        setState(() => _busy = true);
                        _remove(d['address']!).then((_) => setState(() => _busy = false));
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 10),
          SectionLabel('Pairing', palette: p),
          Text(
            '• Pair a new device in blueman-manager (installed) — its wizard '
                'handles the PIN prompt.\n'
            '• Once M3’s forged BlueZ agent lands, pairing happens here too.\n'
            '• Connected devices show in the Control Center’s Bluetooth popup.',
            style: TextStyle(fontSize: 12.5, color: p.dimText),
          ),
        ],
      ),
    );
  }
}
