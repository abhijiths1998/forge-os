// Forge Terminal: Forge OS's terminal. Tabs in the Forge Glass look, the
// desktop's terminal colours, accent and font, all following the Theming
// Kit and light/dark as they change. xterm does the emulation; the
// pseudo-terminals are our own (pty.dart, linux/runner/pty.cc).
//
//   forge-terminal [--workdir DIR] [--hold] [-e COMMAND [ARG...]]
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:xterm/xterm.dart';

import 'find_bar.dart';
import 'session.dart';
import 'settings.dart';
import 'settings_panel.dart';
import 'tab_strip.dart';

void main(List<String> args) => runApp(TerminalApp(launch: Launch.parse(args)));

/// What the command line asked for.
class Launch {
  const Launch({this.workdir, this.command, this.hold = false});

  final String? workdir;
  final List<String>? command;
  final bool hold;

  static Launch parse(List<String> args) {
    String? workdir;
    List<String>? command;
    var hold = false;
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if ((a == '-e' || a == '-x' || a == '--') && i + 1 < args.length) {
        command = args.sublist(i + 1);
        // "-e 'ls -l'" as one word: run it through the shell.
        if (command.length == 1 && command.first.contains(' ')) {
          command = ['/bin/sh', '-c', command.first];
        }
        break;
      } else if ((a == '--workdir' || a == '-w' || a == '--working-directory') && i + 1 < args.length) {
        workdir = args[++i];
      } else if (a.startsWith('--working-directory=') || a.startsWith('--workdir=')) {
        workdir = a.substring(a.indexOf('=') + 1);
      } else if (a == '--hold' || a == '--noclose') {
        hold = true;
      } else if (!a.startsWith('-') && workdir == null && Directory(a).existsSync()) {
        // A folder handed over by a file manager.
        workdir = a;
      }
    }
    return Launch(workdir: workdir, command: command, hold: hold);
  }
}

class TerminalApp extends StatefulWidget {
  const TerminalApp({super.key, required this.launch});

  final Launch launch;

  @override
  State<TerminalApp> createState() => _TerminalAppState();
}

class _TerminalAppState extends State<TerminalApp> {
  static const _window = MethodChannel('forge/window');

  ForgePalette _palette = ForgePalette.current();
  TerminalSettings _settings = TerminalSettings.load();
  double? _zoom; // a font size from Ctrl+=/-, until Ctrl+0

  final List<Session> _sessions = [];
  int _active = 0;
  bool _finding = false;
  bool _settingsOpen = false;
  final List<StreamSubscription<FileSystemEvent>> _watches = [];
  Timer? _themePoll;
  String _shownTitle = '';

  Session get _current => _sessions[_active];
  TerminalColours get _colours => TerminalColours(_palette, _settings);
  double get _fontSize => _zoom ?? _settings.fontSize;

  @override
  void initState() {
    super.initState();
    final l = widget.launch;
    _open(
      program: l.command?.first,
      arguments: l.command?.skip(1).toList() ?? const [],
      workdir: l.workdir,
      hold: l.hold,
    );
    _watchTheme();
  }

  @override
  void dispose() {
    for (final w in _watches) {
      w.cancel();
    }
    _themePoll?.cancel();
    for (final s in _sessions) {
      s.dispose();
    }
    super.dispose();
  }

  // The theme changes under us: the Theming Kit rewrites theme.json, and
  // light/dark switches rewrite kdeglobals. Watch both folders, and look
  // every few seconds anyway (a watch can miss a rename-over).
  void _watchTheme() {
    final home = Platform.environment['HOME'] ?? '';
    final config = Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config';
    for (final dir in ['$config/forge', config]) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      _watches.add(d.watch().listen((e) {
        final name = e.path.split('/').last;
        if (name == 'theme.json' || name == 'kdeglobals') _reloadTheme();
      }));
    }
    _themePoll = Timer.periodic(const Duration(seconds: 5), (_) => _reloadTheme());
  }

  void _reloadTheme() {
    final p = ForgePalette.current();
    if (p.theme.toJson().toString() != _palette.theme.toJson().toString() || p.dark != _palette.dark) {
      setState(() => _palette = p);
    }
  }

  void _open({String? program, List<String> arguments = const [], String? workdir, bool hold = false}) {
    final s = Session(
      scrollback: _settings.scrollback,
      program: program ?? _settings.shell,
      arguments: arguments,
      workingDirectory: workdir,
      hold: hold,
    );
    s.onFinished = () => _close(s, ask: false);
    s.addListener(_sessionChanged);
    setState(() {
      _sessions.add(s);
      _active = _sessions.length - 1;
    });
    // Start the program once the view has laid out, so it begins at the
    // window's real size rather than 80x24.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      s.start();
      s.focus.requestFocus();
    });
  }

  void _sessionChanged() {
    if (!mounted) return;
    // The tab being looked at has no "new output" dot.
    if (_sessions.isNotEmpty) _current.activity = false;
    setState(() {});
    _updateWindowTitle();
  }

  void _updateWindowTitle() {
    if (_sessions.isEmpty) return;
    final t = '${_current.title} — Forge Terminal';
    if (t == _shownTitle) return;
    _shownTitle = t;
    _window.invokeMethod('setTitle', t).catchError((_) => null);
  }

  Future<void> _close(Session s, {bool ask = true}) async {
    if (ask && _settings.confirmClose && s.busy) {
      final name = s.foregroundName ?? 'A program';
      final ok = await _confirm('Close this tab?', '$name is still running in it, and closing ends it.');
      if (!ok) return;
    }
    final i = _sessions.indexOf(s);
    if (i < 0) return;
    setState(() {
      _sessions.removeAt(i);
      if (_active >= _sessions.length) _active = _sessions.length - 1;
      if (_active > i) _active--;
    });
    s.removeListener(_sessionChanged);
    s.dispose();
    if (_sessions.isEmpty) {
      exit(0);
    }
    _select(_active);
  }

  void _select(int i) {
    if (i < 0 || i >= _sessions.length) return;
    setState(() {
      _active = i;
      _current.activity = false;
    });
    _updateWindowTitle();
    WidgetsBinding.instance.addPostFrameCallback((_) => _current.focus.requestFocus());
  }

  Future<bool> _confirm(String title, String body) async {
    final p = _palette;
    final r = await showDialog<bool>(
      context: _navigator.currentContext!,
      barrierColor: Colors.black26,
      builder: (context) => Dialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(body, style: TextStyle(color: p.dimText, fontSize: 13)),
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  PillButton(palette: p, label: 'Cancel', onTap: () => Navigator.pop(context, false)),
                  const SizedBox(width: 8),
                  PillButton(palette: p, label: 'Close', filled: true, onTap: () => Navigator.pop(context, true)),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
    return r ?? false;
  }

  void _newTabHere() => _open(workdir: _sessions.isEmpty ? null : _current.cwd);

  void _newWindow() {
    final dir = _sessions.isEmpty ? null : _current.cwd;
    Process.start(Platform.resolvedExecutable, [if (dir != null) ...['--workdir', dir]],
        mode: ProcessStartMode.detached);
  }

  void _openFiles() {
    final dir = _current.cwd ?? Platform.environment['HOME'] ?? '/';
    Process.start('forge-files', [dir], mode: ProcessStartMode.detached)
        .catchError((_) => Process.start('xdg-open', [dir], mode: ProcessStartMode.detached));
  }

  Future<void> _copy() async {
    final sel = _current.controller.selection;
    if (sel == null) return;
    await Clipboard.setData(ClipboardData(text: _current.terminal.buffer.getText(sel)));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _current.terminal.paste(text);
    _current.controller.clearSelection();
  }

  void _selectAll() {
    final t = _current.terminal;
    _current.controller.setSelection(
      t.buffer.createAnchor(0, 0),
      t.buffer.createAnchor(t.viewWidth, t.buffer.height - 1),
    );
  }

  void _zoomBy(double step) => setState(() => _zoom = (_fontSize + step).clamp(6, 40));

  void _scrollPage(int direction) {
    final c = _current.scroll;
    if (!c.hasClients) return;
    final page = c.position.viewportDimension * 0.9;
    c.jumpTo((c.offset + direction * page).clamp(0, c.position.maxScrollExtent));
  }

  // The window's own keys; everything else goes to the program.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = HardwareKeyboard.instance;
    final ctrl = k.isControlPressed, shift = k.isShiftPressed, alt = k.isAltPressed;
    final key = e.logicalKey;
    bool done(void Function() f) {
      f();
      return true;
    }

    final handled = switch ((ctrl, shift, alt)) {
      (true, true, false) => switch (key) {
          LogicalKeyboardKey.keyT => done(_newTabHere),
          LogicalKeyboardKey.keyW => done(() => _close(_current)),
          LogicalKeyboardKey.keyN => done(_newWindow),
          LogicalKeyboardKey.keyC => done(_copy),
          LogicalKeyboardKey.keyV => done(_paste),
          LogicalKeyboardKey.keyA => done(_selectAll),
          LogicalKeyboardKey.keyF => done(() => setState(() => _finding = true)),
          LogicalKeyboardKey.keyE => done(_openFiles),
          LogicalKeyboardKey.keyQ => done(() => exit(0)),
          LogicalKeyboardKey.comma => done(() => setState(() => _settingsOpen = !_settingsOpen)),
          LogicalKeyboardKey.tab => done(() => _select((_active - 1) % _sessions.length)),
          LogicalKeyboardKey.pageUp => done(() => _move(-1)),
          LogicalKeyboardKey.pageDown => done(() => _move(1)),
          _ => false,
        },
      (true, false, false) => switch (key) {
          LogicalKeyboardKey.tab || LogicalKeyboardKey.pageDown =>
            done(() => _select((_active + 1) % _sessions.length)),
          LogicalKeyboardKey.pageUp => done(() => _select((_active - 1) % _sessions.length)),
          LogicalKeyboardKey.equal || LogicalKeyboardKey.add || LogicalKeyboardKey.numpadAdd =>
            done(() => _zoomBy(1)),
          LogicalKeyboardKey.minus || LogicalKeyboardKey.numpadSubtract => done(() => _zoomBy(-1)),
          LogicalKeyboardKey.digit0 || LogicalKeyboardKey.numpad0 => done(() => setState(() => _zoom = null)),
          _ => false,
        },
      (false, true, false) => switch (key) {
          LogicalKeyboardKey.insert => done(_paste),
          LogicalKeyboardKey.pageUp => done(() => _scrollPage(-1)),
          LogicalKeyboardKey.pageDown => done(() => _scrollPage(1)),
          _ => false,
        },
      (false, false, true) => _altDigit(key),
      _ => false,
    };
    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  bool _altDigit(LogicalKeyboardKey key) {
    const digits = [
      LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
    ];
    final i = digits.indexOf(key);
    if (i < 0) return false;
    _select(i == 8 ? _sessions.length - 1 : i);
    return true;
  }

  void _move(int by) {
    final to = _active + by;
    if (to < 0 || to >= _sessions.length) return;
    _reorder(_active, to > _active ? to + 1 : to);
  }

  void _reorder(int from, int to) {
    setState(() {
      final s = _sessions.removeAt(from);
      final at = to > from ? to - 1 : to;
      _sessions.insert(at, s);
      _active = at;
    });
  }

  // Ctrl+click on a link (or a path to a file) opens it.
  void _tapUp(TapUpDetails d, CellOffset cell) {
    if (!HardwareKeyboard.instance.isControlPressed) return;
    final line = _current.terminal.buffer.lines[cell.y].getText();
    final link = linkAt(line, cell.x, base: _current.cwd);
    if (link != null) Process.start('xdg-open', [link], mode: ProcessStartMode.detached);
  }

  Future<void> _contextMenu(TapDownDetails d, CellOffset cell) async {
    final p = _palette;
    final hasSelection = _current.controller.selection != null;
    final line = _current.terminal.buffer.lines[cell.y].getText();
    final link = linkAt(line, cell.x, base: _current.cwd);
    PopupMenuItem<VoidCallback> item(String label, String keys, VoidCallback f, {bool enabled = true}) =>
        PopupMenuItem(
          value: f,
          enabled: enabled,
          height: 36,
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(color: enabled ? p.text : p.dimText, fontSize: 13))),
            Text(keys, style: TextStyle(color: p.dimText, fontSize: 12)),
          ]),
        );
    final f = await showMenu<VoidCallback>(
      context: _navigator.currentContext!,
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromLTRB(d.globalPosition.dx, d.globalPosition.dy, d.globalPosition.dx, d.globalPosition.dy),
      items: [
        if (link != null) item('Open link', 'Ctrl+click', () => Process.start('xdg-open', [link])),
        if (link != null) item('Copy link', '', () => Clipboard.setData(ClipboardData(text: link))),
        item('Copy', 'Ctrl+Shift+C', _copy, enabled: hasSelection),
        item('Paste', 'Ctrl+Shift+V', _paste),
        item('Select all', 'Ctrl+Shift+A', _selectAll),
        const PopupMenuDivider(height: 8),
        item('Find…', 'Ctrl+Shift+F', () => setState(() => _finding = true)),
        item('New tab', 'Ctrl+Shift+T', _newTabHere),
        item('Open folder in Files', 'Ctrl+Shift+E', _openFiles),
        item('Settings', 'Ctrl+Shift+,', () => setState(() => _settingsOpen = true)),
      ],
    );
    f?.call();
  }

  final _navigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final p = _palette;
    final c = _colours;
    final theme = p.materialTheme();
    return MaterialApp(
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      title: 'Forge Terminal',
      color: Colors.transparent,
      theme: theme,
      home: Scaffold(
        backgroundColor: c.window,
        body: _sessions.isEmpty
            ? const SizedBox()
            : Column(children: [
                TabStrip(
                  palette: p,
                  colours: c,
                  sessions: _sessions,
                  active: _active,
                  onSelect: _select,
                  onClose: (s) => _close(s),
                  onNew: _newTabHere,
                  onReorder: _reorder,
                  onMenu: () => setState(() => _settingsOpen = !_settingsOpen),
                ),
                Expanded(child: _body(p, c)),
              ]),
      ),
    );
  }

  Widget _body(ForgePalette p, TerminalColours c) {
    final s = _current;
    return Stack(children: [
      Positioned.fill(
        child: IndexedStack(
          index: _active,
          children: [
            for (final x in _sessions)
              TerminalView(
                x.terminal,
                key: ObjectKey(x),
                controller: x.controller,
                scrollController: x.scroll,
                focusNode: x.focus,
                autofocus: x == s,
                theme: c.theme,
                backgroundOpacity: 0,
                cursorType: _settings.cursorType,
                padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                textStyle: TerminalStyle(
                  fontSize: _fontSize,
                  fontFamily: _settings.resolvedFont,
                  fontFamilyFallback: const [
                    'JetBrainsMono Nerd Font Mono',
                    'Hack',
                    'DejaVu Sans Mono',
                    'Noto Sans Mono',
                    'Noto Sans Mono CJK SC',
                    'Noto Sans CJK JP',
                    'Noto Color Emoji',
                    'monospace',
                  ],
                ),
                keyboardAppearance: c.light ? Brightness.light : Brightness.dark,
                shortcuts: const {},
                onKeyEvent: _onKey,
                onTapUp: _tapUp,
                onSecondaryTapDown: _contextMenu,
              ),
          ],
        ),
      ),
      if (_finding)
        Positioned(
          top: 8,
          right: 16,
          child: FindBar(
            key: ObjectKey(s),
            palette: p,
            session: s,
            lineHeight: _fontSize * 1.2,
            onClose: () {
              setState(() => _finding = false);
              s.focus.requestFocus();
            },
          ),
        ),
      if (_settingsOpen)
        Positioned(
          top: 8,
          right: 12,
          bottom: 12,
          child: SettingsPanel(
            palette: p,
            settings: _settings,
            onChanged: (n) {
              setState(() {
                _settings = n;
                _zoom = null;
              });
              n.save();
            },
            onClose: () {
              setState(() => _settingsOpen = false);
              s.focus.requestFocus();
            },
          ),
        ),
    ]);
  }
}

final _linkPattern = RegExp(r'''(https?|ftp|file)://[^\s<>"'`]+|(~|\.{0,2})/[^\s<>"'`:]+''');

/// The link (URL or existing path) at column [x] of [line], if any.
String? linkAt(String line, int x, {String? base}) {
  for (final m in _linkPattern.allMatches(line)) {
    if (x < m.start || x >= m.end) continue;
    var text = m.group(0)!.replaceFirst(RegExp(r'[.,;:!?)\]]+$'), '');
    if (text.contains('://')) return text;
    final home = Platform.environment['HOME'] ?? '';
    if (text.startsWith('~')) text = '$home${text.substring(1)}';
    if (!text.startsWith('/') && base != null) text = '$base/$text';
    if (FileSystemEntity.typeSync(text) != FileSystemEntityType.notFound) return text;
  }
  return null;
}
