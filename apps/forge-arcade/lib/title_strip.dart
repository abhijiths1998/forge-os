// Hyprland draws no titlebars, so the Arcade draws its own: drag to move,
// a button to close. The runner does the moving and closing (my_application.cc).
// The shared forge_ui strip will replace this.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

const _channel = MethodChannel('org.forgeos.arcade/window');

Future<void> _call(String method) async {
  try {
    await _channel.invokeMethod<void>(method);
  } on MissingPluginException {
    // Tests, or a runner without the channel.
  }
}

class TitleStrip extends StatelessWidget {
  const TitleStrip({super.key, required this.palette, this.onClose});

  final ForgePalette palette;

  /// Defaults to closing the window through the runner.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => _call('startDrag'),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            const SizedBox(width: 20),
            Icon(Icons.sports_esports_rounded, size: 18, color: palette.accent),
            const SizedBox(width: 10),
            Text('Forge Arcade',
                style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700, color: palette.text)),
            const Spacer(),
            IconButton(
              tooltip: 'Close',
              iconSize: 18,
              color: palette.dimText,
              hoverColor: palette.negative.withValues(alpha: 0.3),
              icon: const Icon(Icons.close_rounded),
              onPressed: onClose ?? () => _call('close'),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
