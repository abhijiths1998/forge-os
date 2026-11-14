// Displays page: resolution, scale, refresh rate and VRR per output.
// Writes ~/.config/hypr/monitors.lua, which ~/.config/hypr/hyprland.lua
// loads after Forge's own defaults — so the user's monitors win. A bad
// monitor line lands Hyprland in the red bar; Forge Settings keeps the
// file syntactically simple and the config-error notifier turns a reload
// failure into a readable message with file and line.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../main.dart';
import '../widgets.dart';

class DisplaysPage extends StatefulWidget {
  const DisplaysPage({super.key});

  @override
  State<DisplaysPage> createState() => _DisplaysPageState();
}

/// One output's editable values.
class Output {
  Output(this.name);
  final String name;
  String res = '1920x1080';
  String refresh = '60';
  String scale = '1';
  bool vrr = false;
  bool enabled = true;
}

class _DisplaysPageState extends State<DisplaysPage> {
  // One output's editable values.

  final _outputs = <String, Output>{};
  List<String> _order = [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Read the current outputs from hyprctl, or fall back to one detected
  /// output when hyprctl isn't running (e.g. in the builder or a test).
  Future<List<String>> _detectOutputs() async {
    try {
      final text = await runCommand(['hyprctl', 'monitors', '-j']);
      final list = jsonDecode(text) as List;
      return list.map((m) => m['name'] as String).toList();
    } catch (_) {
      return <String>['DP-1'];
    }
  }

  Future<void> _load() async {
    final detected = await _detectOutputs();
    if (!mounted) return;
    setState(() {
      _outputs.clear();
      for (final name in detected) {
        _outputs[name] = Output(name);
      }
      _order = detected;
    });
  }

  Future<void> _save() async {
    final lines = <String>[];
    lines.add('-- Monitors, written by Forge Settings.');
    lines.add('-- Loaded by ~/.config/hypr/hyprland.lua, which runs after');
    lines.add("-- Forge's own defaults, so this wins.");
    lines.add('');
    for (final name in _order) {
      final o = _outputs[name]!;
      if (!o.enabled) {
        lines.add('monitor = $name, disable');
        lines.add('');
        continue;
      }
      lines.add(
          'monitor = $name, ${o.res}@${o.refresh}, scale ${o.scale}, '
          'transform 0, vrr ${o.vrr ? 1 : 0}');
      lines.add('');
    }
    try {
      await hyprFile('monitors.lua').writeAsString(lines.join('\n') + '\n');
      setState(() {
        _error = null;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = "Couldn't write monitors.lua: $e";
        _busy = false;
      });
    }
  }

  void _addOutput() {
    final i = _order.length + 1;
    setState(() {
      final name = 'DP-$i';
      _outputs[name] = Output(name);
      _order = [..._order, name];
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return SettingsPage(
      title: 'Displays',
      sub: 'Resolution, scale, refresh rate and VRR per output. Writes '
          '~/.config/hypr/monitors.lua.',
      error: _error,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_order.isEmpty)
            Text('No outputs found.', style: TextStyle(color: p.dimText)),
          for (final name in _order) ...[
            _outputCard(p, name),
            const SizedBox(height: 14),
          ],
          SectionLabel('Add an output', palette: p),
          Row(
            children: [
              PillButton(
                palette: p,
                label: 'Add output',
                onTap: _addOutput,
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
                'Reload Hyprland (Super+Shift+Escape) for display changes to take effect.',
                style: TextStyle(fontSize: 12, color: p.dimText),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _outputCard(ForgePalette p, String name) {
    final o = _outputs[name]!;
    return GlassCard(
      palette: p,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                name,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text),
              ),
              const Spacer(),
              SettingToggle(
                value: o.enabled,
                onChanged: (v) => setState(() => o.enabled = v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Resolution', style: TextStyle(fontSize: 12.5, color: p.dimText)),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 150,
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: '1920x1080',
                          hintStyle: TextStyle(fontSize: 11, color: Color(0xFF9296B5)),
                        ),
                        onChanged: (v) => o.res = v,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Refresh', style: TextStyle(fontSize: 12.5, color: p.dimText)),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: '60',
                          hintStyle: TextStyle(fontSize: 11, color: Color(0xFF9296B5)),
                        ),
                        onChanged: (v) => o.refresh = v,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Scale', style: TextStyle(fontSize: 12.5, color: p.dimText)),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: '1',
                          hintStyle: TextStyle(fontSize: 11, color: Color(0xFF9296B5)),
                        ),
                        onChanged: (v) => o.scale = v,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SettingToggle(
                value: o.vrr,
                onChanged: (v) => setState(() => o.vrr = v),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'VRR (variable refresh rate)',
            style: TextStyle(fontSize: 12, color: p.dimText),
          ),
        ],
      ),
    );
  }
}
