import 'package:flutter_test/flutter_test.dart';
import 'package:forge_gaming/src/models.dart';

void main() {
  test('Game.fromJson reads the protocol object', () {
    final g = Game.fromJson({
      'id': 'local:abc',
      'source': 'local',
      'title': 'Foo',
      'cover': '/x/c.jpg',
      'hero': '',
      'installed': true,
      'running': true,
      'playtimeMinutes': 125,
      'lastPlayed': 1763400000,
      'favorite': true,
      'hidden': false,
      'settings': {
        'kind': 'windows',
        'exe': '/g/Foo.exe',
        'args': '-x',
        'env': {'A': 'b', 'N': 3},
        'gamemode': false,
        'gamescope': {'enabled': true, 'width': 1280, 'height': 720, 'fps': 60, 'fullscreen': false},
      },
    });
    expect(g.source, GameSource.local);
    expect(g.hero, isNull, reason: 'empty strings are no picture');
    expect(g.backdrop, '/x/c.jpg');
    expect(g.lastPlayed, DateTime.fromMillisecondsSinceEpoch(1763400000 * 1000));
    final s = g.settings!;
    expect(s.kind, GameKind.windows);
    expect(s.env, {'A': 'b', 'N': '3'});
    expect(s.gamemode, isFalse);
    expect(s.gamescope.width, 1280);
    expect(s.gamescope.fullscreen, isFalse);
    expect(GameSettings.fromJson(s.toJson()).toJson(), s.toJson());
  });

  test('Game.fromJson survives missing and mistyped fields', () {
    final g = Game.fromJson({'id': 'steam:1', 'source': 'nonsense', 'playtimeMinutes': 'lots', 'lastPlayed': 0});
    expect(g.title, 'steam:1');
    expect(g.source, GameSource.local);
    expect(g.playtimeMinutes, 0);
    expect(g.lastPlayed, isNull);
    expect(g.settings, isNull);
    expect(Game.fromJson(null).id, '');
  });

  test('Game Hub fields: profile, detected, canStop', () {
    final g = Game.fromJson({
      'id': 'steam:9',
      'running': true,
      'detected': true,
      'canStop': false,
      'profile': {'thermal': 'performance', 'quiet': true},
    });
    expect(g.profile.thermal, 'performance');
    expect(g.profile.quiet, isTrue);
    expect(g.profile.isDefault, isFalse);
    expect(g.detected, isTrue);
    expect(g.canStop, isFalse);
    expect(GameProfile.fromJson(g.profile.toJson()).toJson(), g.profile.toJson());
    final old = Game.fromJson({'id': 'local:1', 'running': true});
    expect(old.profile.isDefault, isTrue);
    expect(old.canStop, isTrue, reason: 'an older daemon could stop what it ran');
    final sys = SystemInfo.fromJson({
      'thermal': {'available': true, 'profiles': ['balanced', 3, 'cool'], 'current': 'balanced'},
      'quiet': {'available': true},
    });
    expect(sys.thermalProfiles, ['balanced', 'cool']);
    expect(sys.quietAvailable, isTrue);
    expect(SystemInfo.fromJson(null).thermalAvailable, isFalse);
  });

  test('Pad types', () {
    expect(Pad.fromJson({'index': 3, 'name': 'X', 'type': 'playstation'}).type, PadType.playstation);
    expect(Pad.fromJson({'index': 3, 'type': 'switch'}).type, PadType.nintendo);
    expect(Pad.fromJson({'type': 'weird'}).type, PadType.generic);
  });

  test('kindFor', () {
    expect(GameSettings.kindFor('/a/Game.EXE'), GameKind.windows);
    expect(GameSettings.kindFor('/a/setup.msi'), GameKind.windows);
    expect(GameSettings.kindFor('/a/game.x86_64'), GameKind.native);
    expect(GameSettings.kindFor('/a/exe'), GameKind.native);
  });

  test('formatPlaytime', () {
    expect(formatPlaytime(0), 'Never played');
    expect(formatPlaytime(45), '45 min');
    expect(formatPlaytime(120), '2 h');
    expect(formatPlaytime(725), '12 h 5 min');
  });

  test('formatLastPlayed', () {
    final now = DateTime(2026, 11, 19, 10);
    expect(formatLastPlayed(null, now: now), 'Never');
    expect(formatLastPlayed(DateTime(2026, 11, 19, 1), now: now), 'Today');
    expect(formatLastPlayed(DateTime(2026, 11, 18, 23), now: now), 'Yesterday');
    expect(formatLastPlayed(DateTime(2026, 11, 15), now: now), '4 days ago');
    expect(formatLastPlayed(DateTime(2026, 10, 2), now: now), '2 Oct 2026');
  });

  test('Download fraction', () {
    expect(const Download('x', 50, 200).fraction, 0.25);
    expect(const Download('x', 50, 0).fraction, isNull);
  });
}
