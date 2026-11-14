// Mouse & touchpad page: natural scroll, tap-to-click, pointer speed and
// acceleration profile. Writes ~/.config/hypr/input.user.lua (Hyprland's
// input block), which loads after Forge's input.lua, so the user's choice
// wins.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../main.dart';
import '../widgets.dart';

class MousePage extends StatefulWidget {
  const MousePage({super.key});

  @override
  State<MousePage> createState() => _MousePageState();
}

class _MousePageState extends State<MousePage> {
  static const _defaults = {
    'natural_scroll': 'true',
    'tap_to_click': 'true',
    'disable_while_typing': 'true',
    'clickfinger_behavior': 'true',
    'scroll_factor': '0.8',
    'sensitivity': '0',
    'accel_profile': 'adaptive',
  };

  final _toggles = <String, bool>{};
  final _controllers = <String, TextEditingController>{};
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final values = <String, String>{};
    values.addAll(_defaults);
    final file = File('${hyprConfigDir}/input.user.lua');
    if (file.existsSync()) {
      final text = file.readAsStringSync();
      for (final entry in ['natural_scroll', 'tap_to_click', 'disable_while_typing',
          'clickfinger_behavior']) {
        final m = RegExp("$entry\\s*=\\s*(true|false)").firstMatch(text);
        if (m != null) values[entry] = m.group(1)!;
      }
      final m = RegExp("scroll_factor\\s*=\\s*([\\d.]+)").firstMatch(text);
      if (m != null) values['scroll_factor'] = m.group(1)!;
      final m2 = RegExp("sensitivity\\s*=\\s*([\\d.]+)").firstMatch(text);
      if (m2 != null) values['sensitivity'] = m2.group(1)!;
      final m3 = RegExp("accel_profile\\s*=\\s*'([^']*)'").firstMatch(text);
      if (m3 != null) values['accel_profile'] = m3.group(1)!;
    }
    if (!mounted) return;
    setState(() {
      for (final k in ['natural_scroll', 'tap_to_click', 'disable_while_typing',
          'clickfinger_behavior']) {
        _toggles[k] = values[k] == 'true';
      }
      for (final k in ['scroll_factor', 'sensitivity']) {
        _controllers[k] = TextEditingController(text: values[k]);
      }
      _controllers['accel_profile'] =
          TextEditingController(text: values['accel_profile']!);
    });
  }

  Future<void> _save() async {
    final natural = _toggles['natural_scroll']!;
    final tap = _toggles['tap_to_click']!;
    final typing = _toggles['disable_while_typing']!;
    final clickfinger = _toggles['clickfinger_behavior']!;
    final scroll = _controllers['scroll_factor']!.text.trim();
    final sens = _controllers['sensitivity']!.text.trim();
    final accel = _controllers['accel_profile']!.text.trim();

    if (double.tryParse(scroll) == null || double.tryParse(sens) == null ||
        !['adaptive', 'flat'].contains(accel)) {
      setState(() {
        _error = 'Scroll factor and sensitivity must be numbers; '
            'acceleration profile is adaptive or flat.';
        _busy = false;
      });
      return;
    }

    final lua = '''-- Mouse and touchpad, written by Forge Settings.
-- Loads after Forge's input.lua, so this wins.
hl.config({
    input = {
        touchpad = {
            natural_scroll = $natural,
            tap_to_click = $tap,
            disable_while_typing = $typing,
            clickfinger_behavior = $clickfinger,
            scroll_factor = $scroll,
        },
        sensitivity = $sens,
        accel_profile = '$accel',
    },
})
''';
    try {
      await hyprFile('input.user.lua').writeAsString(lua);
      setState(() {
        _error = null;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = "Couldn't write input.user.lua: $e";
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return SettingsPage(
      title: 'Mouse & touchpad',
      sub: 'Pointer behaviour. Changes write ~/.config/hypr/input.user.lua.',
      error: _error,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Touchpad', palette: p),
          SettingRow(
            label: 'Natural scroll',
            desc: 'Content follows your fingers (two fingers down = scroll).',
            control: SettingToggle(
              value: _toggles['natural_scroll'] ?? true,
              onChanged: (v) => setState(() => _toggles['natural_scroll'] = v),
            ),
          ),
          SettingRow(
            label: 'Tap to click',
            desc: 'A tap on the touchpad counts as a click.',
            control: SettingToggle(
              value: _toggles['tap_to_click'] ?? true,
              onChanged: (v) => setState(() => _toggles['tap_to_click'] = v),
            ),
          ),
          SettingRow(
            label: 'Disable while typing',
            desc: "Turn the touchpad off while you type, so your palms don't move the pointer.",
            control: SettingToggle(
              value: _toggles['disable_while_typing'] ?? true,
              onChanged: (v) => setState(() => _toggles['disable_while_typing'] = v),
            ),
          ),
          SettingRow(
            label: 'Clickfinger behavior',
            desc: 'Tap anywhere to click, rather than needing a physical button.',
            control: SettingToggle(
              value: _toggles['clickfinger_behavior'] ?? true,
              onChanged: (v) => setState(() => _toggles['clickfinger_behavior'] = v),
            ),
          ),
          SettingRow(
            label: 'Scroll factor',
            desc: 'How far two-finger scrolling moves (0.8 is the default).',
            control: SizedBox(
              width: 120,
              child: TextField(
                controller: _controllers['scroll_factor'],
                decoration: const InputDecoration(
                  hintText: '0.8',
                  hintStyle: TextStyle(fontSize: 11, color: Color(0xFF9296B5)),
                ),
              ),
            ),
          ),
          SectionLabel('Pointer', palette: p),
          SettingRow(
            label: 'Sensitivity',
            desc: 'Pointer speed multiplier (0 means no acceleration curve override).',
            control: SizedBox(
              width: 120,
              child: TextField(
                controller: _controllers['sensitivity'],
                decoration: const InputDecoration(
                  hintText: '0',
                  hintStyle: TextStyle(fontSize: 11, color: Color(0xFF9296B5)),
                ),
              ),
            ),
          ),
          SettingRow(
            label: 'Acceleration profile',
            desc: 'adaptive (the default) or flat.',
            control: SizedBox(
              width: 160,
              child: DropdownButtonFormField<String>(
                initialValue: _controllers['accel_profile']!.text.isEmpty
                    ? 'adaptive'
                    : _controllers['accel_profile']!.text,
                items: const [
                  DropdownMenuItem(value: 'adaptive', child: Text('adaptive')),
                  DropdownMenuItem(value: 'flat', child: Text('flat')),
                ],
                onChanged: (v) {
                  if (v != null) _controllers['accel_profile']!.text = v;
                },
              ),
            ),
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
                'Reload Hyprland (Super+Shift+Escape) for pointer changes to take effect.',
                style: TextStyle(fontSize: 12, color: p.dimText),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
