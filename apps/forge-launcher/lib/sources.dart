// What the launcher can find, and how results are ranked.
//
// Typing searches apps, Forge actions (theme, tiling, thermal, updates),
// power actions and a calculator all at once; files come in a moment later
// from Forge Mind (or Baloo, without it). Two prefixes switch modes: `>`
// runs a shell command in Konsole, `?` searches the web. Anything else can
// fall through to a web search, which is always the last row.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'calc.dart';
import 'native.dart';

enum Kind { app, calc, action, file, command, web }

const kindLabels = {
  Kind.app: 'App',
  Kind.calc: 'Copy',
  Kind.action: 'Forge',
  Kind.file: 'File',
  Kind.command: 'Run',
  Kind.web: 'Web',
};

class Result {
  Result({
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.appId,
    this.iconName,
    required this.score,
    required this.run,
    this.key,
  });

  final Kind kind;
  final String title;
  final String subtitle;

  /// Icon: an app's own (by desktop id), else a themed icon name.
  final String? appId;
  final String? iconName;
  final double score;
  final Future<void> Function() run;

  /// Usage key, for ranking things picked often higher.
  final String? key;
}

/// How well `query` matches `text`: whole, start, start of a word,
/// anywhere, or as a subsequence ("ffx" -> Firefox). 0 if not at all.
double matchScore(String query, String text) {
  if (text.isEmpty) return 0;
  final q = query.toLowerCase();
  final t = text.toLowerCase();
  if (t == q) return 100;
  if (t.startsWith(q)) return 90 - (t.length - q.length) * 0.1;
  if (RegExp('(^|[\\s\\-_.])${RegExp.escape(q)}').hasMatch(t)) return 75;
  if (t.contains(q)) return 55;
  var j = 0;
  for (var i = 0; i < t.length && j < q.length; i++) {
    if (t[i] == q[j]) j++;
  }
  return j == q.length && q.length >= 2 ? 30 : 0;
}

// --- Usage: picked results float up ----------------------------------------

class Usage {
  Usage() {
    try {
      final data = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
      _counts.addAll(data.map((k, v) => MapEntry(k, (v as num).toInt())));
    } catch (_) {
      // first run, or unreadable: start fresh
    }
  }

  static File get _file {
    final home = Platform.environment['HOME'] ?? '';
    final data =
        Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share';
    return File('$data/forge-launcher/usage.json');
  }

  final _counts = <String, int>{};

  int count(String key) => _counts[key] ?? 0;

  /// Up to +20 for things used often.
  double boost(String? key) =>
      key == null ? 0 : (count(key) * 4).clamp(0, 20).toDouble();

  Iterable<String> get mostUsed =>
      (_counts.keys.toList()..sort((a, b) => count(b).compareTo(count(a))));

  void record(String? key) {
    if (key == null) return;
    _counts[key] = count(key) + 1;
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(jsonEncode(_counts));
    } catch (_) {}
  }
}

// --- Running things ---------------------------------------------------------

Future<void> sh(String command) async {
  await Process.start('sh', ['-c', command], mode: ProcessStartMode.detached);
}

/// A command in a Konsole window that stays open afterwards.
Future<void> inTerminal(String command) =>
    sh('konsole --hold -e sh -c ${_quote(command)}');

Future<void> openUrl(String url) => sh('xdg-open ${_quote(url)}');

String _quote(String s) => "'${s.replaceAll("'", "'\\''")}'";

// --- Sources ----------------------------------------------------------------

class ForgeAction {
  const ForgeAction(this.title, this.subtitle, this.icon, this.command,
      {this.keywords = '', this.terminal = false});

  final String title;
  final String subtitle;
  final String icon;
  final String command;
  final String keywords;
  final bool terminal;
}

const actions = [
  ForgeAction('Dark theme', 'Switch Forge Glass to dark', 'weather-clear-night',
      'forge theme dark', keywords: 'appearance mode night'),
  ForgeAction('Light theme', 'Switch Forge Glass to light', 'weather-clear',
      'forge theme light', keywords: 'appearance mode day'),
  ForgeAction('Tiling on', 'Auto-tile windows (Polonium)', 'view-grid',
      'forge tile on', keywords: 'windows layout'),
  ForgeAction('Tiling off', 'Float windows freely', 'view-grid', 'forge tile off',
      keywords: 'windows layout'),
  ForgeAction('Update system', 'Packages and Flatpaks', 'system-software-update',
      'forge update', keywords: 'upgrade packages', terminal: true),
  ForgeAction('Thermal: Silent', 'CPU 60% · GPU 60%', 'temperature-cold',
      'forge thermal silent', keywords: 'quiet fan profile'),
  ForgeAction('Thermal: Cool', 'CPU 75% · GPU 80%', 'temperature-cold',
      'forge thermal cool', keywords: 'fan profile'),
  ForgeAction('Thermal: Balanced', 'CPU 90% · GPU 100%', 'temperature-normal',
      'forge thermal balanced', keywords: 'fan profile default'),
  ForgeAction('Thermal: Performance', 'No clock limits', 'temperature-warm',
      'forge thermal performance', keywords: 'fan profile gaming fast'),
  ForgeAction('Lock screen', '', 'system-lock-screen', 'loginctl lock-session',
      keywords: 'lock'),
  ForgeAction('Sleep', 'Suspend to RAM', 'system-suspend', 'systemctl suspend',
      keywords: 'suspend'),
  ForgeAction('Log out', '', 'system-log-out',
      'qdbus6 org.kde.Shutdown /Shutdown logout', keywords: 'logout sign out'),
  ForgeAction('Restart', '', 'system-reboot',
      'qdbus6 org.kde.Shutdown /Shutdown logoutAndReboot',
      keywords: 'reboot'),
  ForgeAction('Shut down', '', 'system-shutdown',
      'qdbus6 org.kde.Shutdown /Shutdown logoutAndShutdown',
      keywords: 'power off poweroff'),
];

class Sources {
  Sources(this.usage);

  final Usage usage;
  List<App> apps = [];

  Future<void> reloadApps() async {
    apps = await Native.apps();
  }

  Result _appResult(App app, double score) => Result(
        kind: Kind.app,
        title: app.name,
        subtitle: app.generic.isNotEmpty ? app.generic : app.comment,
        appId: app.id,
        score: score + usage.boost('app:${app.id}'),
        key: 'app:${app.id}',
        run: () => Native.launch(app.id),
      );

  /// With nothing typed: the apps used most.
  List<Result> frequent() {
    final byId = {for (final a in apps) 'app:${a.id}': a};
    return [
      for (final key in usage.mostUsed.where(byId.containsKey).take(6))
        _appResult(byId[key]!, 0),
    ];
  }

  /// Everything that answers instantly, best first, web search last.
  List<Result> search(String raw) {
    final query = raw.trim();
    if (query.isEmpty) return frequent();

    if (query.startsWith('>')) {
      final cmd = query.substring(1).trim();
      if (cmd.isEmpty) return [];
      return [
        Result(
          kind: Kind.command,
          title: cmd,
          subtitle: 'Run in Konsole',
          iconName: 'utilities-terminal',
          score: 100,
          run: () => inTerminal(cmd),
        ),
      ];
    }
    if (query.startsWith('?')) {
      final q = query.substring(1).trim();
      return q.isEmpty ? [] : [_web(q)];
    }

    final results = <Result>[];

    final value = evaluate(query);
    if (value != null) {
      final text = formatNumber(value);
      results.add(Result(
        kind: Kind.calc,
        title: '= $text',
        subtitle: query,
        iconName: 'accessories-calculator',
        score: 1000,
        run: () => Clipboard.setData(ClipboardData(text: text)),
      ));
    }

    for (final app in apps) {
      var s = matchScore(query, app.name);
      final extra = [
        matchScore(query, app.generic),
        matchScore(query, app.exec.split('/').last),
        for (final k in app.keywords) matchScore(query, k),
      ].fold<double>(0, (a, b) => a > b ? a : b);
      // Name matches first; generic name, binary and keywords a step down.
      s = s > extra * 0.7 ? s : extra * 0.7;
      if (s > 0) results.add(_appResult(app, s));
    }

    for (final a in actions) {
      final s = [
        matchScore(query, a.title),
        matchScore(query, a.command) * 0.8,
        for (final k in a.keywords.split(' ')) matchScore(query, k) * 0.7,
      ].fold<double>(0, (x, y) => x > y ? x : y);
      if (s <= 0) continue;
      final key = 'action:${a.command}';
      results.add(Result(
        kind: Kind.action,
        title: a.title,
        subtitle: a.subtitle,
        iconName: a.icon,
        score: s * 0.9 + usage.boost(key),
        key: key,
        run: () => a.terminal ? inTerminal(a.command) : sh(a.command),
      ));
    }

    final install =
        RegExp(r'^install\s+([\w@.+\-]+(\s+[\w@.+\-]+)*)$').firstMatch(query);
    if (install != null) {
      final pkgs = install.group(1)!;
      results.add(Result(
        kind: Kind.action,
        title: 'Install $pkgs',
        subtitle: 'Repos, Chaotic-AUR and AUR',
        iconName: 'system-software-install',
        score: 95,
        // Forge Store if it's installed, else `forge install` in Konsole.
        run: () => sh('if command -v forge-store >/dev/null; then '
            'forge-store --search ${_quote(pkgs)}; else '
            'konsole --hold -e forge install $pkgs; fi'),
      ));
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    final top = results.take(8).toList();
    if (_looksLikeUrl(query)) {
      final url = query.contains('://') ? query : 'https://$query';
      top.insert(
          top.isEmpty || top.first.kind != Kind.calc ? 0 : 1,
          Result(
            kind: Kind.web,
            title: url,
            subtitle: 'Open in browser',
            iconName: 'internet-web-browser',
            score: 99,
            run: () => openUrl(url),
          ));
    }
    top.add(_web(query));
    return top;
  }

  Result _web(String q) => Result(
        kind: Kind.web,
        title: 'Search the web for “$q”',
        subtitle: 'DuckDuckGo',
        iconName: 'internet-web-browser',
        score: 0,
        run: () => openUrl(
            'https://duckduckgo.com/?q=${Uri.encodeQueryComponent(q)}'),
      );

  static bool _looksLikeUrl(String q) =>
      !q.contains(' ') &&
      (q.contains('://') ||
          RegExp(r'^[\w\-]+(\.[\w\-]+)*\.[a-z]{2,}(/\S*)?$').hasMatch(q));

  /// Files for a query: from Forge Mind, which understands requests like
  /// "the pdf from march", or else from Baloo (KDE's file index). `deep`
  /// asks Forge Mind to let its local model read the request too; it
  /// returns nothing when no model answered, so the first results stay.
  Future<List<Result>> files(String raw, {bool deep = false}) async {
    final query = raw.trim();
    if (query.length < 3 || '>?'.contains(query[0])) return [];
    final mind = await _mindFiles(query, deep);
    if (mind != null || deep) return mind ?? [];
    return _balooFiles(query);
  }

  /// Forge Mind's answer over D-Bus (org.forgeos.Mind.Ask), or null if it
  /// isn't there. busctl prints the reply as JSON: {"data": ["<json>"]}.
  Future<List<Result>?> _mindFiles(String query, bool deep) async {
    try {
      final r = await Process.run('busctl', [
        '--user', '--json=short', 'call', 'org.forgeos.Mind',
        '/org/forgeos/Mind', 'org.forgeos.Mind', 'Ask', 'sb', query,
        deep ? 'true' : 'false',
      ]).timeout(Duration(seconds: deep ? 10 : 2));
      if (r.exitCode != 0) return null;
      final data = jsonDecode(r.stdout as String)['data'] as List;
      final reply = jsonDecode(data.first as String) as Map<String, dynamic>;
      if (deep && reply['by'] != 'model') return [];
      final home = Platform.environment['HOME'] ?? '';
      return [
        for (final f in (reply['results'] as List).take(5))
          _fileResult(f['path'] as String, home,
              when: DateTime.fromMillisecondsSinceEpoch(
                  ((f['mtime'] as num) * 1000).round())),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<List<Result>> _balooFiles(String query) async {
    try {
      final r = await Process.run('baloosearch6', ['-l', '5', query])
          .timeout(const Duration(seconds: 2));
      if (r.exitCode != 0) return [];
      final home = Platform.environment['HOME'] ?? '';
      return [
        for (final path in (r.stdout as String)
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.startsWith('/')))
          _fileResult(path, home),
      ];
    } catch (_) {
      return [];
    }
  }

  /// A file row: its name, then its folder and (from Forge Mind) date.
  Result _fileResult(String path, String home, {DateTime? when}) {
    final dir = path.substring(0, path.lastIndexOf('/').clamp(0, path.length));
    final where =
        dir.startsWith(home) ? '~${dir.substring(home.length)}' : dir;
    return Result(
      kind: Kind.file,
      title: path.split('/').last,
      subtitle: when == null ? where : '$where · ${_date(when)}',
      iconName:
          FileSystemEntity.isDirectorySync(path) ? 'folder' : _fileIcon(path),
      score: 10,
      run: () => openUrl(path),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _date(DateTime d) {
    final day = '${d.day} ${_months[d.month - 1]}';
    return d.year == DateTime.now().year ? day : '$day ${d.year}';
  }

  static const _icons = {
    'application-pdf': ['pdf'],
    'image-x-generic': [
      'png', 'jpg', 'jpeg', 'webp', 'gif', 'heic', 'avif', 'bmp', 'svg', //
    ],
    'video-x-generic': ['mp4', 'mkv', 'webm', 'mov', 'avi'],
    'audio-x-generic': ['mp3', 'flac', 'ogg', 'opus', 'm4a', 'wav'],
    'x-office-document': ['doc', 'docx', 'odt', 'rtf'],
    'x-office-spreadsheet': ['xls', 'xlsx', 'ods', 'csv'],
    'x-office-presentation': ['ppt', 'pptx', 'odp'],
    'package-x-generic': ['zip', 'tar', 'gz', 'xz', 'zst', '7z', 'rar'],
    'application-x-cd-image': ['iso', 'img'],
    'text-x-script': [
      'sh', 'py', 'dart', 'js', 'ts', 'c', 'cpp', 'h', 'rs', 'go', //
    ],
  };

  /// A themed icon for the file's type, by extension.
  static String _fileIcon(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
    for (final e in _icons.entries) {
      if (e.value.contains(ext)) return e.key;
    }
    return 'text-x-generic';
  }
}
