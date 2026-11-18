// The window itself, through the runner (linux/runner/my_application.cc):
// Hyprland draws no titlebar, so the app drags, closes and goes full screen
// by asking GTK.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

const _channel = MethodChannel('org.forgeos.gaming/window');

Future<void> windowCall(String method, [Object? args]) async {
  try {
    await _channel.invokeMethod<void>(method, args);
  } on MissingPluginException {
    // Tests, or a runner without the channel.
  }
}

/// Brings the window forward over a running game. GTK's present is only a
/// hint on Wayland, so on Hyprland ask the compositor too.
Future<void> bringToFront() async {
  await windowCall('present');
  if (Platform.environment['HYPRLAND_INSTANCE_SIGNATURE'] == null) return;
  try {
    await Process.run('hyprctl', ['dispatch', 'focuswindow', 'class:org.forgeos.gaming']);
  } on ProcessException {
    // No hyprctl; the GTK hint is all we have.
  }
}

/// Hands the screen back to the game. Hyprland has no minimising, so there
/// focus the window that had it before; elsewhere minimise.
Future<void> returnToGame() async {
  if (Platform.environment['HYPRLAND_INSTANCE_SIGNATURE'] != null) {
    try {
      await Process.run('hyprctl', ['dispatch', 'focuscurrentorlast']);
      return;
    } on ProcessException {
      // Fall through to the GTK way.
    }
  }
  await windowCall('minimize');
}

class TitleStrip extends StatelessWidget {
  const TitleStrip({super.key, required this.palette, this.trailing = const []});

  final ForgePalette palette;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String tip, String method, Color hover) => ExcludeFocus(
          child: IconButton(
            tooltip: tip,
            iconSize: 17,
            color: palette.dimText,
            hoverColor: hover,
            icon: Icon(icon),
            onPressed: () => windowCall(method),
          ),
        );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowCall('startDrag'),
      child: SizedBox(
        height: 46,
        child: Row(children: [
          const SizedBox(width: 20),
          Icon(Icons.sports_esports_rounded, size: 19, color: palette.accent),
          const SizedBox(width: 10),
          Text('Forge Gaming',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: palette.text, letterSpacing: 0.2)),
          const Spacer(),
          ...trailing,
          button(Icons.remove_rounded, 'Minimise', 'minimize', palette.hover),
          button(Icons.close_rounded, 'Close', 'close', palette.negative.withValues(alpha: 0.3)),
          const SizedBox(width: 8),
        ]),
      ),
    );
  }
}
