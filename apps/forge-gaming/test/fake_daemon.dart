// A stand-in for forge-gamed: canned results per method, recorded calls,
// and events pushed by the test.
import 'dart:async';

import 'package:forge_gaming/src/daemon.dart';

class FakeDaemon implements DaemonApi {
  FakeDaemon([Map<String, Object? Function(Map<String, Object?>? params)>? handlers])
      : handlers = handlers ?? {};

  final Map<String, Object? Function(Map<String, Object?>? params)> handlers;
  final calls = <(String, Map<String, Object?>?)>[];
  final _events = StreamController<DaemonEvent>.broadcast(sync: true);
  final _connection = StreamController<bool>.broadcast();

  @override
  Stream<DaemonEvent> get events => _events.stream;
  @override
  bool connected = true;
  @override
  Stream<bool> get connection => _connection.stream;

  void reconnect() => _connection.add(true);

  void emit(String name, [Map<String, Object?> data = const {}]) => _events.add(DaemonEvent(name, data));

  @override
  Future<Object?> call(String method, [Map<String, Object?>? params]) async {
    calls.add((method, params));
    final h = handlers[method];
    if (h == null) return <String, Object?>{};
    return h(params);
  }
}

Map<String, Object?> gameJson(String id, String title,
        {String source = 'local', bool favorite = false, bool hidden = false, int? lastPlayed, bool running = false}) =>
    {
      'id': id,
      'source': source,
      'title': title,
      'cover': null,
      'hero': null,
      'installed': true,
      'running': running,
      'playtimeMinutes': 0,
      'lastPlayed': lastPlayed,
      'favorite': favorite,
      'hidden': hidden,
      'settings': null,
    };
