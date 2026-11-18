// Adding one of your own games, or changing its settings: the program,
// how it runs (Linux, or Windows through Proton/Wine), and the extras
// (GameMode, MangoHud, gamescope, environment).
import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../models.dart';
import '../pad.dart';
import '../store.dart';
import '../widgets/glass.dart';
import '../widgets/osk.dart';
import '../window.dart';
import 'file_browser.dart';

/// "KEY=VALUE" lines to a map; blank lines and lines without '=' are skipped.
Map<String, String> parseEnv(String text) {
  final out = <String, String>{};
  for (final line in text.split('\n')) {
    final i = line.indexOf('=');
    if (i <= 0) continue;
    final k = line.substring(0, i).trim();
    if (k.isEmpty) continue;
    out[k] = line.substring(i + 1).trim();
  }
  return out;
}

String formatEnv(Map<String, String> env) => env.entries.map((e) => '${e.key}=${e.value}').join('\n');

/// A title from an executable path: "/g/Hollow_Knight/hollow-knight.x86_64" → "Hollow Knight".
String titleFromExe(String path) {
  final parts = path.split('/').where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return '';
  var name = parts.last.replaceAll(RegExp(r'\.(exe|x86_64|x86|sh|AppImage|bin)$', caseSensitive: false), '');
  // Generic launcher names say less than the folder they're in.
  if (parts.length > 1 && RegExp(r'^(game|launcher|start|run|play|setup)$', caseSensitive: false).hasMatch(name)) {
    name = parts[parts.length - 2];
  }
  name = name.replaceAll(RegExp(r'[_\-.]+'), ' ').trim();
  return name.split(' ').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.store, required this.palette, this.game});

  final GamingStore store;
  final ForgePalette palette;

  /// The game to edit; null to add a new one.
  final Game? game;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final GameSettings? _s = widget.game?.settings;
  late final _title = TextEditingController(text: widget.game?.title ?? '');
  late final _exe = TextEditingController(text: _s?.exe ?? '');
  late final _args = TextEditingController(text: _s?.args ?? '');
  late final _workdir = TextEditingController(text: _s?.workdir ?? '');
  late final _cover = TextEditingController(text: widget.game?.cover ?? '');
  late final _env = TextEditingController(text: formatEnv(_s?.env ?? const {}));
  late final _gsWidth = TextEditingController(text: '${_s?.gamescope.width ?? 1920}');
  late final _gsHeight = TextEditingController(text: '${_s?.gamescope.height ?? 1080}');
  late final _gsFps = TextEditingController(text: '${_s?.gamescope.fps ?? 0}');
  late String? _runner = _s?.runner;
  late bool _gamemode = _s?.gamemode ?? true;
  late bool _mangohud = _s?.mangohud ?? false;
  late bool _gamescope = _s?.gamescope.enabled ?? false;
  late bool _gsFull = _s?.gamescope.fullscreen ?? true;
  bool _saving = false;

  ForgePalette get p => widget.palette;
  GamingStore get store => widget.store;
  bool get _isWindows => GameSettings.kindFor(_exe.text) == GameKind.windows;

  @override
  void dispose() {
    for (final c in [_title, _exe, _args, _workdir, _cover, _env, _gsWidth, _gsHeight, _gsFps]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _browseExe() async {
    final path = await pickFile(context,
        palette: p,
        start: _exe.text.isEmpty ? null : _exe.text,
        title: 'Choose the game\'s program',
        filter: (f) => RegExp(r'(\.(exe|sh|x86_64|x86|AppImage|bin|bat)$)|(^[^.]+$)', caseSensitive: false)
            .hasMatch(f.split('/').last));
    if (path == null) return;
    setState(() {
      _exe.text = path;
      if (_title.text.trim().isEmpty) _title.text = titleFromExe(path);
    });
  }

  Future<void> _browseCover() async {
    final path = await pickFile(context,
        palette: p,
        start: _cover.text.isEmpty ? (_exe.text.isEmpty ? null : _exe.text) : _cover.text,
        title: 'Choose a cover picture',
        filter: (f) => RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false).hasMatch(f));
    if (path != null) setState(() => _cover.text = path);
  }

  int _int(TextEditingController c, int d) => int.tryParse(c.text.trim()) ?? d;

  Future<void> _save() async {
    final exe = _exe.text.trim();
    final title = _title.text.trim().isEmpty ? titleFromExe(exe) : _title.text.trim();
    if (exe.isEmpty || title.isEmpty) return;
    setState(() => _saving = true);
    final settings = GameSettings(
      kind: GameSettings.kindFor(exe),
      exe: exe,
      args: _args.text.trim(),
      workdir: _workdir.text.trim().isEmpty ? null : _workdir.text.trim(),
      runner: _isWindows ? _runner : null,
      prefix: _s?.prefix,
      env: parseEnv(_env.text),
      gamemode: _gamemode,
      mangohud: _mangohud,
      gamescope: Gamescope(
        enabled: _gamescope,
        width: _int(_gsWidth, 1920),
        height: _int(_gsHeight, 1080),
        fps: _int(_gsFps, 0),
        fullscreen: _gsFull,
      ),
    );
    final cover = _cover.text.trim().isEmpty ? null : _cover.text.trim();
    final g = widget.game;
    if (g == null) {
      await store.addGame(title, settings, cover: cover);
    } else {
      await store.editGame(g, title, settings, cover: cover);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    final g = widget.game;
    if (g == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Glass(
            palette: p,
            strength: 1.6,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Remove ${g.title}?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text)),
              const SizedBox(height: 8),
              Text('It leaves the library. The game\'s files and its prefix stay where they are.',
                  style: TextStyle(color: p.dimText)),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                GlassButton(palette: p, label: 'Keep', autofocus: true, onPressed: () => Navigator.pop(context, false)),
                const SizedBox(width: 10),
                GlassButton(palette: p, label: 'Remove', danger: true, filled: true, onPressed: () => Navigator.pop(context, true)),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (ok != true) return;
    await store.removeGame(g);
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => PadShortcuts(
        bindings: padBindings({PadButton.start: _save}),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(fit: StackFit.expand, children: [
            Backdrop(palette: p, game: widget.game),
            Column(children: [
              TitleStrip(palette: p),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
                      children: [
                        Text(widget.game == null ? 'Add a game' : '${widget.game!.title} settings',
                            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: p.text)),
                        const SizedBox(height: 18),
                        _section('Game', [
                          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Expanded(
                              child: GlassField(
                                palette: p,
                                controller: _exe,
                                label: 'Program',
                                hint: '/path/to/game.x86_64 or Game.exe',
                                autofocus: widget.game == null,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 10),
                            GlassButton(palette: p, icon: Icons.folder_open_rounded, label: 'Browse', onPressed: _browseExe),
                          ]),
                          const SizedBox(height: 14),
                          GlassField(palette: p, controller: _title, label: 'Name', hint: 'Shown in the library'),
                          const SizedBox(height: 14),
                          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Expanded(
                              child: GlassField(
                                  palette: p, controller: _cover, label: 'Cover picture (optional)', hint: 'Portrait, 2:3'),
                            ),
                            const SizedBox(width: 10),
                            GlassButton(palette: p, icon: Icons.image_rounded, label: 'Browse', onPressed: _browseCover),
                          ]),
                        ]),
                        if (_exe.text.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 10, left: 4),
                            child: Text(
                              _isWindows ? 'A Windows game: runs with Proton or Wine.' : 'A Linux game: runs as it is.',
                              style: TextStyle(color: p.dimText, fontSize: 12.5),
                            ),
                          ),
                        if (_isWindows) _section('Proton / Wine', [_runnerPicker()]),
                        _section('Launch', [
                          GlassField(palette: p, controller: _args, label: 'Arguments', hint: 'e.g. -dx11 --skip-intro'),
                          const SizedBox(height: 14),
                          GlassField(
                              palette: p,
                              controller: _workdir,
                              label: 'Working folder (optional)',
                              hint: 'Defaults to the program\'s folder'),
                          const SizedBox(height: 14),
                          GlassField(
                              palette: p,
                              controller: _env,
                              label: 'Environment (one KEY=VALUE per line)',
                              hint: 'DXVK_HUD=fps',
                              maxLines: 4),
                        ]),
                        _section('Extras', [
                          GlassToggle(
                            palette: p,
                            label: 'GameMode',
                            subtitle: 'Let gamemoded raise CPU and GPU performance while playing',
                            value: _gamemode,
                            onChanged: (v) => setState(() => _gamemode = v),
                          ),
                          const SizedBox(height: 8),
                          GlassToggle(
                            palette: p,
                            label: 'MangoHud',
                            subtitle: 'Frame rate, temperatures and load over the game',
                            value: _mangohud,
                            onChanged: (v) => setState(() => _mangohud = v),
                          ),
                          const SizedBox(height: 8),
                          GlassToggle(
                            palette: p,
                            label: 'gamescope',
                            subtitle: 'Run inside its own compositor: fixed resolution, frame limit, upscaling',
                            value: _gamescope,
                            onChanged: (v) => setState(() => _gamescope = v),
                          ),
                          if (_gamescope) ...[
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(child: GlassField(palette: p, controller: _gsWidth, label: 'Width')),
                              const SizedBox(width: 10),
                              Expanded(child: GlassField(palette: p, controller: _gsHeight, label: 'Height')),
                              const SizedBox(width: 10),
                              Expanded(child: GlassField(palette: p, controller: _gsFps, label: 'FPS limit (0 = none)')),
                            ]),
                            const SizedBox(height: 8),
                            GlassToggle(
                              palette: p,
                              label: 'Full screen',
                              value: _gsFull,
                              onChanged: (v) => setState(() => _gsFull = v),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 26),
                        Row(children: [
                          if (widget.game != null)
                            GlassButton(
                                palette: p, icon: Icons.delete_outline_rounded, label: 'Remove', danger: true, onPressed: _remove),
                          const Spacer(),
                          GlassButton(palette: p, label: 'Cancel', onPressed: () => Navigator.of(context).maybePop()),
                          const SizedBox(width: 10),
                          GlassButton(
                            palette: p,
                            filled: true,
                            icon: Icons.check_rounded,
                            label: widget.game == null ? 'Add to library' : 'Save',
                            onPressed: _saving || _exe.text.trim().isEmpty ? null : _save,
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: FocusTraversalGroup(
          child: Glass(
            palette: p,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title.toUpperCase(),
                  style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: p.dimText)),
              const SizedBox(height: 12),
              ...children,
            ]),
          ),
        ),
      );

  Widget _runnerPicker() {
    final runners = store.runners;
    String defaultName() {
      for (final r in runners) {
        if (r.id == store.defaultRunner) return r.name;
      }
      return runners.isEmpty ? 'none installed' : runners.first.name;
    }

    return Wrap(spacing: 10, runSpacing: 10, children: [
      GlassChip(
        palette: p,
        label: 'Default (${defaultName()})',
        selected: _runner == null,
        onSelected: () => setState(() => _runner = null),
      ),
      for (final r in runners)
        GlassChip(
          palette: p,
          icon: r.kind == 'proton' ? Icons.bolt_rounded : Icons.wine_bar_rounded,
          label: r.name,
          selected: _runner == r.id,
          onSelected: () => setState(() => _runner = r.id),
        ),
      if (_runner != null && !runners.any((r) => r.id == _runner))
        GlassChip(palette: p, label: 'Missing: $_runner', selected: true, onSelected: () {}),
    ]);
  }
}
