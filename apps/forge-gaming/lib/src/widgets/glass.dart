// The Forge Gaming look: liquid glass panels without outlines over a blurred
// backdrop of the game in focus, with focus shown as a lift and an accent
// glow so it reads from the sofa.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../models.dart';
import '../pad.dart';

/// A frosted panel: blurs what is behind it, a soft light-to-clear sheen,
/// a shadow, no border.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.palette,
    required this.child,
    this.radius = 22,
    this.padding = const EdgeInsets.all(20),
    this.blur = 28,
    this.strength = 1,
  });

  final ForgePalette palette;
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double blur;

  /// How milky the glass is; 1 is the default panel.
  final double strength;

  @override
  Widget build(BuildContext context) {
    const light = Colors.white;
    final shade = palette.dark ? Colors.black : const Color(0xFF8090A0);
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 32, offset: const Offset(0, 12)),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  light.withValues(alpha: (palette.dark ? 0.13 : 0.55) * strength),
                  light.withValues(alpha: (palette.dark ? 0.05 : 0.30) * strength),
                  shade.withValues(alpha: (palette.dark ? 0.10 : 0.05) * strength),
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
            // The sheen along the top edge that makes it read as glass.
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [light.withValues(alpha: 0.10 * strength), light.withValues(alpha: 0)],
                ),
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// A picture from a path or https URL; a generated gradient with the title's
/// initials when there is none or it fails to load.
class GameArt extends StatelessWidget {
  const GameArt({
    super.key,
    required this.source,
    required this.title,
    this.fit = BoxFit.cover,
    this.placeholderText = true,
  });

  final String? source;
  final String title;
  final BoxFit fit;
  final bool placeholderText;

  @override
  Widget build(BuildContext context) {
    final s = source;
    Widget fallback(BuildContext _, Object _, StackTrace? _) =>
        ArtPlaceholder(title: title, showText: placeholderText);
    if (s == null || s.isEmpty) return ArtPlaceholder(title: title, showText: placeholderText);
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return Image.network(s, fit: fit, errorBuilder: fallback, gaplessPlayback: true);
    }
    return Image.file(File(s), fit: fit, errorBuilder: fallback, gaplessPlayback: true);
  }
}

/// Two colours picked from the title, so a game without art still has a
/// stable look of its own.
(Color, Color) titleColours(String title) {
  var h = 0;
  for (final c in title.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  final hue = (h % 360).toDouble();
  return (
    HSLColor.fromAHSL(1, hue, 0.55, 0.42).toColor(),
    HSLColor.fromAHSL(1, (hue + 50) % 360, 0.65, 0.22).toColor(),
  );
}

String initials(String title) {
  final words = title.split(RegExp(r'[\s:_\-]+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.substring(0, math.min(2, words.first.length)).toUpperCase();
  return (words[0][0] + words[1][0]).toUpperCase();
}

class ArtPlaceholder extends StatelessWidget {
  const ArtPlaceholder({super.key, required this.title, this.showText = true});

  final String title;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final (a, b) = titleColours(title);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b]),
      ),
      child: showText
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(initials(title),
                      style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          color: Colors.white.withValues(alpha: 0.9),
                          letterSpacing: 1)),
                  const SizedBox(height: 6),
                  Text(title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.75))),
                ]),
              ),
            )
          : const SizedBox.expand(),
    );
  }
}

/// The whole-window background: the focused game's art, heavily blurred and
/// dimmed, cross-fading as focus moves, over the translucent window.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.palette, required this.game, this.opacity = 0.55});

  final ForgePalette palette;
  final Game? game;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final g = game;
    return Stack(fit: StackFit.expand, children: [
      ColoredBox(color: palette.window),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        child: g == null
            ? const SizedBox.expand()
            : Opacity(
                key: ValueKey(g.id),
                opacity: opacity,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50, tileMode: TileMode.decal),
                  child: GameArt(source: g.backdrop, title: g.title, placeholderText: false),
                ),
              ),
      ),
      // Keep text readable: darken towards the bottom-left where content sits.
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Colors.black.withValues(alpha: palette.dark ? 0.05 : 0),
              Colors.black.withValues(alpha: palette.dark ? 0.45 : 0.15),
            ],
          ),
        ),
      ),
    ]);
  }
}

/// Makes [builder]'s child focusable and activatable (A, Enter, Space,
/// click), and tells it whether it has focus so it can lift and glow.
class Focusable extends StatefulWidget {
  const Focusable({
    super.key,
    required this.builder,
    this.onActivate,
    this.onFocus,
    this.autofocus = false,
    this.focusNode,
    this.mouseCursor = SystemMouseCursors.click,
  });

  final Widget Function(BuildContext context, bool focused, bool hovered) builder;
  final VoidCallback? onActivate;
  final ValueChanged<bool>? onFocus;
  final bool autofocus;
  final FocusNode? focusNode;
  final MouseCursor mouseCursor;

  @override
  State<Focusable> createState() => _FocusableState();
}

class _FocusableState extends State<Focusable> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onActivate != null;
    return FocusableActionDetector(
      enabled: true,
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      mouseCursor: enabled ? widget.mouseCursor : MouseCursor.defer,
      onShowFocusHighlight: (_) {},
      onFocusChange: (f) {
        setState(() => _focused = f);
        widget.onFocus?.call(f);
      },
      onShowHoverHighlight: (h) => setState(() => _hovered = h),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onActivate?.call();
          return null;
        }),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                widget.focusNode?.requestFocus();
                widget.onActivate!();
              }
            : null,
        child: widget.builder(context, _focused, _hovered),
      ),
    );
  }
}

/// The lift-and-glow focus treatment around any rounded child.
class FocusGlow extends StatelessWidget {
  const FocusGlow({
    super.key,
    required this.palette,
    required this.focused,
    required this.child,
    this.radius = 18,
    this.scale = 1.05,
    this.hovered = false,
  });

  final ForgePalette palette;
  final bool focused;
  final bool hovered;
  final Widget child;
  final double radius;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final on = focused || hovered;
    return AnimatedScale(
      scale: focused ? scale : (hovered ? 1 + (scale - 1) / 2 : 1),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            if (focused)
              BoxShadow(color: palette.accent.withValues(alpha: 0.55), blurRadius: 28, spreadRadius: 1),
            BoxShadow(
              color: Colors.black.withValues(alpha: on ? 0.40 : 0.25),
              blurRadius: on ? 26 : 14,
              offset: Offset(0, on ? 12 : 6),
            ),
          ],
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          // A thin accent ring only while focused, so the pad user always
          // knows where they are; resting state stays borderless.
          border: focused ? Border.all(color: palette.accent.withValues(alpha: 0.95), width: 2.5) : null,
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: child),
      ),
    );
  }
}

/// A pill button that works with mouse, keyboard and pad.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.palette,
    required this.label,
    this.icon,
    this.onPressed,
    this.filled = false,
    this.large = false,
    this.autofocus = false,
    this.focusNode,
    this.danger = false,
  });

  final ForgePalette palette;
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool filled;
  final bool large;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final base = danger ? palette.negative : palette.accent;
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: Focusable(
        autofocus: autofocus,
        focusNode: focusNode,
        onActivate: onPressed,
        builder: (context, focused, hovered) => FocusGlow(
          palette: palette,
          focused: focused,
          hovered: hovered,
          radius: 40,
          scale: 1.04,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: EdgeInsets.symmetric(horizontal: large ? 30 : 18, vertical: large ? 15 : 10),
            decoration: BoxDecoration(
              gradient: filled
                  ? LinearGradient(colors: [
                      Color.lerp(base, Colors.white, focused ? 0.18 : 0.05)!,
                      Color.lerp(base, Colors.black, 0.15)!,
                    ])
                  : null,
              color: filled
                  ? null
                  : Colors.white.withValues(alpha: focused || hovered ? 0.18 : (palette.dark ? 0.08 : 0.35)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, size: large ? 24 : 18, color: filled ? palette.onAccent : palette.text),
                SizedBox(width: large ? 10 : 8),
              ],
              Text(label,
                  style: TextStyle(
                    color: filled ? palette.onAccent : palette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: large ? 17 : 13.5,
                  )),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A selectable chip (filters, segmented choices).
class GlassChip extends StatelessWidget {
  const GlassChip({
    super.key,
    required this.palette,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
    this.count,
  });

  final ForgePalette palette;
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final IconData? icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Focusable(
      onActivate: onSelected,
      builder: (context, focused, hovered) => FocusGlow(
        palette: palette,
        focused: focused,
        hovered: hovered,
        radius: 30,
        scale: 1.04,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          color: selected
              ? palette.accent.withValues(alpha: 0.85)
              : Colors.white.withValues(alpha: focused || hovered ? 0.16 : (palette.dark ? 0.07 : 0.3)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: selected ? palette.onAccent : palette.text),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? palette.onAccent : palette.text,
                )),
            if (count != null) ...[
              const SizedBox(width: 6),
              Text('$count',
                  style: TextStyle(
                    fontSize: 12,
                    color: (selected ? palette.onAccent : palette.dimText).withValues(alpha: 0.8),
                  )),
            ],
          ]),
        ),
      ),
    );
  }
}

/// A pad-friendly switch row: label, explanation, and the switch; A toggles.
class GlassToggle extends StatelessWidget {
  const GlassToggle({
    super.key,
    required this.palette,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final ForgePalette palette;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Focusable(
      onActivate: () => onChanged(!value),
      builder: (context, focused, hovered) => FocusGlow(
        palette: palette,
        focused: focused,
        hovered: hovered,
        radius: 14,
        scale: 1.01,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.white.withValues(alpha: focused || hovered ? 0.12 : (palette.dark ? 0.05 : 0.25)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: palette.text)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: TextStyle(fontSize: 12, color: palette.dimText)),
                  ),
              ]),
            ),
            ExcludeFocus(
              child: Switch(value: value, onChanged: onChanged, activeTrackColor: palette.accent),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A round glyph for a pad button, coloured like the pad's own when it is a
/// face button.
class PadGlyph extends StatelessWidget {
  const PadGlyph(this.button, {super.key, this.size = 22, this.type = PadType.xbox});

  final PadButton button;
  final double size;
  final PadType type;

  @override
  Widget build(BuildContext context) {
    final (text, colour) = switch ((button, type)) {
      (PadButton.a, PadType.playstation) => ('✕', const Color(0xFF7AA7FF)),
      (PadButton.b, PadType.playstation) => ('○', const Color(0xFFFF6B7A)),
      (PadButton.x, PadType.playstation) => ('□', const Color(0xFFE58CFF)),
      (PadButton.y, PadType.playstation) => ('△', const Color(0xFF4DE5B0)),
      (PadButton.a, _) => ('A', const Color(0xFF5FD068)),
      (PadButton.b, _) => ('B', const Color(0xFFFF5F5F)),
      (PadButton.x, _) => ('X', const Color(0xFF4D9BFF)),
      (PadButton.y, _) => ('Y', const Color(0xFFFFC94D)),
      (PadButton.lb, _) => ('LB', Colors.white70),
      (PadButton.rb, _) => ('RB', Colors.white70),
      (PadButton.lt, _) => ('LT', Colors.white70),
      (PadButton.rt, _) => ('RT', Colors.white70),
      (PadButton.start, _) => ('☰', Colors.white70),
      (PadButton.back, _) => ('⧉', Colors.white70),
      (PadButton.guide, _) => ('⌂', Colors.white70),
      _ => ('✥', Colors.white70),
    };
    final wide = text.length > 1;
    return Container(
      height: size,
      constraints: BoxConstraints(minWidth: size),
      padding: EdgeInsets.symmetric(horizontal: wide ? size * 0.25 : 0),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: colour.withValues(alpha: 0.9), width: 1.5),
      ),
      child: Text(text,
          style: TextStyle(
              color: colour, fontWeight: FontWeight.w800, fontSize: size * (wide ? 0.42 : 0.52), height: 1)),
    );
  }
}

/// The strip of "A Play · B Back" hints shown while a pad is connected.
class PadHintBar extends StatelessWidget {
  const PadHintBar({super.key, required this.palette, required this.hints, this.type = PadType.xbox});

  final ForgePalette palette;
  final List<PadHint> hints;
  final PadType type;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 18, runSpacing: 8, children: [
      for (final h in hints)
        Row(mainAxisSize: MainAxisSize.min, children: [
          PadGlyph(h.button, type: type),
          if (h.also != null) ...[const SizedBox(width: 4), PadGlyph(h.also!, type: type)],
          const SizedBox(width: 7),
          Text(h.label,
              style: TextStyle(color: palette.text.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
    ]);
  }
}
