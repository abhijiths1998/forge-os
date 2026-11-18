// High scores, read from the files the games write themselves.
import 'dart:io';

import 'games.dart';

class ScoreEntry {
  const ScoreEntry(this.score, {this.name, this.level});
  final int score;
  final String? name;
  final int? level;
}

/// "~/.local/share/x" -> the real path. SDL keeps its data under
/// XDG_DATA_HOME when it is set, so this does too.
String expandScorePath(String path, [Map<String, String>? env]) {
  final e = env ?? Platform.environment;
  final home = e['HOME'] ?? '';
  const share = '~/.local/share/';
  if (path.startsWith(share) && (e['XDG_DATA_HOME'] ?? '').isNotEmpty) {
    return '${e['XDG_DATA_HOME']}/${path.substring(share.length)}';
  }
  return path.startsWith('~/') ? '$home/${path.substring(2)}' : path;
}

/// "int": the first number in the file (Hardlight's file has more after it).
/// "table": lines of `NAME score level`. Zero scores are padding.
List<ScoreEntry> parseScores(String text, String format) {
  final entries = <ScoreEntry>[];
  if (format == 'table') {
    for (final line in text.split('\n')) {
      final f = line.trim().split(RegExp(r'\s+'));
      if (f.length < 3) continue;
      final score = int.tryParse(f[1]);
      if (score == null || score <= 0) continue;
      entries.add(ScoreEntry(score, name: f[0], level: int.tryParse(f[2])));
    }
  } else {
    final n = int.tryParse(text.trim().split(RegExp(r'\s+')).first);
    if (n != null && n > 0) entries.add(ScoreEntry(n));
  }
  return entries;
}

/// The game's scores, best first; empty when it keeps none or none exist yet.
Future<List<ScoreEntry>> loadScores(Game g, [Map<String, String>? env]) async {
  final path = g.highScoreFile;
  if (path == null) return const [];
  try {
    final text = await File(expandScorePath(path, env)).readAsString();
    return parseScores(text, g.highScoreFormat ?? 'int');
  } on FileSystemException {
    return const [];
  }
}
