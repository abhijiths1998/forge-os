// libpamac, via the GTK runner (linux/runner/pamac_channel.cc), and the
// transaction queue: one pamac command at a time, output streamed back.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class Package {
  Package(Map<Object?, Object?> m)
      : name = m['name'] as String,
        appName = m['appName'] as String,
        appId = m['appId'] as String,
        version = m['version'] as String,
        installedVersion = m['installedVersion'] as String,
        desc = m['desc'] as String,
        repo = m['repo'] as String,
        icon = m['icon'] as String,
        launchable = m['launchable'] as String,
        downloadSize = m['downloadSize'] as int,
        installedSize = m['installedSize'] as int,
        aur = m['aur'] as bool,
        details = m;

  final String name;
  final String appName;
  final String appId;
  final String version;
  final String installedVersion;
  final String desc;
  final String repo;

  /// An AppStream icon file, if the package is an app.
  final String icon;

  /// Its desktop file id, for "Open".
  final String launchable;
  final int downloadSize;
  final int installedSize;
  final bool aur;

  /// Everything the runner sent, including detail-only fields.
  final Map<Object?, Object?> details;

  String get title => appName.isNotEmpty ? appName : name;
  bool get installed => installedVersion.isNotEmpty;
  bool get hasUpdate => installed && installedVersion != version;

  String str(String key) => (details[key] as String?) ?? '';
  List<String> list(String key) =>
      ((details[key] as List?) ?? []).cast<String>();
}

String formatSize(int bytes) {
  if (bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = bytes.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  return '${v.toStringAsFixed(v < 10 && u > 0 ? 1 : 0)} ${units[u]}';
}

class Pamac {
  static const _channel = MethodChannel('forge/store');
  static final _icons = <String, Future<Uint8List?>>{};

  static Future<List<Package>> _list(String method, [Object? args]) async {
    final list = await _channel.invokeListMethod<Object?>(method, args) ?? [];
    return [for (final m in list) Package(m as Map<Object?, Object?>)];
  }

  static Future<bool> aurEnabled() async {
    final m = await _channel.invokeMapMethod<String, Object?>('config');
    return (m?['aur'] as bool?) ?? false;
  }

  static Future<List<Package>> search(String q) =>
      _list('search', {'query': q});
  static Future<List<Package>> searchAur(String q) =>
      _list('searchAur', {'query': q});
  static Future<List<Package>> category(String name) =>
      _list('category', {'name': name});
  static Future<List<Package>> installed() => _list('installed');

  static Future<({List<Package> repos, List<Package> aur})> updates() async {
    final m = await _channel.invokeMapMethod<String, Object?>('updates') ?? {};
    List<Package> pkgs(Object? l) => [
          for (final p in (l as List?) ?? []) Package(p as Map<Object?, Object?>)
        ];
    return (repos: pkgs(m['repos']), aur: pkgs(m['aur']));
  }

  static Future<Package?> details(Package p) async {
    final m = await _channel.invokeMapMethod<Object?, Object?>(
        'details', {'name': p.name, 'aur': p.aur ? 1 : 0});
    return m == null ? null : Package(m);
  }

  static Future<Uint8List?> icon(String name, {int size = 48}) =>
      _icons['$name|$size'] ??= _channel
          .invokeMethod<Uint8List>('icon', {'name': name, 'size': size});

  static Future<void> launch(String desktopId) =>
      _channel.invokeMethod('launch', {'id': desktopId});
}

/// One queued pamac command.
class Job {
  Job(this.title, this.args);

  final String title;
  final List<String> args;
}

/// Runs jobs one after another and keeps their output for the activity
/// panel. Listeners hear about every line and every finished job.
class Transactions extends ChangeNotifier {
  Transactions() {
    Pamac._channel.setMethodCallHandler((call) async {
      if (call.method == 'txOutput') {
        // pamac redraws progress lines with \r: keep the last state.
        final line = (call.arguments as String).split('\r').last.trimRight();
        if (line.isNotEmpty) {
          log.add(line);
          if (log.length > 400) log.removeRange(0, log.length - 400);
          notifyListeners();
        }
      } else if (call.method == 'txDone') {
        _finish(call.arguments as int);
      }
    });
  }

  final queue = <Job>[];
  final log = <String>[];
  Job? current;

  /// The last finished job and whether it worked, for the status line.
  Job? lastJob;
  bool lastOk = true;

  /// Bumped after every finished job, so pages know to reload.
  int generation = 0;

  bool get busy => current != null;

  bool pending(String name) =>
      [?current, ...queue].any((j) => j.args.contains(name));

  void add(Job job) {
    queue.add(job);
    notifyListeners();
    _next();
  }

  Future<void> _next() async {
    if (current != null || queue.isEmpty) return;
    current = queue.removeAt(0);
    log
      ..clear()
      ..add('pamac ${current!.args.join(' ')}');
    notifyListeners();
    try {
      await Pamac._channel.invokeMethod('run', {'args': current!.args});
    } on PlatformException catch (e) {
      log.add(e.message ?? 'could not start pamac');
      _finish(-1);
    }
  }

  void _finish(int status) {
    lastJob = current;
    lastOk = status == 0;
    current = null;
    generation++;
    notifyListeners();
    _next();
  }
}
