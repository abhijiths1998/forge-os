// The connection to forge-gamed: newline-delimited JSON over
// $XDG_RUNTIME_DIR/forge-gamed.sock (docs/FORGE-GAMING.md, "Protocol").
// Starts the daemon when the socket is missing and reconnects when it drops.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class DaemonError implements Exception {
  DaemonError(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

class DaemonEvent {
  const DaemonEvent(this.name, this.data);
  final String name;
  final Map<String, Object?> data;
}

/// Splits a byte stream into lines and decodes each as a JSON object.
/// Lines that are not JSON objects are skipped.
class NdjsonDecoder {
  final _buffer = BytesBuilder(copy: false);

  List<Map<String, Object?>> add(List<int> chunk) {
    final out = <Map<String, Object?>>[];
    var start = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] != 0x0A) continue;
      _buffer.add(chunk.sublist(start, i));
      start = i + 1;
      final line = utf8.decode(_buffer.takeBytes(), allowMalformed: true).trim();
      if (line.isEmpty) continue;
      try {
        final v = jsonDecode(line);
        if (v is Map) out.add(v.cast<String, Object?>());
      } on FormatException {
        // Not ours; skip.
      }
    }
    if (start < chunk.length) _buffer.add(chunk.sublist(start));
    return out;
  }
}

/// The calls the UI makes. An interface so tests can use a fake daemon.
abstract class DaemonApi {
  Stream<DaemonEvent> get events;

  /// True while connected; changes are announced on [connection].
  bool get connected;
  Stream<bool> get connection;

  Future<Object?> call(String method, [Map<String, Object?>? params]);
}

class DaemonClient implements DaemonApi {
  DaemonClient({String? socketPath, this.daemonCommand})
      : socketPath = socketPath ?? defaultSocketPath();

  static String defaultSocketPath() {
    final dir = Platform.environment['XDG_RUNTIME_DIR'] ?? '/run/user/${_uid()}';
    return '$dir/forge-gamed.sock';
  }

  static String _uid() {
    try {
      return Process.runSync('id', ['-u']).stdout.toString().trim();
    } on Object {
      return '1000';
    }
  }

  final String socketPath;

  /// How to start the daemon; defaults to $FORGE_GAMED_BIN or forge-gamed.
  final String? daemonCommand;

  Socket? _socket;
  var _nextId = 1;
  final _pending = <int, Completer<Object?>>{};
  final _events = StreamController<DaemonEvent>.broadcast();
  final _connection = StreamController<bool>.broadcast();
  bool _closed = false;
  bool _spawned = false;
  Future<void>? _connecting;
  Timer? _reconnect;
  var _backoff = 0;

  @override
  Stream<DaemonEvent> get events => _events.stream;
  @override
  Stream<bool> get connection => _connection.stream;
  @override
  bool get connected => _socket != null;

  /// Connects, starting the daemon if nobody is listening. Retries for ~5 s.
  /// Every attempt (a "Try again", a reconnect) may start the daemon once.
  Future<void> connect() => _connecting ??= _connect().whenComplete(() => _connecting = null);

  Future<void> _connect() async {
    _spawned = false;
    for (var attempt = 0; attempt < 25 && !_closed; attempt++) {
      try {
        final s = await Socket.connect(
            InternetAddress(socketPath, type: InternetAddressType.unix), 0,
            timeout: const Duration(seconds: 2));
        _attach(s);
        return;
      } on SocketException {
        if (!_spawned) {
          _spawned = true;
          await _spawnDaemon();
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    throw DaemonError('io', 'Can\'t reach forge-gamed at $socketPath');
  }

  Future<void> _spawnDaemon() async {
    final override = daemonCommand ?? Platform.environment['FORGE_GAMED_BIN'];
    if (override == null) {
      // Prefer the user service, so systemd owns (and restarts) the daemon
      // rather than this window. A daemon we start ourselves would make the
      // service's own restart find the socket taken and give up.
      try {
        final r = await Process.run('systemctl', ['--user', 'start', 'forge-gamed.service'])
            .timeout(const Duration(seconds: 5));
        if (r.exitCode == 0) return;
      } on Object {
        // No systemd, or no unit: start it directly.
      }
    }
    final cmd = override ?? 'forge-gamed';
    try {
      await Process.start(cmd, const [], mode: ProcessStartMode.detached);
    } on ProcessException {
      // Not installed; connect() reports the failure.
    }
  }

  void _attach(Socket s) {
    _socket = s;
    _backoff = 0;
    _reconnect?.cancel();
    _connection.add(true);
    // A write after the daemon died fails here (EPIPE), not in add().
    s.done.then((_) => _dropped(s), onError: (Object _) => _dropped(s));
    final decoder = NdjsonDecoder();
    s.listen(
      (chunk) {
        for (final msg in decoder.add(chunk)) {
          _dispatch(msg);
        }
      },
      onDone: () => _dropped(s),
      onError: (Object _) => _dropped(s),
      cancelOnError: true,
    );
  }

  void _dispatch(Map<String, Object?> msg) {
    final event = msg['event'];
    if (event is String) {
      final data = msg['data'];
      _events.add(DaemonEvent(event, data is Map ? data.cast<String, Object?>() : const {}));
      return;
    }
    final id = msg['id'];
    if (id is! int) return;
    final c = _pending.remove(id);
    if (c == null) return;
    final err = msg['error'];
    if (err is Map) {
      c.completeError(DaemonError('${err['code'] ?? 'internal'}', '${err['message'] ?? err}'));
    } else {
      c.complete(msg['result']);
    }
  }

  void _dropped(Socket s) {
    if (_socket != s) return;
    _socket = null;
    s.destroy();
    for (final c in _pending.values) {
      c.completeError(DaemonError('io', 'forge-gamed went away'));
    }
    _pending.clear();
    _connection.add(false);
    _scheduleReconnect();
  }

  /// Keeps trying to come back while disconnected: first after 3 s (longer
  /// than the unit's RestartSec, so systemd gets to restart it), then backing
  /// off to every 30 s.
  void _scheduleReconnect() {
    if (_closed || _socket != null || (_reconnect?.isActive ?? false)) return;
    final delay = Duration(seconds: _backoff == 0 ? 3 : (5 * _backoff).clamp(5, 30));
    _backoff++;
    _reconnect = Timer(delay, () {
      if (_closed || _socket != null) return;
      connect().catchError((Object _) => _scheduleReconnect());
    });
  }

  @override
  Future<Object?> call(String method, [Map<String, Object?>? params]) async {
    if (_socket == null) {
      try {
        await connect();
      } on Object {
        _scheduleReconnect();
        rethrow;
      }
    }
    final s = _socket;
    if (s == null) throw DaemonError('io', 'Not connected to forge-gamed');
    final id = _nextId++;
    final c = Completer<Object?>();
    _pending[id] = c;
    s.add(utf8.encode('${jsonEncode({'id': id, 'method': method, 'params': ?params})}\n'));
    return c.future.timeout(const Duration(seconds: 30), onTimeout: () {
      _pending.remove(id);
      throw DaemonError('io', '$method timed out');
    });
  }

  Future<void> close() async {
    _closed = true;
    _reconnect?.cancel();
    await _socket?.close();
    _socket = null;
  }
}
