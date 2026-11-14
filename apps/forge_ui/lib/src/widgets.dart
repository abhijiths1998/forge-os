// Forge UI building blocks: the pieces every Forge app is made of, so they
// look and behave alike.
import 'package:flutter/material.dart';

import 'palette.dart';

/// A rounded translucent panel, the basic Forge surface. No outline: like
/// the windows, the glass runs to the edge.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.palette,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.selected = false,
    this.radius = 14,
  });

  final ForgePalette palette;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final bool selected;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? palette.accent.withValues(alpha: 0.22) : palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: selected
            ? BorderSide(color: palette.accent, width: 2)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: palette.hover,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A rounded pill button: filled (accent) or quiet.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.palette,
    required this.label,
    this.onTap,
    this.filled = false,
    this.icon,
  });

  final ForgePalette palette;
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? palette.onAccent : palette.text;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: filled ? palette.accent : palette.hover,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
              Text(label,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A small upper-case heading over a group of controls.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, required this.palette});

  final String text;
  final ForgePalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: palette.dimText)),
    );
  }
}

/// A labelled slider with its value and a one-line explanation.
class ForgeSlider extends StatelessWidget {
  const ForgeSlider({
    super.key,
    required this.palette,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.divisions,
    this.format,
    this.hint,
    this.track,
  });

  final ForgePalette palette;
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String Function(double)? format;
  final String? hint;

  /// A gradient for the track (hue pickers), instead of the accent.
  final Gradient? track;

  @override
  Widget build(BuildContext context) {
    final shown = format?.call(value) ?? value.toStringAsFixed(divisions == null ? 1 : 0);
    Widget slider = Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
      onChanged: onChanged,
      onChangeEnd: onChangeEnd,
    );
    if (track != null) {
      slider = Stack(alignment: Alignment.center, children: [
        Container(
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(gradient: track, borderRadius: BorderRadius.circular(4)),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.transparent,
            inactiveTrackColor: Colors.transparent,
          ),
          child: slider,
        ),
      ]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              Text(label,
                  style: TextStyle(
                      color: palette.text, fontSize: 13.5, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(shown, style: TextStyle(color: palette.dimText, fontSize: 12.5)),
            ]),
          ),
          SizedBox(height: 34, child: slider),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
              child: Text(hint!, style: TextStyle(color: palette.dimText, fontSize: 11.5)),
            ),
        ],
      ),
    );
  }
}

/// A two-or-more way switch (Dark / Light).
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.palette,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final ForgePalette palette;
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: palette.hover, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final e in options.entries)
          GestureDetector(
            onTap: () => onChanged(e.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              decoration: BoxDecoration(
                color: e.key == value ? palette.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(e.value,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: e.key == value ? palette.onAccent : palette.text)),
            ),
          ),
      ]),
    );
  }
}

/// A hue gradient, for hue sliders.
const hueGradient = LinearGradient(colors: [
  Color(0xFFFF4D4D), Color(0xFFFFB84D), Color(0xFFE5FF4D), Color(0xFF4DFF88),
  Color(0xFF4DE5FF), Color(0xFF4D7BFF), Color(0xFFB84DFF), Color(0xFFFF4DB8),
  Color(0xFFFF4D4D),
]);
