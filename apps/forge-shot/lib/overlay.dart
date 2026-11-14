// The region picker, over the whole screen: the screen as it was when the
// key was pressed, dimmed except the selection. Drag to select (a loupe
// shows the pixels under the cursor), then adjust: drag the handles or the
// selection, arrows nudge it (Shift: 10px). Enter or a double-click saves
// and copies it; the toolbar under it also annotates it or copies its text.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

enum ShotAction { saveAndCopy, copy, save, edit, text }

class RegionOverlay extends StatefulWidget {
  const RegionOverlay({
    super.key,
    required this.image,
    required this.palette,
    required this.onDone,
    required this.onCancel,
  });

  final ui.Image image;
  final ForgePalette palette;

  /// The chosen part of the image, in the image's own pixels.
  final void Function(Rect region, ShotAction action) onDone;
  final VoidCallback onCancel;

  @override
  State<RegionOverlay> createState() => _RegionOverlayState();
}

enum _Drag { none, create, move, handle }

class _RegionOverlayState extends State<RegionOverlay> {
  Rect? _sel; // in this window's logical pixels
  Offset? _cursor;
  _Drag _drag = _Drag.none;
  int _handle = -1;
  Offset _anchor = Offset.zero;
  Rect _startSel = Rect.zero;
  Size _size = Size.zero;

  double get _scale => _size.width == 0 ? 1 : widget.image.width / _size.width;

  static const _handleRadius = 9.0;

  List<Offset> _handles(Rect r) => [
        r.topLeft, r.topCenter, r.topRight, r.centerRight,
        r.bottomRight, r.bottomCenter, r.bottomLeft, r.centerLeft, //
      ];

  Rect _clamp(Rect r) {
    final bounds = Offset.zero & _size;
    return Rect.fromLTRB(
      r.left.clamp(0, bounds.right), r.top.clamp(0, bounds.bottom),
      r.right.clamp(0, bounds.right), r.bottom.clamp(0, bounds.bottom), //
    );
  }

  void _down(Offset p) {
    final sel = _sel;
    if (sel != null) {
      final hs = _handles(sel);
      for (var i = 0; i < hs.length; i++) {
        if ((hs[i] - p).distance <= _handleRadius + 4) {
          _drag = _Drag.handle;
          _handle = i;
          _startSel = sel;
          return;
        }
      }
      if (sel.contains(p)) {
        _drag = _Drag.move;
        _anchor = p;
        _startSel = sel;
        return;
      }
    }
    _drag = _Drag.create;
    _anchor = p;
    setState(() => _sel = Rect.fromPoints(p, p));
  }

  void _moveTo(Offset p) {
    setState(() {
      _cursor = p;
      switch (_drag) {
        case _Drag.create:
          _sel = _clamp(Rect.fromPoints(_anchor, p));
        case _Drag.move:
          final d = p - _anchor;
          final moved = _startSel.shift(d);
          final dx = moved.left < 0 ? -moved.left : (moved.right > _size.width ? _size.width - moved.right : 0.0);
          final dy = moved.top < 0 ? -moved.top : (moved.bottom > _size.height ? _size.height - moved.bottom : 0.0);
          _sel = moved.shift(Offset(dx, dy));
        case _Drag.handle:
          var l = _startSel.left, t = _startSel.top, r = _startSel.right, b = _startSel.bottom;
          if ([0, 6, 7].contains(_handle)) l = p.dx;
          if ([2, 3, 4].contains(_handle)) r = p.dx;
          if ([0, 1, 2].contains(_handle)) t = p.dy;
          if ([4, 5, 6].contains(_handle)) b = p.dy;
          _sel = _clamp(Rect.fromLTRB(math.min(l, r), math.min(t, b), math.max(l, r), math.max(t, b)));
        case _Drag.none:
          break;
      }
    });
  }

  void _up() {
    setState(() {
      // A click without a drag isn't a selection.
      if (_drag == _Drag.create && _sel != null && (_sel!.width < 4 || _sel!.height < 4)) _sel = null;
      _drag = _Drag.none;
    });
  }

  void _finish(ShotAction action) {
    final sel = _sel ?? (Offset.zero & _size);
    final s = _scale;
    widget.onDone(
      Rect.fromLTRB((sel.left * s).roundToDouble(), (sel.top * s).roundToDouble(),
          (sel.right * s).roundToDouble(), (sel.bottom * s).roundToDouble()),
      action,
    );
  }

  static final _nudges = {
    LogicalKeyboardKey.arrowLeft: const Offset(-1, 0), LogicalKeyboardKey.arrowRight: const Offset(1, 0),
    LogicalKeyboardKey.arrowUp: const Offset(0, -1), LogicalKeyboardKey.arrowDown: const Offset(0, 1), //
  };

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final step = HardwareKeyboard.instance.isShiftPressed ? 10.0 : 1.0;
    if (k == LogicalKeyboardKey.escape) {
      widget.onCancel();
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _finish(ShotAction.saveAndCopy);
    } else if (ctrl && k == LogicalKeyboardKey.keyC) {
      _finish(ShotAction.copy);
    } else if (ctrl && k == LogicalKeyboardKey.keyS) {
      _finish(ShotAction.save);
    } else if (ctrl && k == LogicalKeyboardKey.keyA) {
      setState(() => _sel = Offset.zero & _size);
    } else if (!ctrl && k == LogicalKeyboardKey.keyE) {
      _finish(ShotAction.edit);
    } else if (!ctrl && k == LogicalKeyboardKey.keyT) {
      _finish(ShotAction.text);
    } else if (_sel != null && _nudges.containsKey(k)) {
      setState(() => _sel = _clamp(_sel!.shift(_nudges[k]! * step)));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return LayoutBuilder(builder: (context, box) {
      _size = box.biggest;
      final sel = _sel;
      final picking = sel == null || _drag == _Drag.create;
      return Focus(
        autofocus: true,
        onKeyEvent: _key,
        child: MouseRegion(
          cursor: _drag == _Drag.move ? SystemMouseCursors.grabbing : SystemMouseCursors.precise,
          onHover: (e) => setState(() => _cursor = e.localPosition),
          child: GestureDetector(
            onDoubleTap: sel != null ? () => _finish(ShotAction.saveAndCopy) : null,
            child: Listener(
              onPointerDown: (e) => _down(e.localPosition),
              onPointerMove: (e) => _moveTo(e.localPosition),
              onPointerUp: (_) => _up(),
              child: Stack(children: [
                Positioned.fill(child: RawImage(image: widget.image, fit: BoxFit.fill)),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ShadePainter(sel: sel, cursor: picking ? _cursor : null, accent: p.accent,
                        handles: sel != null && _drag != _Drag.create ? _handles(sel) : const []),
                  ),
                ),
                if (sel == null)
                  Center(
                    child: _Pill(
                      text: 'Drag to choose an area  ·  Enter: the whole screen  ·  Esc: cancel',
                    ),
                  ),
                if (sel != null) _sizeLabel(sel),
                if (sel != null && _drag == _Drag.none) _toolbar(sel, p),
                if (picking && _cursor != null) _loupe(_cursor!),
              ]),
            ),
          ),
        ),
      );
    });
  }

  Widget _sizeLabel(Rect sel) {
    final text = '${(sel.width * _scale).round()} × ${(sel.height * _scale).round()}';
    final top = sel.top > 34 ? sel.top - 30 : sel.top + 6;
    return Positioned(left: sel.left, top: top, child: _Pill(text: text, small: true));
  }

  Widget _toolbar(Rect sel, ForgePalette p) {
    const height = 46.0;
    const width = 5 * 44.0 + 12;
    final below = sel.bottom + 10 + height <= _size.height;
    final top = below ? sel.bottom + 10 : math.max(8.0, sel.top - 10 - height);
    final left = (sel.right - width).clamp(8.0, math.max(8.0, _size.width - width - 8)).toDouble();
    Widget button(IconData icon, String tip, ShotAction a) => IconButton(
          tooltip: tip,
          icon: Icon(icon, size: 21),
          color: Colors.white,
          onPressed: () => _finish(a),
        );
    return Positioned(
      left: left,
      top: top,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(color: const Color(0xE61A1C33), borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          button(Icons.content_copy_rounded, 'Copy  (Ctrl+C)', ShotAction.copy),
          button(Icons.save_alt_rounded, 'Save  (Ctrl+S)', ShotAction.save),
          button(Icons.draw_rounded, 'Annotate  (E)', ShotAction.edit),
          button(Icons.text_snippet_rounded, 'Copy the text in it  (T)', ShotAction.text),
          IconButton(
            tooltip: 'Cancel  (Esc)',
            icon: const Icon(Icons.close_rounded, size: 21),
            color: Colors.white70,
            onPressed: widget.onCancel,
          ),
        ]),
      ),
    );
  }

  /// The pixels around the cursor, magnified, with their position.
  Widget _loupe(Offset c) {
    const size = 128.0;
    final left = c.dx + 24 + size > _size.width ? c.dx - 24 - size : c.dx + 24;
    final top = c.dy + 24 + size + 26 > _size.height ? c.dy - 24 - size - 26 : c.dy + 24;
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Column(children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size / 2),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 12)],
            ),
            child: ClipOval(child: CustomPaint(painter: _LoupePainter(widget.image, c * _scale))),
          ),
          const SizedBox(height: 4),
          _Pill(text: '${(c.dx * _scale).round()}, ${(c.dy * _scale).round()}', small: true),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.small = false});

  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 16, vertical: small ? 3 : 9),
      decoration: BoxDecoration(color: const Color(0xD91A1C33), borderRadius: BorderRadius.circular(small ? 8 : 14)),
      child: Text(text,
          style: TextStyle(
              color: Colors.white, fontSize: small ? 12 : 14, fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }
}

/// The dim around the selection, its outline and handles, and guides
/// through the cursor while choosing.
class _ShadePainter extends CustomPainter {
  _ShadePainter({required this.sel, required this.cursor, required this.accent, required this.handles});

  final Rect? sel;
  final Offset? cursor;
  final Color accent;
  final List<Offset> handles;

  @override
  void paint(Canvas canvas, Size size) {
    final all = Offset.zero & size;
    final shade = Path()..addRect(all);
    if (sel != null) shade.addRect(sel!);
    shade.fillType = PathFillType.evenOdd;
    canvas.drawPath(shade, Paint()..color = const Color(0x73000000));
    if (cursor != null) {
      final guide = Paint()
        ..color = const Color(0x88FFFFFF)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(0, cursor!.dy), Offset(size.width, cursor!.dy), guide);
      canvas.drawLine(Offset(cursor!.dx, 0), Offset(cursor!.dx, size.height), guide);
    }
    if (sel != null) {
      canvas.drawRect(sel!, Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
      for (final h in handles) {
        canvas.drawCircle(h, 6, Paint()..color = Colors.white);
        canvas.drawCircle(h, 6, Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
      }
    }
  }

  @override
  bool shouldRepaint(_ShadePainter old) =>
      old.sel != sel || old.cursor != cursor || old.handles.length != handles.length;
}

class _LoupePainter extends CustomPainter {
  _LoupePainter(this.image, this.at);

  final ui.Image image;
  final Offset at; // in image pixels

  @override
  void paint(Canvas canvas, Size size) {
    const zoom = 8.0;
    final src = Rect.fromCenter(center: at, width: size.width / zoom, height: size.height / zoom);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    canvas.drawImageRect(image, src, Offset.zero & size, Paint()..filterQuality = FilterQuality.none);
    final c = size.center(Offset.zero);
    final cross = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..strokeWidth = 1;
    canvas.drawRect(Rect.fromCenter(center: c, width: zoom, height: zoom), cross..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_LoupePainter old) => old.at != at;
}
