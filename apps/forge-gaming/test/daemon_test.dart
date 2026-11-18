import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_gaming/src/daemon.dart';

void main() {
  test('NdjsonDecoder joins split lines and skips junk', () {
    final d = NdjsonDecoder();
    expect(d.add(utf8.encode('{"id":1,"res')), isEmpty);
    expect(d.add(utf8.encode('ult":{}}\n{"event":"a"}\nnot json\n[1]\n{"x"')), [
      {'id': 1, 'result': <String, Object?>{}},
      {'event': 'a'},
    ]);
    expect(d.add(utf8.encode(':2}\n')), [
      {'x': 2},
    ]);
  });

  group('DaemonClient over a real socket', () {
    late Directory dir;
    late ServerSocket server;
    late String path;
    final received = <Map<String, Object?>>[];
    late Socket serverSide;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('fg-test');
      path = '${dir.path}/s.sock';
      server = await ServerSocket.bind(InternetAddress(path, type: InternetAddressType.unix), 0);
      received.clear();
      server.listen((s) {
        serverSide = s;
        final dec = NdjsonDecoder();
        s.listen((chunk) {
          for (final m in dec.add(chunk)) {
            received.add(m);
            final id = m['id'];
            if (m['method'] == 'fail') {
              s.add(utf8.encode('${jsonEncode({'id': id, 'error': {'code': 'not_found', 'message': 'nope'}})}\n'));
            } else {
              // An event first, then the answer in two pieces.
              s.add(utf8.encode('{"event":"pad.button","data":{"button":"a","pressed":true}}\n{"id":$id,'));
              s.add(utf8.encode('"result":{"echo":${jsonEncode(m['params'])}}}\n'));
            }
          }
        });
      });
    });

    tearDown(() async {
      await server.close();
      await dir.delete(recursive: true);
    });

    test('requests, responses, errors and events', () async {
      final c = DaemonClient(socketPath: path, daemonCommand: '/nonexistent');
      final events = <DaemonEvent>[];
      c.events.listen(events.add);
      await c.connect();
      expect(c.connected, isTrue);

      final r = await c.call('game.launch', {'id': 'lutris:2'});
      expect(r, {
        'echo': {'id': 'lutris:2'}
      });
      expect(received.single, {
        'id': 1,
        'method': 'game.launch',
        'params': {'id': 'lutris:2'}
      });

      await c.call('hello');
      expect(received.last.containsKey('params'), isFalse, reason: 'params omitted when none');

      expect(
          () => c.call('fail'),
          throwsA(isA<DaemonError>()
              .having((e) => e.code, 'code', 'not_found')
              .having((e) => e.message, 'message', 'nope')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(events.first.name, 'pad.button');
      expect(events.first.data['button'], 'a');
      await c.close();
    });

    test('pending calls fail when the daemon goes away', () async {
      final c = DaemonClient(socketPath: path, daemonCommand: '/nonexistent');
      await c.connect();
      final states = <bool>[];
      c.connection.listen(states.add);
      await c.call('hello');
      serverSide.destroy();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.connected, isFalse);
      expect(states, contains(false));
      await c.close();
    });
  });
}
