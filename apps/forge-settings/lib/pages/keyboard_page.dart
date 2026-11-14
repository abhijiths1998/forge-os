// Keyboard page: layout, variant, options, and repeat rate/delay.
// Writes ~/.config/hypr/input.user.lua (Hyprland's input block), which loads
// after Forge's input.lua, so the user's choice wins.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../main.dart';
import '../widgets.dart';

class KeyboardPage extends StatefulWidget {
  const KeyboardPage({super.key});

  @override
  State<KeyboardPage> createState() => _KeyboardPageState();
}

class _KeyboardPageState extends State<KeyboardPage> {
  static const _defaults = {
    'layout': 'us',
    'variant': '',
    'model': '',
    'options': '',
    'repeat_delay': '300',
    'repeat_rate': '30',
  };

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
      for (final entry in ['layout', 'variant', 'model', 'options']) {
        final m = RegExp("kb_$entry\\s*=\\s*'([^']*)'").firstMatch(text);
        if (m != null) values[entry] = m.group(1)!;
      }
      final m = RegExp("repeat_delay\\s*=\\s*(\\d+)").firstMatch(text);
      if (m != null) values['repeat_delay'] = m.group(1)!;
      final m2 = RegExp("repeat_rate\\s*=\\s*(\\d+)").firstMatch(text);
      if (m2 != null) values['repeat_rate'] = m2.group(1)!;
    }
    if (!mounted) return;
    setState(() {
      for (final k in values.keys) {
        _controllers[k] = TextEditingController(text: values[k]);
      }
    });
  }

  Future<void> _save() async {
    final layout = _controllers['layout']!.text.trim();
    final variant = _controllers['variant']!.text.trim();
    final model = _controllers['model']!.text.trim();
    final options = _controllers['options']!.text.trim();
    final delay = _controllers['repeat_delay']!.text.trim();
    final rate = _controllers['repeat_rate']!.text.trim();

    if (int.tryParse(delay) == null || int.tryParse(rate) == null) {
      setState(() {
        _error = 'Repeat delay and rate must be numbers (milliseconds).';
        _busy = false;
      });
      return;
    }

    final lua = '''-- Keyboard layout and repeat, written by Forge Settings.
-- Loads after Forge's input.lua, so this wins.
hl.config({
    input = {
        kb_layout = '$layout',
        kb_variant = '$variant',
        kb_model = '$model',
        kb_options = '$options',
        repeat_delay = $delay,
        repeat_rate = $rate,
    },
})
''';
    final file = hyprFile('input.user.lua');
    try {
      await file.writeAsString(lua);
      try {
        await runCommand(['hyprctl', 'keyword', 'input:kb_layout', layout]);
      } catch (_) {}
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

  Widget _field(String key, String label, String hint) {
    return TextField(
      controller: _controllers[key],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF9296B5)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return SettingsPage(
      title: 'Keyboard',
      sub: 'Layout, variant and repeat. Changes write ~/.config/hypr/input.user.lua.',
      error: _error,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingRow(
            label: 'Layout',
            desc: 'The keyboard layout Hyprland uses (e.g. us, gb, de, fr).',
            control: _field('layout', 'Layout', 'us'),
          ),
          SettingRow(
            label: 'Variant',
            desc: 'Layout variant, if any (e.g. dvorak, colemak).',
            control: _field('variant', 'Variant', 'optional'),
          ),
          SettingRow(
            label: 'Model',
            desc: 'Keyboard model, if any.',
            control: _field('model', 'Model', 'optional'),
          ),
          SettingRow(
            label: 'Options',
            desc: 'XKB options, comma-separated (e.g. caps:escape).',
            control: _field('options', 'Options', 'optional'),
          ),
          SectionLabel('Repeat', palette: p),
          SettingRow(
            label: 'Repeat delay',
            desc: 'Milliseconds before a held key starts repeating.',
            control: SizedBox(
              width: 140,
              child: _field('repeat_delay', 'Delay', '300'),
            ),
          ),
          SettingRow(
            label: 'Repeat rate',
            desc: 'Milliseconds between repeats while a key is held.',
            control: SizedBox(
              width: 140,
              child: _field('repeat_rate', 'Rate', '30'),
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
                'Reload Hyprland (Super+Shift+Escape) for layout changes to take effect.',
                style: TextStyle(fontSize: 12, color: p.dimText),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
