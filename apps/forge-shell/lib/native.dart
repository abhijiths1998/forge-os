// The GTK runner's side of things (linux/runner/my_application.cc).
import 'package:flutter/services.dart';

class App {
  App(Map<Object?, Object?> m)
    : id = m['id'] as String,
      name = m['name'] as String,
      exec = m['exec'] as String,
      wmClass = m['wmclass'] as String,
      comment = m['comment'] as String? ?? '',
      generic = m['generic'] as String? ?? '',
      categories = _list(m['categories']),
      keywords = _list(m['keywords']),
      show = m['show'] as bool? ?? true;

  static List<String> _list(Object? s) => [
    for (final part in (s as String? ?? '').split(';'))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  final String id; // the desktop file's name, "org.kde.dolphin.desktop"
  final String name;
  final String exec;
  final String wmClass;
  final String comment;
  final String generic; // "Web Browser"
  final List<String> categories; // freedesktop's: Game, Network, ...
  final List<String> keywords;

  /// Listed in menus (not NoDisplay or hidden from this desktop).
  final bool show;

  /// Whether a window with this app id or class belongs to this app: its
  /// StartupWMClass, its desktop id ("org.kde.dolphin") or that id's last
  /// part ("dolphin"), or its command's name.
  bool owns(String windowClass) {
    final c = windowClass.toLowerCase();
    if (c.isEmpty) return false;
    final base = id.replaceFirst(RegExp(r'\.desktop$'), '').toLowerCase();
    return c == wmClass.toLowerCase() ||
        c == base ||
        c == base.split('.').last ||
        c == exec.split('/').last.toLowerCase();
  }
}

class Native {
  static const _channel = MethodChannel('forge/shell');
  static final _icons = <String, Future<Uint8List?>>{};

  static Future<List<App>> apps() async {
    final list = await _channel.invokeListMethod<Object?>('apps') ?? [];
    return [for (final m in list) App(m as Map<Object?, Object?>)];
  }

  /// PNG bytes for an app's icon (by desktop id) or a themed icon name.
  static Future<Uint8List?> icon({String? app, String? name, int size = 48}) {
    final key = '${app ?? ''}|${name ?? ''}|$size';
    return _icons[key] ??= _channel.invokeMethod<Uint8List>('icon', {
      'app': app ?? '',
      'name': name ?? '',
      'size': size,
    });
  }

  /// Calls from the runner (polkit's requests, in the popups part).
  static void onCall(Future<Object?> Function(MethodCall call) handler) =>
      _channel.setMethodCallHandler(handler);

  static Future<T?> call<T>(String method, [Object? args]) =>
      _channel.invokeMethod<T>(method, args);

  /// The screen's size in logical pixels.
  static Future<Size> screen() async {
    final m = await _channel.invokeMapMethod<String, Object?>('screen');
    return Size(
      (m?['width'] as int? ?? 1920).toDouble(),
      (m?['height'] as int? ?? 1080).toDouble(),
    );
  }

  static Future<void> launch(String appId) =>
      _channel.invokeMethod('launch', {'app': appId});

  static Future<void> setWidth(int width) =>
      _channel.invokeMethod('setWidth', {'width': width});

  /// Starts a command line and leaves it running on its own.
  static Future<void> run(String command) =>
      _channel.invokeMethod('run', {'command': command}).catchError((_) {});
}
