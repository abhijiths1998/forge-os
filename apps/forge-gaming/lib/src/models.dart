// The objects forge-gamed sends and takes (docs/FORGE-GAMING.md, "Objects").
// Parsing is lenient: a missing or mistyped field gets a default rather than
// throwing, so a newer daemon does not break an older UI.

String _s(Object? v, [String d = '']) => v is String ? v : d;
String? _sn(Object? v) => v is String && v.isNotEmpty ? v : null;
int _i(Object? v, [int d = 0]) => v is num ? v.toInt() : d;
bool _b(Object? v, [bool d = false]) => v is bool ? v : d;
Map<String, Object?> _m(Object? v) => v is Map ? v.cast<String, Object?>() : const {};

enum GameSource {
  steam('Steam'),
  heroic('Heroic'),
  lutris('Lutris'),
  local('My games');

  const GameSource(this.label);
  final String label;

  static GameSource parse(Object? v) =>
      GameSource.values.firstWhere((s) => s.name == v, orElse: () => GameSource.local);
}

class Gamescope {
  const Gamescope({
    this.enabled = false,
    this.width = 1920,
    this.height = 1080,
    this.fps = 0,
    this.fullscreen = true,
  });

  factory Gamescope.fromJson(Object? json) {
    final j = _m(json);
    return Gamescope(
      enabled: _b(j['enabled']),
      width: _i(j['width'], 1920),
      height: _i(j['height'], 1080),
      fps: _i(j['fps']),
      fullscreen: _b(j['fullscreen'], true),
    );
  }

  final bool enabled;
  final int width;
  final int height;
  final int fps;
  final bool fullscreen;

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'width': width,
        'height': height,
        'fps': fps,
        'fullscreen': fullscreen,
      };

  Gamescope copyWith({bool? enabled, int? width, int? height, int? fps, bool? fullscreen}) =>
      Gamescope(
        enabled: enabled ?? this.enabled,
        width: width ?? this.width,
        height: height ?? this.height,
        fps: fps ?? this.fps,
        fullscreen: fullscreen ?? this.fullscreen,
      );
}

enum GameKind { native, windows }

class GameSettings {
  const GameSettings({
    required this.kind,
    required this.exe,
    this.args = '',
    this.workdir,
    this.runner,
    this.prefix,
    this.env = const {},
    this.gamemode = true,
    this.mangohud = false,
    this.gamescope = const Gamescope(),
  });

  factory GameSettings.fromJson(Object? json) {
    final j = _m(json);
    return GameSettings(
      kind: j['kind'] == 'windows' ? GameKind.windows : GameKind.native,
      exe: _s(j['exe']),
      args: _s(j['args']),
      workdir: _sn(j['workdir']),
      runner: _sn(j['runner']),
      prefix: _sn(j['prefix']),
      env: _m(j['env']).map((k, v) => MapEntry(k, '$v')),
      gamemode: _b(j['gamemode'], true),
      mangohud: _b(j['mangohud']),
      gamescope: Gamescope.fromJson(j['gamescope']),
    );
  }

  /// A Windows game is anything ending in .exe, .bat or .msi.
  static GameKind kindFor(String exe) =>
      RegExp(r'\.(exe|bat|msi)$', caseSensitive: false).hasMatch(exe)
          ? GameKind.windows
          : GameKind.native;

  final GameKind kind;
  final String exe;
  final String args;
  final String? workdir;
  final String? runner;
  final String? prefix;
  final Map<String, String> env;
  final bool gamemode;
  final bool mangohud;
  final Gamescope gamescope;

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'exe': exe,
        'args': args,
        'workdir': workdir,
        'runner': runner,
        'prefix': prefix,
        'env': env,
        'gamemode': gamemode,
        'mangohud': mangohud,
        'gamescope': gamescope.toJson(),
      };
}

/// The Game Hub profile: applied when the game starts, undone when it stops,
/// whichever launcher started it (docs/FORGE-GAMING.md, "Profiles").
class GameProfile {
  const GameProfile({this.thermal, this.quiet = false});

  factory GameProfile.fromJson(Object? json) {
    final j = _m(json);
    return GameProfile(thermal: _sn(j['thermal']), quiet: _b(j['quiet']));
  }

  /// A Forge Thermal profile, or null for the desktop's automatic rule.
  final String? thermal;

  /// Do not disturb while playing.
  final bool quiet;

  bool get isDefault => thermal == null && !quiet;

  Map<String, Object?> toJson() => {'thermal': thermal, 'quiet': quiet};
}

/// What the desktop offers profiles (from forged, through system.info).
class SystemInfo {
  const SystemInfo({
    this.thermalAvailable = false,
    this.thermalProfiles = const [],
    this.thermalCurrent,
    this.quietAvailable = false,
  });

  factory SystemInfo.fromJson(Object? json) {
    final j = _m(json);
    final t = _m(j['thermal']);
    final profiles = t['profiles'];
    return SystemInfo(
      thermalAvailable: _b(t['available']),
      thermalProfiles: profiles is List ? profiles.whereType<String>().toList() : const [],
      thermalCurrent: _sn(t['current']),
      quietAvailable: _b(_m(j['quiet'])['available']),
    );
  }

  final bool thermalAvailable;
  final List<String> thermalProfiles;
  final String? thermalCurrent;
  final bool quietAvailable;
}

class Game {
  const Game({
    required this.id,
    required this.source,
    required this.title,
    this.cover,
    this.hero,
    this.installed = true,
    this.running = false,
    this.playtimeMinutes = 0,
    this.lastPlayed,
    this.favorite = false,
    this.hidden = false,
    this.settings,
    this.profile = const GameProfile(),
    this.detected = false,
    this.canStop = false,
  });

  factory Game.fromJson(Object? json) {
    final j = _m(json);
    final last = j['lastPlayed'];
    return Game(
      id: _s(j['id']),
      source: GameSource.parse(j['source']),
      title: _s(j['title'], _s(j['id'])),
      cover: _sn(j['cover']),
      hero: _sn(j['hero']),
      installed: _b(j['installed'], true),
      running: _b(j['running']),
      playtimeMinutes: _i(j['playtimeMinutes']),
      lastPlayed: last is num && last > 0
          ? DateTime.fromMillisecondsSinceEpoch(last.toInt() * 1000)
          : null,
      favorite: _b(j['favorite']),
      hidden: _b(j['hidden']),
      settings: j['settings'] is Map ? GameSettings.fromJson(j['settings']) : null,
      profile: GameProfile.fromJson(j['profile']),
      detected: _b(j['detected']),
      // An older daemon has no canStop: then it could stop what it ran.
      canStop: j.containsKey('canStop') ? _b(j['canStop']) : _b(j['running']),
    );
  }

  final String id;
  final GameSource source;
  final String title;
  final String? cover;
  final String? hero;
  final bool installed;
  final bool running;
  final int playtimeMinutes;
  final DateTime? lastPlayed;
  final bool favorite;
  final bool hidden;
  final GameSettings? settings;
  final GameProfile profile;

  /// Running, found by forge-gamed's watcher rather than launched by it.
  final bool detected;

  /// forge-gamed started it and can stop it.
  final bool canStop;

  bool get isLocal => source == GameSource.local;

  /// The wide picture if there is one, else the cover.
  String? get backdrop => hero ?? cover;

  Game copyWith({bool? running, bool? detected, bool? canStop}) => Game(
        id: id,
        source: source,
        title: title,
        cover: cover,
        hero: hero,
        installed: installed,
        running: running ?? this.running,
        playtimeMinutes: playtimeMinutes,
        lastPlayed: lastPlayed,
        favorite: favorite,
        hidden: hidden,
        settings: settings,
        profile: profile,
        detected: detected ?? this.detected,
        canStop: canStop ?? this.canStop,
      );
}

class Runner {
  const Runner({
    required this.id,
    required this.name,
    required this.kind,
    required this.source,
    required this.path,
  });

  factory Runner.fromJson(Object? json) {
    final j = _m(json);
    return Runner(
      id: _s(j['id']),
      name: _s(j['name'], _s(j['id'])),
      kind: _s(j['kind'], 'wine'),
      source: _s(j['source']),
      path: _s(j['path']),
    );
  }

  final String id;
  final String name;
  final String kind; // proton | wine
  final String source; // steam | forge | lutris | system
  final String path;
}

class RunnerRelease {
  const RunnerRelease({required this.name, required this.size, required this.installed});

  factory RunnerRelease.fromJson(Object? json) {
    final j = _m(json);
    return RunnerRelease(
      name: _s(j['name']),
      size: _i(j['size']),
      installed: _b(j['installed']),
    );
  }

  final String name;
  final int size;
  final bool installed;
}

enum PadType { xbox, playstation, nintendo, generic }

class Pad {
  const Pad({required this.index, required this.name, required this.type});

  factory Pad.fromJson(Object? json) {
    final j = _m(json);
    return Pad(
      index: _i(j['index']),
      name: _s(j['name'], 'Controller'),
      type: switch (j['type']) {
        'xbox' => PadType.xbox,
        'playstation' => PadType.playstation,
        'switch' => PadType.nintendo,
        _ => PadType.generic,
      },
    );
  }

  final int index;
  final String name;
  final PadType type;
}

/// A runner download in progress (from runner.progress events).
class Download {
  const Download(this.name, this.received, this.total);
  final String name;
  final int received;
  final int total;
  double? get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : null;
}

/// "12 h 5 min", "45 min", "Never played".
String formatPlaytime(int minutes) {
  if (minutes <= 0) return 'Never played';
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// "Today", "Yesterday", "3 days ago", "12 Nov 2026".
String formatLastPlayed(DateTime? t, {DateTime? now}) {
  if (t == null) return 'Never';
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${t.day} ${months[t.month - 1]} ${t.year}';
}
