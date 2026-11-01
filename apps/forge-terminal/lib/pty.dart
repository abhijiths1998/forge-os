// A program on a pseudo-terminal: the C side is linux/runner/pty.cc, found
// in the executable itself. Reading blocks, so each terminal reads in its
// own isolate and sends the bytes back here.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _SpawnC = Int32 Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>,
    Pointer<Pointer<Utf8>>, Pointer<Utf8>, Int32, Int32, Pointer<Int32>);
typedef _Spawn = int Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>,
    Pointer<Pointer<Utf8>>, Pointer<Utf8>, int, int, Pointer<Int32>);

class _Native {
  _Native() : _lib = DynamicLibrary.executable();
  final DynamicLibrary _lib;

  late final spawn = _lib.lookupFunction<_SpawnC, _Spawn>('forge_pty_spawn');
  late final resize = _lib.lookupFunction<Int32 Function(Int32, Int32, Int32, Int32, Int32),
      int Function(int, int, int, int, int)>('forge_pty_resize');
  late final write = _lib.lookupFunction<Int32 Function(Int32, Pointer<Uint8>, Int32),
      int Function(int, Pointer<Uint8>, int)>('forge_pty_write');
  late final foreground =
      _lib.lookupFunction<Int32 Function(Int32), int Function(int)>('forge_pty_foreground');
  late final close = _lib.lookupFunction<Int32 Function(Int32, Int32),
      int Function(int, int)>('forge_pty_close');
}

final _native = _Native();

class Pty {
  Pty._(this.pid, this.fd, this._output, this._exit);

  final int pid;
  final int fd;
  final Stream<String> _output;
  final Future<int> _exit;
  bool _closed = false;

  /// What the program writes, decoded as UTF-8 (characters split between
  /// two reads are put back together).
  Stream<String> get output => _output;

  /// The program's exit status, once the terminal is gone.
  Future<int> get exitCode => _exit;

  /// Start [program] (the user's shell if null) on a new terminal.
  static Pty start({
    String? program,
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String> environment = const {},
    int rows = 24,
    int columns = 80,
  }) {
    final shell = program ?? _userShell();
    // A login shell's argv[0] starts with '-' only for real logins; a
    // terminal starts an interactive one, like Konsole.
    final argv = [shell, ...arguments];
    final env = {
      ...Platform.environment,
      'TERM': 'xterm-256color',
      'COLORTERM': 'truecolor',
      'TERM_PROGRAM': 'forge-terminal',
      ...environment,
    }
      // Our own launch details shouldn't leak into the shell.
      ..remove('GIO_LAUNCHED_DESKTOP_FILE')
      ..remove('GIO_LAUNCHED_DESKTOP_FILE_PID')
      ..remove('DESKTOP_STARTUP_ID')
      ..remove('XDG_ACTIVATION_TOKEN');

    return using((arena) {
      Pointer<Pointer<Utf8>> list(List<String> items) {
        final p = arena<Pointer<Utf8>>(items.length + 1);
        for (var i = 0; i < items.length; i++) {
          p[i] = items[i].toNativeUtf8(allocator: arena);
        }
        p[items.length] = nullptr;
        return p;
      }

      final fdOut = arena<Int32>();
      final pid = _native.spawn(
        shell.toNativeUtf8(allocator: arena),
        list(argv),
        list([for (final e in env.entries) '${e.key}=${e.value}']),
        (workingDirectory ?? Platform.environment['HOME'] ?? '/').toNativeUtf8(allocator: arena),
        rows,
        columns,
        fdOut,
      );
      if (pid < 0) throw ProcessException(shell, arguments, 'no pseudo-terminal');
      final fd = fdOut.value;

      final bytes = StreamController<List<int>>();
      final exit = Completer<int>();
      final port = ReceivePort();
      port.listen((message) {
        if (message is TransferableTypedData) {
          bytes.add(message.materialize().asUint8List());
        } else if (message is int) {
          bytes.close();
          if (!exit.isCompleted) exit.complete(message);
          port.close();
        }
      });
      Isolate.spawn(_reader, (port.sendPort, fd, pid));
      final text = bytes.stream.transform(const Utf8Decoder(allowMalformed: true)).asBroadcastStream();
      return Pty._(pid, fd, text, exit.future);
    });
  }

  void write(String text) => writeBytes(utf8.encode(text));

  void writeBytes(List<int> data) {
    if (_closed || data.isEmpty) return;
    using((arena) {
      final p = arena<Uint8>(data.length);
      p.asTypedList(data.length).setAll(0, data);
      _native.write(fd, p, data.length);
    });
  }

  void resize(int rows, int columns, [int width = 0, int height = 0]) {
    if (_closed || rows <= 0 || columns <= 0) return;
    _native.resize(fd, rows, columns, width, height);
  }

  /// The pid of what's in the foreground: the shell itself, or the command
  /// it's running (vim, htop...).
  int get foreground {
    if (_closed) return -1;
    final pgrp = _native.foreground(fd);
    return pgrp > 0 ? pgrp : pid;
  }

  /// The foreground program's name and its working directory.
  String? get foregroundName => _procRead('$foreground/comm')?.trim();
  String? get workingDirectory {
    for (final p in [foreground, pid]) {
      try {
        return Link('/proc/$p/cwd').resolveSymbolicLinksSync();
      } on FileSystemException {
        continue;
      }
    }
    return null;
  }

  /// Is something besides the shell running (closing would end it)?
  bool get busy => !_closed && foreground != pid;

  void close() {
    if (_closed) return;
    _closed = true;
    _native.close(fd, pid);
  }

  static String? _procRead(String path) {
    try {
      return File('/proc/$path').readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  static String _userShell() {
    final env = Platform.environment['SHELL'];
    if (env != null && env.isNotEmpty && File(env).existsSync()) return env;
    // The account's shell from passwd, then bash.
    final user = Platform.environment['USER'];
    try {
      for (final line in File('/etc/passwd').readAsLinesSync()) {
        final f = line.split(':');
        if (f.length >= 7 && f[0] == user && File(f[6]).existsSync()) return f[6];
      }
    } on FileSystemException {
      // fall through
    }
    return '/bin/bash';
  }
}

// The reader isolate: read until the terminal is gone, then reap the program
// and send its exit status.
void _reader((SendPort, int, int) args) {
  final (port, fd, pid) = args;
  final lib = DynamicLibrary.executable();
  final read = lib.lookupFunction<Int32 Function(Int32, Pointer<Uint8>, Int32),
      int Function(int, Pointer<Uint8>, int)>('forge_pty_read');
  final wait = lib.lookupFunction<Int32 Function(Int32), int Function(int)>('forge_pty_wait');
  const size = 64 * 1024;
  final buf = malloc<Uint8>(size);
  try {
    for (;;) {
      final n = read(fd, buf, size);
      if (n <= 0) break;
      port.send(TransferableTypedData.fromList([Uint8List.fromList(buf.asTypedList(n))]));
    }
  } finally {
    malloc.free(buf);
  }
  port.send(wait(pid));
}
