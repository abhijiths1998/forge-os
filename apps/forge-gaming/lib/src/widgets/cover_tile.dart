// A game in the library: its portrait cover, lifting and glowing in focus,
// with badges for running, favourite and where it comes from.
import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../models.dart';
import 'glass.dart';

IconData sourceIcon(GameSource s) => switch (s) {
      GameSource.steam => Icons.cloud_rounded,
      GameSource.heroic => Icons.shield_rounded,
      GameSource.lutris => Icons.wine_bar_rounded,
      GameSource.local => Icons.folder_special_rounded,
    };

class CoverTile extends StatelessWidget {
  const CoverTile({
    super.key,
    required this.palette,
    required this.game,
    required this.onActivate,
    this.onFocus,
    this.autofocus = false,
    this.focusNode,
    this.showTitle = true,
    this.busy = false,
  });

  final ForgePalette palette;
  final Game game;
  final VoidCallback onActivate;
  final ValueChanged<bool>? onFocus;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool showTitle;

  /// Handed to Steam/Heroic a moment ago.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Focusable(
      autofocus: autofocus,
      focusNode: focusNode,
      onActivate: onActivate,
      onFocus: onFocus,
      builder: (context, focused, hovered) => FocusGlow(
        palette: palette,
        focused: focused,
        hovered: hovered,
        radius: 16,
        scale: 1.07,
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: Stack(fit: StackFit.expand, children: [
            GameArt(source: game.cover, title: game.title),
            // Bottom fade for the caption.
            if (showTitle && (focused || hovered || game.cover == null))
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC000000)],
                  ),
                ),
              ),
            // A glass sheen across the top when focused.
            if (focused)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.center,
                    colors: [Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0)],
                  ),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(children: [
                _Badge(icon: sourceIcon(game.source)),
                const Spacer(),
                if (game.favorite) const _Badge(icon: Icons.star_rounded, colour: Color(0xFFFFC94D)),
              ]),
            ),
            if (game.running || busy)
              Positioned(
                top: 40,
                left: 8,
                child: _Pill(
                  text: game.running ? 'Playing' : 'Starting…',
                  colour: game.running ? palette.positive : palette.accent,
                ),
              ),
            if (showTitle && (focused || hovered))
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(game.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(formatPlaytime(game.playtimeMinutes),
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11.5)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, this.colour = Colors.white});
  final IconData icon;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
        child: Icon(icon, size: 14, color: colour),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.colour});
  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.play_arrow_rounded, size: 13, color: Colors.white),
          const SizedBox(width: 3),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );
}
