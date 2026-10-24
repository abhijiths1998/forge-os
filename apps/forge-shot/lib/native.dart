// The GTK runner's side (linux/runner/my_application.cc): the clipboard,
// turning the overlay into the thumbnail, and quitting.
import 'package:flutter/services.dart';

class Native {
  static const _channel = MethodChannel('forge/shot');

  static Future<bool> copyImage(String path) async =>
      await _channel.invokeMethod<bool>('copyImage', {'path': path}) ?? false;

  static Future<bool> copyText(String text) async =>
      await _channel.invokeMethod<bool>('copyText', {'text': text}) ?? false;

  /// "thumbnail": the bottom-right corner, without the keyboard; "hidden".
  static Future<void> present(String mode) =>
      _channel.invokeMethod('present', {'mode': mode});

  static Future<void> quit() => _channel.invokeMethod('quit');
}
