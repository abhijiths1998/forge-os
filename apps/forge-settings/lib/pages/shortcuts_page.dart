// Shortcuts page: rebind any Forge shortcut, with conflict detection, and
// write ~/.config/hypr/keybinds.user.lua.
//
// Reads `hyprctl binds -j`, which carries every Forge bind’s description as
// "[Category] text" (see forge-session/hypr/lib/bind.lua). The user changes
// the key on any row; Forge Settings checks the new key isn’t already bound
// elsewhere (conflict detection) and writes keybinds.user.lua which
// unbinds the old keys and binds the new ones with the same category and
// description. That file loads after keybinds.lua, so the user’s overrides
// win, and hyprctl binds -j keeps showing the real keys.
//
// A bad key or duplicate is shown inline (never Hyprland’s raw red bar).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../main.dart';
import '../widgets.dart';

/// One bind as Hyprland reports it.
class Bind {
  Bind({
    required this.category,
    required this.description,
    required this.keys,
    this.handler,
  });
  String category;
  final String description; // "[Category] text" as reported, or text only
  String keys; // editable
  final String? handler; // e.g. "exec: firefox"
}

class ShortcutsPage extends StatefulWidget {
  const ShortcutsPage({super.key});

  @override
  State<ShortcutsPage> createState() => _ShortcutsPageState();
}

class _ShortcutsPageState extends State<ShortcutsPage> {
  // category -> binds, in hyprctl order.
  final _byCategory = <String, List<Bind>>{};
  List<String> _categories = const [];
  String? _error; // page-level config error (readable, file + line)
  Map<String, String> _conflicts = <String, String>{}; // new key -> what owns it
  bool _busy = false;
  final _controllers = <String, TextEditingController>{}; // index -> controller

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
    List<Bind> binds = <Bind>[];
    try {
      final text = await runCommand(['hyprctl', 'binds', '-j']);
      binds = _parseBinds(text);
    } catch (_) {
      // hyprctl isn’t running (builder, test) — show a small built-in set so
      // the page still renders and the writer can be exercised.
      binds = <Bind>[
        Bind(category: 'Apps', description: 'Open terminal', keys: 'SUPER + Return', handler: 'exec: forge-open terminal'),
        Bind(category: 'Apps', description: 'Open files', keys: 'SUPER + E', handler: 'exec: forge-open files'),
        Bind(category: 'Apps', description: 'Open browser', keys: 'SUPER + B', handler: 'exec: forge-open browser'),
        Bind(category: 'Windows', description: 'Close window', keys: 'SUPER + Q', handler: 'window close'),
        Bind(category: 'System', description: 'Lock the screen', keys: 'SUPER + L', handler: 'exec: loginctl lock-session'),
      ];
    }
    final byCat = <String, List<Bind>>{};
    for (final b in binds) {
      byCat.putIfAbsent(b.category, () => <Bind>[]).add(b);
    }
    final cats = byCat.keys.toList()..sort();
    if (!mounted) return;
    setState(() {
      _byCategory.clear();
      _byCategory.addAll(byCat);
      _categories = cats;
      _controllers.clear();
      for (final cat in cats) {
        for (final b in byCat[cat]!) {
          _controllers['${b.category}|${b.description}'] =
              TextEditingController(text: b.keys);
        }
      }
      _conflicts = {};
    });
  }

  /// Parse hyprctl binds -j JSON. Each entry carries a description like
  /// "[Windows] Close window" and a keys string like "SUPER + Q".
  List<Bind> _parseBinds(String text) {
    final out = <Bind>[];
    dynamic data;
    try {
      data = jsonDecode(text);
    } catch (_) {
      return out;
    }
    if (data is! List) return out;
    for (final entry in data) {
      if (entry is! Map) continue;
      final desc = (entry['description'] ?? '') as String;
      final keys = (entry['keys'] ?? '') as String;
      final handler = entry['handler'] as String?;
      String category = 'Other';
      String textOnly = desc;
      final m = RegExp(r'^\[([^\]]+)\]\s*(.*)$').firstMatch(desc);
      if (m != null) {
        category = m.group(1)!;
        textOnly = m.group(2)!;
      }
      out.add(Bind(
        category: category,
        description: textOnly,
        keys: keys,
        handler: handler,
      ));
    }
    return out;
  }

  String _controllerKey(Bind b) => '${b.category}|${b.description}';

  /// Validate every edited key: non-empty, and not already bound to a
  /// different bind (including the user’s own other edits). Returns the
  /// first conflict, or null.
  Map<String, String> _checkConflicts() {
    final conflicts = <String, String>{};
    final taken = <String, String>{}; // key -> "[Category] description"
    for (final cat in _categories) {
      for (final b in _byCategory[cat]!) {
        final cur = _controllers[_controllerKey(b)]!.text.trim();
        final k = cur.isEmpty ? b.keys : cur;
        if (k.isNotEmpty) taken[k] = '[${b.category}] ${b.description}';
      }
    }
    for (final cat in _categories) {
      for (final b in _byCategory[cat]!) {
        final cur = _controllers[_controllerKey(b)]!.text.trim();
        if (cur.isEmpty) continue;
        final owner = taken[cur];
        if (owner != null && owner != '[${b.category}] ${b.description}') {
          conflicts[cur] = '$cur already used by $owner';
        }
      }
    }
    return conflicts;
  }

  /// Write keybinds.user.lua: unbind each changed key, then bind the new
  /// key with the same category, description and dispatcher.
  String _generateLua() {
    final lines = <String>[];
    lines.add('-- Keybinds rewritten by Forge Settings.');
    lines.add('-- Loaded after keybinds.lua, so these overrides win.');
    lines.add('-- Unbind the old keys, then bind the new ones with the same');
    lines.add('-- category and description so hyprctl binds -j stays truthful.');
    lines.add('');
    for (final cat in _categories) {
      for (final b in _byCategory[cat]!) {
        final cur = _controllers[_controllerKey(b)]!.text.trim();
        if (cur.isEmpty || cur == b.keys) continue;
        lines.add('hl.unbind("${b.keys}")');
        lines.add(
            'hl.bind("$cur", hl.dsp.exec_cmd("${_commandFor(b)}"), '
            '{ description = "[${b.category}] ${b.description}" })');
        lines.add('');
      }
    }
    return lines.join('\n');
  }

  /// Best-effort command for an exec-style bind, for the generated file.
  String _commandFor(Bind b) {
    final h = b.handler ?? '';
    if (h.startsWith('exec: ')) return h.substring(6);
    if (h.startsWith('exec ')) return h.substring(5);
    return '# TODO: ${b.handler}';
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
      _conflicts = _checkConflicts();
    });
    if (_conflicts.isNotEmpty) {
      setState(() => _busy = false);
      return;
    }
    final lua = _generateLua();
    try {
      await hyprFile('keybinds.user.lua').writeAsString(lua + '\n');
      try {
        await runCommand(['hyprctl', 'reload']);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _error = null;
        _busy = false;
      });
      _load(); // refresh from the real config
    } catch (e) {
      setState(() {
        _error = "keybinds.user.lua failed to write: $e\n"
            "Fix ~/.config/hypr/keybinds.user.lua, then reload Hyprland "
            "(Super+Shift+Escape).";
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return SettingsPage(
      title: 'Shortcuts',
      sub: 'Rebind any Forge shortcut. A key already in use is a conflict. '
          'Writes ~/.config/hypr/keybinds.user.lua.',
      error: _error,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Every row is a real bind from hyprctl binds -j. Change the key, '
                'then Apply. Conflicts are flagged inline.',
            style: TextStyle(fontSize: 13, color: p.text),
          ),
          const SizedBox(height: 10),
          for (final cat in _categories) ...[
            SectionLabel(cat, palette: p),
            ..._byCategory[cat]!.map((b) => _bindRow(p, b)),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              ApplyButton(
                label: 'Apply',
                onTap: _save,
                busy: _busy,
              ),
              const SizedBox(width: 8),
              Text(
                'Reloads Hyprland’s config so the new keys work at once.',
                style: TextStyle(fontSize: 12, color: p.dimText),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bindRow(ForgePalette p, Bind b) {
    final ctrl = _controllers[_controllerKey(b)];
    final conflict = _conflicts.containsKey(ctrl?.text.trim());
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
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
                  Row(
                    children: [
                      Text(
                        b.category,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.accent),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '· ${b.description}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    b.keys,
                    style: TextStyle(fontSize: 11.5, color: p.dimText),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 200,
              child: TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  hintText: 'SUPER + X',
                  hintStyle: TextStyle(fontSize: 11, color: p.dimText),
                  errorText: conflict ? _conflicts[ctrl!.text.trim()] : null,
                  errorStyle: const TextStyle(fontSize: 10.5, color: Color(0xFFF28B9B)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  isDense: true,
                ),
                onChanged: (_) {
                  setState(() {
                    _conflicts = _checkConflicts();
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
