import 'package:flutter_test/flutter_test.dart';
import 'package:forge_gaming/src/models.dart';
import 'package:forge_gaming/src/store.dart';

import 'fake_daemon.dart';

void main() {
  final games = [
    Game.fromJson(gameJson('steam:1', 'zeta', source: 'steam', lastPlayed: 100)),
    Game.fromJson(gameJson('lutris:1', 'Alpha', source: 'lutris', favorite: true)),
    Game.fromJson(gameJson('local:1', 'beta', lastPlayed: 300)),
    Game.fromJson(gameJson('local:2', 'Hidden one', hidden: true)),
  ];

  test('selectGames filters, searches and orders', () {
    List<String> ids(LibraryFilter f, [String q = '']) => selectGames(games, f, q).map((g) => g.id).toList();
    expect(ids(LibraryFilter.all), ['lutris:1', 'local:1', 'steam:1'], reason: 'favourites first, then A-Z, no hidden');
    expect(ids(LibraryFilter.recent), ['local:1', 'steam:1']);
    expect(ids(LibraryFilter.favorites), ['lutris:1']);
    expect(ids(LibraryFilter.local), ['local:1']);
    expect(ids(LibraryFilter.hidden), ['local:2']);
    expect(ids(LibraryFilter.all, 'ET'), ['local:1', 'steam:1']);
    expect(recentGames(games, count: 1).single.id, 'local:1');
  });

  test('store follows daemon events', () async {
    final d = FakeDaemon({
      'library.list': (_) => {
            'games': [gameJson('local:1', 'One'), gameJson('steam:5', 'Five', source: 'steam')]
          },
      'pads.list': (_) => {
            'pads': [
              {'index': 4, 'name': 'Specter', 'type': 'xbox'}
            ]
          },
      'runners.list': (_) => {
            'runners': [
              {'id': 'steam:GE-Proton11-12', 'name': 'GE-Proton11-12', 'kind': 'proton', 'source': 'steam', 'path': '/x'}
            ],
            'default': 'steam:GE-Proton11-12',
          },
    });
    final s = GamingStore(d);
    await s.init();
    expect(d.calls.first.$1, 'ui.register');
    expect(s.games.map((g) => g.id), ['local:1', 'steam:5']);
    expect(s.pads[4]!.name, 'Specter');
    expect(s.defaultRunner, 'steam:GE-Proton11-12');

    d.emit('game.started', {'id': 'local:1', 'tracked': true});
    expect(s.game('local:1')!.running, isTrue);
    expect(s.anyRunning, isTrue);

    d.emit('game.started', {'id': 'steam:5', 'tracked': false});
    expect(s.handedOff, contains('steam:5'));
    expect(s.game('steam:5')!.running, isFalse);

    final toasts = <String>[];
    s.toasts.listen(toasts.add);
    d.emit('game.failed', {'id': 'local:1', 'message': 'exit 1'});
    expect(s.game('local:1')!.running, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(toasts.single, 'One stopped: exit 1');

    d.emit('runner.progress', {'name': 'GE-Proton11-13', 'received': 10, 'total': 40});
    expect(s.downloads['GE-Proton11-13']!.fraction, 0.25);
    d.emit('runner.installed', {'name': 'GE-Proton11-13', 'runner': {}});
    expect(s.downloads, isEmpty);

    d.emit('pad.disconnected', {'index': 4});
    expect(s.pads, isEmpty);
    d.emit('pad.connected', {
      'pad': {'index': 7, 'name': 'DualSense', 'type': 'playstation'}
    });
    expect(s.pads[7]!.type, PadType.playstation);
  });

  test('a reconnection registers as a UI again and reloads', () async {
    final d = FakeDaemon();
    GamingStore(d);
    d.reconnect();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final methods = d.calls.map((c) => c.$1).toList();
    expect(methods.first, 'ui.register');
    expect(methods, containsAll(['library.list', 'runners.list', 'pads.list']));
  });

  test('update replaces the game with the daemon\'s answer', () async {
    final d = FakeDaemon({
      'library.list': (_) => {
            'games': [gameJson('local:1', 'One')]
          },
      'game.update': (p) => {'game': gameJson('local:1', 'One', favorite: p!['favorite'] == true)},
    });
    final s = GamingStore(d);
    await s.refresh(rescan: false);
    await s.setFavorite(s.games.single, true);
    expect(d.calls.last.$1, 'game.update');
    expect(d.calls.last.$2, {'id': 'local:1', 'favorite': true});
    expect(s.games.single.favorite, isTrue);
  });
}
