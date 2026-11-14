import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_arcade/games.dart';
import 'package:forge_arcade/gamepad.dart';
import 'package:forge_arcade/scores.dart';

const _json = '''
[
  {"id": "a", "name": "Alpha", "description": "First.",
   "controls": [["Space", "Jump"], ["Esc", "Pause"]],
   "needsGpu": true, "exec": "/usr/bin/a", "cover": "/c/a.png",
   "highScoreFile": "~/.local/share/doomedl/a/best", "highScoreFormat": "int"},
  {"id": "b", "name": "Beta", "controls": [], "needsGpu": false,
   "exec": "/usr/bin/b", "cover": "/c/b.png", "highScoreFile": null},
  {"name": "Broken: no id or exec"}
]
''';

void main() {
  test('parses games and skips a broken entry', () {
    final games = parseGames(_json);
    expect(games.map((g) => g.id), ['a', 'b']);
    expect(games[0].needsGpu, isTrue);
    expect(games[0].controls, [('Space', 'Jump'), ('Esc', 'Pause')]);
    expect(games[1].highScoreFile, isNull);
    expect(games[1].description, '');
  });

  test('anything but a list gives no games', () {
    expect(parseGames('{"a": 1}'), isEmpty);
  });

  test('FORGE_GAMES_JSON overrides the path', () {
    expect(gamesJsonPath({}), defaultGamesJson);
    expect(gamesJsonPath({'FORGE_GAMES_JSON': '/x.json'}), '/x.json');
  });

  test('loads from a file; a missing or bad file gives none', () async {
    final dir = Directory.systemTemp.createTempSync('arcade');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/games.json')..writeAsStringSync(_json);
    expect((await loadGames(f.path)).length, 2);
    expect(await loadGames('${dir.path}/none.json'), isEmpty);
    f.writeAsStringSync('not json');
    expect(await loadGames(f.path), isEmpty);
  });

  test('the shipped games.json in the package parses to ten games', () async {
    final games = await loadGames('../../packages/forge-games/games.json');
    expect(games.length, 10);
    expect(games.where((g) => g.needsGpu).map((g) => g.id), ['port-calder', 'hardlight']);
    expect(games.firstWhere((g) => g.id == 'port-calder').highScoreFile, isNull);
  });

  group('scores', () {
    test('int format reads the first number', () {
      expect(parseScores('1200 0.0022 1.2 0\n', 'int').single.score, 1200);
      expect(parseScores('0\n', 'int'), isEmpty);
    });

    test('table format reads NAME score level and drops zeros', () {
      final s = parseScores('AAA 5000 3\nBBB 0 0\nCCC 900 1\n', 'table');
      expect(s.map((e) => (e.name, e.score, e.level)), [('AAA', 5000, 3), ('CCC', 900, 1)]);
    });

    test('paths follow XDG_DATA_HOME', () {
      expect(expandScorePath('~/.local/share/x/best', {'HOME': '/h'}), '/h/.local/share/x/best');
      expect(expandScorePath('~/.local/share/x/best', {'HOME': '/h', 'XDG_DATA_HOME': '/d'}),
          '/d/x/best');
    });
  });

  group('gamepad', () {
    List<int> ev(int value, int type, int number) =>
        [0, 0, 0, 0, value & 0xff, (value >> 8) & 0xff, type, number];

    test('buttons and the d-pad', () {
      expect(parsePadEvent(ev(1, 1, 0)), PadAction.select);
      expect(parsePadEvent(ev(1, 1, 1)), PadAction.back);
      expect(parsePadEvent(ev(0, 1, 0)), isNull); // release
      expect(parsePadEvent(ev(-32767, 2, 6)), PadAction.left);
      expect(parsePadEvent(ev(32767, 2, 7)), PadAction.down);
      expect(parsePadEvent(ev(1000, 2, 0)), isNull); // stick at rest
      expect(parsePadEvent(ev(1, 0x81, 0)), isNull); // initial state
    });
  });
}
