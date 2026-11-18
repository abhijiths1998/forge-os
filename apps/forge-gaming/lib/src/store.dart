// The app's state: what forge-gamed knows, kept in step with its events.
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'daemon.dart';
import 'models.dart';

enum LibraryFilter { all, favorites, recent, steam, heroic, lutris, local, hidden }

extension LibraryFilterLabel on LibraryFilter {
  String get label => switch (this) {
        LibraryFilter.all => 'All games',
        LibraryFilter.favorites => 'Favourites',
        LibraryFilter.recent => 'Recently played',
        LibraryFilter.steam => 'Steam',
        LibraryFilter.heroic => 'Heroic',
        LibraryFilter.lutris => 'Lutris',
        LibraryFilter.local => 'My games',
        LibraryFilter.hidden => 'Hidden',
      };
}

/// The games [filter] and [query] select, in display order: most recently
/// played first for "recent", otherwise favourites first, then by title.
List<Game> selectGames(List<Game> games, LibraryFilter filter, String query) {
  final q = query.trim().toLowerCase();
  final out = games.where((g) {
    if (filter == LibraryFilter.hidden) {
      if (!g.hidden) return false;
    } else if (g.hidden) {
      return false;
    }
    final keep = switch (filter) {
      LibraryFilter.all || LibraryFilter.hidden => true,
      LibraryFilter.favorites => g.favorite,
      LibraryFilter.recent => g.lastPlayed != null,
      LibraryFilter.steam => g.source == GameSource.steam,
      LibraryFilter.heroic => g.source == GameSource.heroic,
      LibraryFilter.lutris => g.source == GameSource.lutris,
      LibraryFilter.local => g.source == GameSource.local,
    };
    return keep && (q.isEmpty || g.title.toLowerCase().contains(q));
  }).toList();
  if (filter == LibraryFilter.recent) {
    out.sort((a, b) => b.lastPlayed!.compareTo(a.lastPlayed!));
  } else {
    out.sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
  }
  return out;
}

/// The few most recently played games, for "Continue playing".
List<Game> recentGames(List<Game> games, {int count = 8}) {
  final r = games.where((g) => g.lastPlayed != null && !g.hidden).toList()
    ..sort((a, b) => b.lastPlayed!.compareTo(a.lastPlayed!));
  return r.take(count).toList();
}

class GamingStore extends ChangeNotifier {
  GamingStore(this.daemon) {
    _subs.add(daemon.events.listen(_onEvent));
    // Every (re)connection is a new client to the daemon: register as a UI
    // again (or the Guide button would start another window) and reload.
    _subs.add(daemon.connection.listen((up) {
      notifyListeners();
      if (up) init();
    }));
  }

  final DaemonApi daemon;
  final _subs = <StreamSubscription<Object?>>[];

  List<Game> games = const [];
  List<Runner> runners = const [];
  String? defaultRunner;
  List<RunnerRelease>? releases;
  final Map<String, Download> downloads = {};
  final Map<int, Pad> pads = {};

  /// Ids whose launch was handed to another launcher (Steam, Heroic):
  /// shown as "starting" for a moment, as we can't see them run.
  final Set<String> handedOff = {};

  bool loading = true;
  String? error;

  /// The last message worth a toast (launch failures, finished downloads).
  final _toasts = StreamController<String>.broadcast();
  Stream<String> get toasts => _toasts.stream;

  bool get connected => daemon.connected;
  bool get anyRunning => games.any((g) => g.running);

  Game? game(String id) {
    for (final g in games) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// Couldn't reach the daemon at all: stop the spinner and say why.
  void markOffline(String message) {
    error = message;
    loading = false;
    notifyListeners();
  }

  Future<void> init() async {
    try {
      await daemon.call('ui.register');
    } on Object catch (e) {
      error = '$e';
    }
    await Future.wait([refresh(rescan: false), loadRunners(), _loadPads()]);
  }

  Future<void> refresh({bool rescan = true}) async {
    try {
      final r = await daemon.call(rescan ? 'library.refresh' : 'library.list');
      games = _games(r);
      error = null;
    } on Object catch (e) {
      error = '$e';
    }
    loading = false;
    notifyListeners();
  }

  static List<Game> _games(Object? result) {
    final list = result is Map ? result['games'] : null;
    return list is List ? list.map(Game.fromJson).where((g) => g.id.isNotEmpty).toList() : [];
  }

  Future<void> loadRunners() async {
    try {
      final r = await daemon.call('runners.list');
      if (r is Map) {
        final list = r['runners'];
        runners = list is List ? list.map(Runner.fromJson).toList() : [];
        defaultRunner = r['default'] is String ? r['default'] as String : null;
      }
    } on Object catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  Future<void> loadReleases() async {
    try {
      final r = await daemon.call('runners.available');
      final list = r is Map ? r['releases'] : null;
      releases = list is List ? list.map(RunnerRelease.fromJson).toList() : [];
    } on Object catch (e) {
      releases = const [];
      _toasts.add('Couldn\'t load GE-Proton releases: $e');
    }
    notifyListeners();
  }

  Future<void> _loadPads() async {
    try {
      final r = await daemon.call('pads.list');
      final list = r is Map ? r['pads'] : null;
      pads.clear();
      if (list is List) {
        for (final p in list.map(Pad.fromJson)) {
          pads[p.index] = p;
        }
      }
    } on Object {
      // No pads is fine.
    }
    notifyListeners();
  }

  // ---- actions -------------------------------------------------------------

  Future<void> launch(Game g) async {
    try {
      await daemon.call('game.launch', {'id': g.id});
    } on DaemonError catch (e) {
      _toasts.add('Couldn\'t start ${g.title}: ${e.message}');
    }
  }

  Future<void> stop(Game g) => _try(() => daemon.call('game.stop', {'id': g.id}));

  Future<void> setFavorite(Game g, bool on) =>
      _update({'id': g.id, 'favorite': on});

  Future<void> setHidden(Game g, bool on) => _update({'id': g.id, 'hidden': on});

  Future<Game?> addGame(String title, GameSettings s, {String? cover}) async {
    try {
      final r = await daemon.call('game.add', {
        'title': title,
        'cover': ?cover,
        'settings': s.toJson(),
      });
      await refresh(rescan: false);
      final g = r is Map ? Game.fromJson(r['game']) : null;
      return g == null || g.id.isEmpty ? null : g;
    } on DaemonError catch (e) {
      _toasts.add('Couldn\'t add $title: ${e.message}');
      return null;
    }
  }

  Future<void> editGame(Game g, String title, GameSettings s, {String? cover}) =>
      _update({'id': g.id, 'title': title, 'cover': cover, 'settings': s.toJson()});

  Future<void> removeGame(Game g) async {
    await _try(() => daemon.call('game.remove', {'id': g.id}));
    await refresh(rescan: false);
  }

  Future<String> log(Game g) async {
    try {
      final r = await daemon.call('game.log', {'id': g.id});
      return r is Map && r['text'] is String ? r['text'] as String : '';
    } on DaemonError catch (e) {
      return e.message;
    }
  }

  Future<void> setDefaultRunner(Runner r) async {
    await _try(() => daemon.call('runners.setDefault', {'id': r.id}));
    await loadRunners();
  }

  Future<void> installRunner(String name) async {
    downloads[name] = Download(name, 0, 0);
    notifyListeners();
    try {
      await daemon.call('runners.install', {'name': name});
    } on DaemonError catch (e) {
      downloads.remove(name);
      _toasts.add('Couldn\'t download $name: ${e.message}');
      notifyListeners();
    }
  }

  Future<void> removeRunner(Runner r) async {
    await _try(() => daemon.call('runners.remove', {'id': r.id}));
    await loadRunners();
    if (releases != null) await loadReleases();
  }

  Future<void> rumble({double strength = 0.4, int ms = 120}) async {
    try {
      await daemon.call('pad.rumble', {'strength': strength, 'ms': ms});
    } on Object {
      // A pad without rumble, or none at all.
    }
  }

  Future<void> _update(Map<String, Object?> params) async {
    try {
      final r = await daemon.call('game.update', params);
      final updated = r is Map ? Game.fromJson(r['game']) : null;
      if (updated != null && updated.id.isNotEmpty) {
        games = [for (final g in games) g.id == updated.id ? updated : g];
        notifyListeners();
      }
    } on DaemonError catch (e) {
      _toasts.add(e.message);
    }
  }

  Future<void> _try(Future<Object?> Function() f) async {
    try {
      await f();
    } on DaemonError catch (e) {
      _toasts.add(e.message);
    }
  }

  // ---- events --------------------------------------------------------------

  void _setRunning(String id, bool running) {
    games = [for (final g in games) g.id == id ? g.copyWith(running: running) : g];
  }

  void _onEvent(DaemonEvent e) {
    final d = e.data;
    final id = d['id'] is String ? d['id'] as String : '';
    switch (e.name) {
      case 'library.changed':
        refresh(rescan: false);
        return;
      case 'game.started':
        if (d['tracked'] == false) {
          handedOff.add(id);
          Timer(const Duration(seconds: 8), () {
            handedOff.remove(id);
            notifyListeners();
          });
        } else {
          _setRunning(id, true);
        }
      case 'game.stopped':
        // Play time and last played changed: fetch the game again.
        _setRunning(id, false);
        refresh(rescan: false);
      case 'game.failed':
        _setRunning(id, false);
        handedOff.remove(id);
        _toasts.add('${game(id)?.title ?? id} stopped: ${d['message'] ?? 'unknown error'}');
      case 'runner.progress':
        final name = '${d['name']}';
        downloads[name] = Download(name, _int(d['received']), _int(d['total']));
      case 'runner.installed':
        downloads.remove('${d['name']}');
        _toasts.add('${d['name']} is ready');
        loadRunners();
        if (releases != null) loadReleases();
      case 'runner.failed':
        downloads.remove('${d['name']}');
        _toasts.add('Download of ${d['name']} failed: ${d['message']}');
      case 'pad.connected':
        final p = Pad.fromJson(d['pad']);
        pads[p.index] = p;
      case 'pad.disconnected':
        pads.remove(_int(d['index']));
      default:
        return;
    }
    notifyListeners();
  }

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _toasts.close();
    super.dispose();
  }
}
