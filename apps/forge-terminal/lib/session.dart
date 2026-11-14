// One tab: a program (the shell) on a pseudo-terminal, and the terminal
// state xterm keeps for it.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'pty.dart';

class Session extends ChangeNotifier {
  Session({
    required int scrollback,
    this.program,
    this.arguments = const [],
    this.workingDirectory,
    this.hold = false,
  })  : terminal = Terminal(maxLines: scrollback),
        controller = TerminalController();

  final Terminal terminal;
  final TerminalController controller;
  final ScrollController scroll = ScrollController();
  final FocusNode focus = FocusNode();

  final String? program;
  final List<String> arguments;
  final String? workingDirectory;

  /// Keep the tab open after the program ends (it ran from -e and --hold
  /// was given, or it failed).
  final bool hold;

  Pty? _pty;
  StreamSubscription<String>? _sub;
  Timer? _poll;

  /// What the program asked the title to be (OSC 0/2), if anything.
  String? _programTitle;

  /// The foreground program's name and the shell's directory.
  String _name = '';
  String? cwd;

  /// The program ended, with this status.
  int? exitStatus;

  /// Output arrived while the tab wasn't looked at.
  bool activity = false;

  /// The bell rang (flashes the tab).
  bool bell = false;

  /// Called when the tab should go away by itself (its program ended).
  VoidCallback? onFinished;

  bool get exited => exitStatus != null;
  bool get busy => _pty?.busy ?? false;
  String? get foregroundName => _pty?.foregroundName;

  String get title {
    if (_programTitle != null && _programTitle!.trim().isNotEmpty) return _programTitle!.trim();
    final dir = _prettyDir(cwd);
    if (_name.isEmpty) return dir ?? 'Terminal';
    final shell = program == null && _pty != null && _pty!.foreground == _pty!.pid;
    if (shell) return dir ?? _name;
    return dir == null ? _name : '$_name · $dir';
  }

  void start() {
    final pty = Pty.start(
      program: program,
      arguments: arguments,
      workingDirectory: workingDirectory,
      rows: terminal.viewHeight,
      columns: terminal.viewWidth,
    );
    _pty = pty;
    _sub = pty.output.listen((data) {
      terminal.write(data);
      if (!activity) {
        activity = true;
        notifyListeners();
      }
    });
    terminal.onOutput = pty.write;
    terminal.onResize = (w, h, pw, ph) => pty.resize(h, w, pw, ph);
    terminal.onTitleChange = (t) {
      _programTitle = t;
      notifyListeners();
    };
    terminal.onBell = () {
      bell = true;
      notifyListeners();
      Timer(const Duration(milliseconds: 600), () {
        bell = false;
        notifyListeners();
      });
    };
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    pty.exitCode.then(_ended);
  }

  void _refresh() {
    final pty = _pty;
    if (pty == null || exited) return;
    final name = pty.foregroundName ?? '';
    final dir = pty.workingDirectory;
    if (name != _name || dir != cwd) {
      _name = name;
      cwd = dir;
      notifyListeners();
    }
  }

  void _ended(int status) {
    _poll?.cancel();
    exitStatus = status;
    // A shell that ended normally, or a -e command without --hold, closes
    // its tab; anything else stays to show what happened.
    if (!hold && (status == 0 || program != null && status < 128)) {
      onFinished?.call();
    } else {
      terminal.write('\r\n\x1b[2m[${status == 0 ? 'Finished' : 'Exited with $status'}'
          ' — press Enter to close the tab]\x1b[0m');
      terminal.onOutput = (data) {
        if (data.contains('\r') || data.contains('\n')) onFinished?.call();
      };
    }
    notifyListeners();
  }

  void write(String text) => _pty?.write(text);

  void close() {
    _poll?.cancel();
    _sub?.cancel();
    _pty?.close();
  }

  @override
  void dispose() {
    close();
    scroll.dispose();
    focus.dispose();
    controller.dispose();
    super.dispose();
  }

  static String? _prettyDir(String? dir) {
    if (dir == null) return null;
    final home = Platform.environment['HOME'];
    if (home != null && dir == home) return '~';
    if (home != null && dir.startsWith('$home/')) return '~/${dir.substring(home.length + 1)}';
    return dir;
  }
}
