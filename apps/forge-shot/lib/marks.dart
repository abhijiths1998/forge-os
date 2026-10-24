// What the editor draws on a screenshot, kept in the image's own pixels so
// it exports at full resolution whatever the zoom: arrows, boxes, ellipses,
// lines, pen and highlighter strokes, text, pixelated areas (to hide things)
// and numbered steps.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum Tool { arrow, rect, ellipse, line, pen, highlight, text, pixelate, step, crop }

class Mark {
  Mark({required this.tool, required this.color, required this.width, required this.points, this.text = '', this.number = 0});

  final Tool tool;
  final Color color;
  final double width;
  final List<Offset> points;
  final String text;
  final int number;

  Rect get bounds => points.length < 2 ? Rect.fromCircle(center: points.first, radius: width * 5) : Rect.fromPoints(points.first, points.last);
}

/// A copy of the image in big blocks, for the pixelate tool to show through.
Future<ui.Image> pixelated(ui.Image image) async {
  final block = math.max(8, (math.max(image.width, image.height) / 120).round());
  final w = math.max(1, image.width ~/ block), h = math.max(1, image.height ~/ block);
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      Offset.zero & Size(w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.medium);
  return recorder.endRecording().toImage(w, h);
}

/// Draws the image and the marks, in image pixels.
void paintShot(Canvas canvas, ui.Image image, ui.Image? blocks, List<Mark> marks) {
  final full = Offset.zero & Size(image.width.toDouble(), image.height.toDouble());
  canvas.drawImageRect(image, full, full, Paint()..filterQuality = FilterQuality.medium);
  for (final m in marks) {
    paintMark(canvas, m, image, blocks);
  }
}

void paintMark(Canvas canvas, Mark m, ui.Image image, ui.Image? blocks) {
  final stroke = Paint()
    ..color = m.color
    ..strokeWidth = m.width
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final a = m.points.first, b = m.points.last;
  switch (m.tool) {
    case Tool.arrow:
      final angle = (b - a).direction;
      final head = math.max(14.0, m.width * 4.2);
      canvas.drawLine(a, b - Offset.fromDirection(angle, head * 0.6), stroke);
      final tip = Path()
        ..moveTo(b.dx, b.dy)
        ..lineTo(b.dx - head * math.cos(angle - 0.45), b.dy - head * math.sin(angle - 0.45))
        ..lineTo(b.dx - head * math.cos(angle + 0.45), b.dy - head * math.sin(angle + 0.45))
        ..close();
      canvas.drawPath(tip, Paint()..color = m.color);
    case Tool.rect:
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(a, b), Radius.circular(m.width * 1.5)), stroke);
    case Tool.ellipse:
      canvas.drawOval(Rect.fromPoints(a, b), stroke);
    case Tool.line:
      canvas.drawLine(a, b, stroke);
    case Tool.pen:
    case Tool.highlight:
      final path = Path()..moveTo(a.dx, a.dy);
      for (var i = 1; i < m.points.length - 1; i++) {
        final mid = Offset.lerp(m.points[i], m.points[i + 1], 0.5)!;
        path.quadraticBezierTo(m.points[i].dx, m.points[i].dy, mid.dx, mid.dy);
      }
      if (m.points.length > 1) path.lineTo(b.dx, b.dy);
      if (m.tool == Tool.highlight) {
        stroke
          ..color = m.color.withValues(alpha: 0.38)
          ..strokeWidth = m.width * 5
          ..strokeCap = StrokeCap.square;
      }
      canvas.drawPath(path, stroke);
    case Tool.text:
      final painter = TextPainter(
        text: TextSpan(
          text: m.text,
          style: TextStyle(
            color: m.color,
            fontSize: m.width * 6,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(color: _contrast(m.color).withValues(alpha: 0.55), blurRadius: m.width)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, a);
    case Tool.pixelate:
      final r = Rect.fromPoints(a, b);
      if (blocks != null) {
        canvas.save();
        canvas.clipRect(r);
        canvas.drawImageRect(
            blocks,
            Offset.zero & Size(blocks.width.toDouble(), blocks.height.toDouble()),
            Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
            Paint()..filterQuality = FilterQuality.none);
        canvas.restore();
      }
    case Tool.step:
      final radius = math.max(14.0, m.width * 4.5);
      canvas.drawCircle(a, radius, Paint()..color = m.color);
      canvas.drawCircle(a, radius, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.12);
      final label = TextPainter(
        text: TextSpan(
          text: '${m.number}',
          style: TextStyle(color: _contrast(m.color), fontSize: radius * 1.1, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, a - Offset(label.width / 2, label.height / 2));
    case Tool.crop:
      break;
  }
}

Color _contrast(Color c) => c.computeLuminance() > 0.55 ? const Color(0xFF16182E) : Colors.white;

/// The image, cropped to [crop], with the marks, as a new image.
Future<ui.Image> flatten(ui.Image image, ui.Image? blocks, List<Mark> marks, Rect crop) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.translate(-crop.left, -crop.top);
  paintShot(canvas, image, blocks, marks);
  return recorder.endRecording().toImage(crop.width.round(), crop.height.round());
}
