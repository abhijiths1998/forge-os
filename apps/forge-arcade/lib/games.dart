// The games Forge Arcade lists: /usr/share/forge-games/games.json, written by
// the forge-games package. Here it is only read.
import 'dart:convert';
import 'dart:io';

const defaultGamesJson = '/usr/share/forge-games/games.json';

class Game {
  const Game({
    required this.id,
    required this.name,
    required this.description,
    required this.controls,
    required this.needsGpu,
    required this.exec,
    required this.cover,
    this.highScoreFile,
    this.highScoreFormat,
    this.lowerIsBetter = false,
  });

  factory Game.fromJson(Map<String, dynamic> j) => Game(
        id: j['id'] as String,
        name: j['name'] as String,
        description: (j['description'] as String?) ?? '',
        controls: [
          for (final c in (j['controls'] as List? ?? const []))
            if (c is List && c.length >= 2) (c[0].toString(), c[1].toString()),
        ],
        needsGpu: (j['needsGpu'] as bool?) ?? false,
        exec: j['exec'] as String,
        cover: (j['cover'] as String?) ?? '',
        highScoreFile: j['highScoreFile'] as String?,
        highScoreFormat: j['highScoreFormat'] as String?,
        lowerIsBetter: (j['lowerIsBetter'] as bool?) ?? false,
      );

  final String id;
  final String name;
  final String description;

  /// (keys, action) pairs, in README order.
  final List<(String, String)> controls;
  final bool needsGpu;
  final String exec;
  final String cover;

  /// Where the game keeps its scores; null when it keeps none.
  final String? highScoreFile;

  /// "int" (one number) or "table" (NAME score level, per line).
  final String? highScoreFormat;

  /// Orbit Golf counts strokes, so its best is the smallest.
  final bool lowerIsBetter;
}

/// Where games.json is: FORGE_GAMES_JSON, for tests and for trying a build
/// before it is installed.
String gamesJsonPath([Map<String, String>? env]) =>
    (env ?? Platform.environment)['FORGE_GAMES_JSON'] ?? defaultGamesJson;

/// Parses games.json. A game with a broken entry is skipped rather than
/// hiding the others; a file that isn't a list gives none.
List<Game> parseGames(String json) {
  final data = jsonDecode(json);
  if (data is! List) return const [];
  final games = <Game>[];
  for (final e in data) {
    try {
      games.add(Game.fromJson(e as Map<String, dynamic>));
    } catch (_) {
      // Skip it.
    }
  }
  return games;
}

/// Reads the games; an empty list when the file is missing or unreadable.
Future<List<Game>> loadGames([String? path]) async {
  try {
    return parseGames(await File(path ?? gamesJsonPath()).readAsString());
  } on FileSystemException {
    return const [];
  } on FormatException {
    return const [];
  }
}

/// Starts the game and lets go of it: it outlives the Arcade.
Future<void> launchGame(Game g) async {
  await Process.start(g.exec, const [], mode: ProcessStartMode.detached);
}
