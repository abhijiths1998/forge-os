// The GTK runner's side of things (linux/runner/my_application.cc).

import 'package:flutter/services.dart';

class App {
  App(Map<Object?, Object?> m)
      : id = m['id'] as String,
        name = m['name'] as String,
        comment = m['comment'] as String,
        generic = m['generic'] as String,
        exec = m['exec'] as String,
        keywords = (m['keywords'] as String)
            .split(';')
            .where((k) => k.isNotEmpty)
            .toList();

  final String id;
  final String name;
  final String comment;
  final String generic;
  final String exec;
  final List<String> keywords;
}

class Native {
  static const _channel = MethodChannel('forge/launcher');
  static final _icons = <String, Future<Uint8List?>>{};

  /// Called with "shown" / "hidden" as the runner toggles the window.
  static void onEvent(void Function(String event) handler) {
    _channel.setMethodCallHandler((call) async => handler(call.method));
  }

  static Future<List<App>> apps() async {
    final list = await _channel.invokeListMethod<Object?>('apps') ?? [];
    return [for (final m in list) App(m as Map<Object?, Object?>)];
  }

  /// PNG bytes for an app's icon (by desktop id) or a themed icon name.
  static Future<Uint8List?> icon({String? app, String? name, int size = 32}) {
    final key = '${app ?? ''}|${name ?? ''}|$size';
    return _icons[key] ??= _channel.invokeMethod<Uint8List>(
        'icon', {'app': app ?? '', 'name': name ?? '', 'size': size});
  }

  static Future<void> launch(String appId) =>
      _channel.invokeMethod('launch', {'app': appId});

  static Future<void> hide() => _channel.invokeMethod('hide');

  static Future<void> setHeight(int height) =>
      _channel.invokeMethod('setHeight', {'height': height});
}
