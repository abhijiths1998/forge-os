// The temperature gauge and the last minutes of CPU/GPU temperatures.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// Series colours (CPU, GPU): the validated categorical slots 1 and 2,
/// stepped for each mode.
Color cpuColour(ForgePalette p) => p.dark ? const Color(0xFF3987E5) : const Color(0xFF2A78D6);
Color gpuColour(ForgePalette p) => p.dark ? const Color(0xFFD95926) : const Color(0xFFEB6834);

/// How hot a reading is, against the limit the hardware holds it at.
enum Heat { cool, warm, hot }

extension HeatLook on Heat {
  String get label => const {Heat.cool: 'Cool', Heat.warm: 'Warm', Heat.hot: 'Hot'}[this]!;

  // Status colours: reserved for state, never a series, always with an
  // icon and a label.
  Color get colour =>
      const {Heat.cool: Color(0xFF0CA30C), Heat.warm: Color(0xFFFAB219), Heat.hot: Color(0xFFD03B3B)}[this]!;

  IconData get icon => const {
    Heat.cool: Icons.ac_unit_rounded,
    Heat.warm: Icons.thermostat_rounded,
    Heat.hot: Icons.local_fire_department_rounded,
  }[this]!;
}

Heat heatOf(double temp, double limit) => temp >= limit - 5 ? Heat.hot : (temp >= limit - 20 ? Heat.warm : Heat.cool);

/// A 270° arc from [min] to [limit], filled to [value], with the number in
/// the middle.
class TempGauge extends StatelessWidget {
  const TempGauge({
    super.key,
    required this.palette,
    required this.value,
    required this.limit,
    this.min = 30,
    this.size = 150,
  });

  final ForgePalette palette;
  final double? value;
  final double limit;
  final double min;
  final double size;

  @override
  Widget build(BuildContext context) {
    final v = value;
    final heat = v == null ? null : heatOf(v, limit);
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: v ?? min),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, shown, _) => CustomPaint(
          painter: _GaugePainter(
            fraction: ((shown - min) / (limit - min)).clamp(0.0, 1.0),
            track: palette.hover,
            fill: heat?.colour ?? palette.dimText,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  v == null ? '–' : '${shown.round()}°',
                  style: TextStyle(
                    fontSize: size * 0.24,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (heat != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(heat.icon, size: 13, color: heat.colour),
                      const SizedBox(width: 4),
                      Text(
                        heat.label,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.dimText),
                      ),
                    ],
                  ),
                Text('limit ${limit.round()}°', style: TextStyle(fontSize: 11, color: palette.dimText)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.fraction, required this.track, required this.fill});

  final double fraction;
  final Color track;
  final Color fill;

  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, paint..color = track);
    if (fraction > 0) canvas.drawArc(rect, _start, _sweep * fraction, false, paint..color = fill);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.fraction != fraction || old.fill != fill || old.track != track;
}

/// One reading of both temperatures.
class Sample {
  const Sample(this.at, this.cpu, this.gpu);

  final DateTime at;
  final double? cpu;
  final double? gpu;
}

/// CPU and GPU temperature over the last [window], one °C axis, with a
/// crosshair and tooltip under the pointer.
class HistoryChart extends StatefulWidget {
  const HistoryChart({
    super.key,
    required this.palette,
    required this.samples,
    this.window = const Duration(minutes: 2),
  });

  final ForgePalette palette;
  final List<Sample> samples;
  final Duration window;

  @override
  State<HistoryChart> createState() => _HistoryChartState();
}

class _HistoryChartState extends State<HistoryChart> {
  double? _hoverX;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final geo = _Geometry(box.biggest, widget.window, widget.samples);
        final hovered = _hoverX == null ? null : geo.nearest(_hoverX!);
        return MouseRegion(
          onHover: (e) => setState(() => _hoverX = e.localPosition.dx),
          onExit: (_) => setState(() => _hoverX = null),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                size: box.biggest,
                painter: _HistoryPainter(palette: widget.palette, geo: geo, hovered: hovered),
              ),
              if (hovered != null) _tooltip(geo, hovered),
            ],
          ),
        );
      },
    );
  }

  Widget _tooltip(_Geometry geo, Sample s) {
    final p = widget.palette;
    final ago = geo.now.difference(s.at).inSeconds;
    final x = geo.x(s.at);
    const width = 132.0;
    final left = x + 12 + width > geo.size.width ? x - 12 - width : x + 12;
    Widget row(String name, Color c, double? v) => Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 3,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 6),
          Text(name, style: TextStyle(fontSize: 12, color: p.dimText)),
          const Spacer(),
          Text(
            v == null ? '–' : '${v.round()} °C',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text),
          ),
        ],
      ),
    );
    return Positioned(
      left: left,
      top: 4,
      width: width,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: p.dark ? const Color(0xF0262944) : const Color(0xF5FFFFFF),
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ago <= 1 ? 'Now' : '$ago s ago', style: TextStyle(fontSize: 11, color: p.dimText)),
              row('CPU', cpuColour(p), s.cpu),
              row('GPU', gpuColour(p), s.gpu),
            ],
          ),
        ),
      ),
    );
  }
}

class _Geometry {
  _Geometry(this.size, this.window, this.samples) : now = DateTime.now();

  final Size size;
  final Duration window;
  final List<Sample> samples;
  final DateTime now;

  static const lo = 30.0, hi = 100.0;
  static const left = 34.0, right = 64.0, top = 8.0, bottom = 22.0;

  Rect get plot => Rect.fromLTRB(left, top, size.width - right, size.height - bottom);

  double x(DateTime at) {
    final f = 1 - now.difference(at).inMilliseconds / window.inMilliseconds;
    return plot.left + plot.width * f.clamp(0.0, 1.0);
  }

  double y(double temp) => plot.bottom - plot.height * ((temp - lo) / (hi - lo)).clamp(0.0, 1.0);

  Sample? nearest(double px) {
    Sample? best;
    var bestD = double.infinity;
    for (final s in samples) {
      final d = (x(s.at) - px).abs();
      if (d < bestD) (best, bestD) = (s, d);
    }
    return bestD < 30 ? best : null;
  }
}

class _HistoryPainter extends CustomPainter {
  _HistoryPainter({required this.palette, required this.geo, this.hovered});

  final ForgePalette palette;
  final _Geometry geo;
  final Sample? hovered;

  void _text(Canvas c, String s, Offset at, {Color? colour, bool bold = false, TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: 11,
          color: colour ?? palette.dimText,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = align == TextAlign.right ? at.dx - tp.width : at.dx;
    tp.paint(c, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plot = geo.plot;
    final grid = Paint()
      ..color = palette.text.withValues(alpha: 0.09)
      ..strokeWidth = 1;
    for (final t in [40.0, 60.0, 80.0, 100.0]) {
      final y = geo.y(t).roundToDouble() + 0.5;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _text(canvas, '${t.round()}°', Offset(plot.left - 8, y), align: TextAlign.right);
    }
    canvas.drawLine(
      Offset(plot.left, plot.bottom + 0.5),
      Offset(plot.right, plot.bottom + 0.5),
      Paint()..color = palette.text.withValues(alpha: 0.22),
    );
    _text(canvas, '${geo.window.inMinutes} min ago', Offset(plot.left, plot.bottom + 12));
    _text(canvas, 'now', Offset(plot.right, plot.bottom + 12), align: TextAlign.right);

    final ends = <(String, Color, Offset, double)>[];
    for (final (name, colour, pick) in [
      ('CPU', cpuColour(palette), (Sample s) => s.cpu),
      ('GPU', gpuColour(palette), (Sample s) => s.gpu),
    ]) {
      final path = Path();
      var started = false;
      Offset? last;
      double? lastV;
      for (final s in geo.samples) {
        final v = pick(s);
        if (v == null) {
          started = false;
          continue;
        }
        final pt = Offset(geo.x(s.at), geo.y(v));
        started ? path.lineTo(pt.dx, pt.dy) : path.moveTo(pt.dx, pt.dy);
        started = true;
        last = pt;
        lastV = v;
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..color = colour,
      );
      if (last != null) ends.add((name, colour, last, lastV!));
    }

    // End dots, and the value as a direct label unless the two collide
    // (then the legend and the tooltip carry it).
    final collide = ends.length == 2 && (ends[0].$3.dy - ends[1].$3.dy).abs() < 14;
    for (final (name, colour, pt, v) in ends) {
      canvas.drawCircle(pt, 4, Paint()..color = colour);
      if (!collide) _text(canvas, '$name ${v.round()}°', Offset(pt.dx + 10, pt.dy), colour: palette.text, bold: true);
    }

    final h = hovered;
    if (h != null) {
      final x = geo.x(h.at);
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()..color = palette.text.withValues(alpha: 0.3),
      );
      for (final (v, colour) in [(h.cpu, cpuColour(palette)), (h.gpu, gpuColour(palette))]) {
        if (v == null) continue;
        final pt = Offset(x, geo.y(v));
        canvas.drawCircle(pt, 4, Paint()..color = colour);
      }
    }
  }

  @override
  bool shouldRepaint(_HistoryPainter old) => true;
}
