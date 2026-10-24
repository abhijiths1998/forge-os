// Forge Shot's editor: a screenshot to mark up and crop, then copy or save.
// Tools (and their keys): arrow A, box R, ellipse O, line L, pen P,
// highlighter H, text T, pixelate B, numbered step N, crop C. Ctrl+Z undoes,
// Ctrl+Shift+Z redoes, Ctrl+C copies, Ctrl+S saves (over the file if it's
// already in the Screenshots folder, else as a new one), Ctrl+Shift+S asks
// where.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

import 'marks.dart';
import 'native.dart';
import 'store.dart';

class Editor extends StatefulWidget {
  const Editor({super.key, required this.image, required this.path, required this.palette});

  final ui.Image image;
  final String path;
  final ForgePalette palette;

  @override
  State<Editor> createState() => _EditorState();
}

class _Snapshot {
  _Snapshot(this.marks, this.crop);
  final List<Mark> marks;
  final Rect crop;
}

class _EditorState extends State<Editor> {
  final _focus = FocusNode();
  ui.Image? _blocks;
  List<Mark> _marks = [];
  late Rect _crop;
  final _undo = <_Snapshot>[];
  final _redo = <_Snapshot>[];

  Tool _tool = Tool.arrow;
  late Color _colour;
  double _width = 6;
  Mark? _drawing;
  Rect? _cropping;

  // A text being typed, where it'll go.
  Offset? _textAt;
  final _textController = TextEditingController();
  final _textFocus = FocusNode();

  double _scale = 1; // screen px per image px
  String _status = '';

  static const _colours = [
    Color(0xFFFF4D5E), Color(0xFFFF9F43), Color(0xFFFFD43B), Color(0xFF3FD68A),
    Color(0xFF4DABF7), Color(0xFFB57BFF), Color(0xFFFFFFFF), Color(0xFF16182E), //
  ];
  static const _widths = {'Thin': 3.0, 'Medium': 6.0, 'Thick': 11.0};

  Rect get _full => Offset.zero & Size(widget.image.width.toDouble(), widget.image.height.toDouble());

  @override
  void initState() {
    super.initState();
    _crop = _full;
    _colour = _colours.first;
    pixelated(widget.image).then((b) => setState(() => _blocks = b));
  }

  void _remember() {
    _undo.add(_Snapshot(List.of(_marks), _crop));
    _redo.clear();
  }

  void _undoOne() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(_Snapshot(List.of(_marks), _crop));
      final s = _undo.removeLast();
      _marks = s.marks;
      _crop = s.crop;
    });
  }

  void _redoOne() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(_Snapshot(List.of(_marks), _crop));
      final s = _redo.removeLast();
      _marks = s.marks;
      _crop = s.crop;
    });
  }

  Offset _toImage(Offset p) => p / _scale + _crop.topLeft;

  // --- Drawing ---------------------------------------------------------------

  void _start(Offset p) {
    _commitText();
    final at = _toImage(p);
    if (_tool == Tool.text) {
      setState(() {
        _textAt = at;
        _textController.clear();
      });
      _textFocus.requestFocus();
      return;
    }
    if (_tool == Tool.step) {
      _remember();
      setState(() => _marks.add(Mark(
            tool: Tool.step, color: _colour, width: _width, points: [at],
            number: _marks.where((m) => m.tool == Tool.step).length + 1)));
      return;
    }
    if (_tool == Tool.crop) {
      _cropStart = at;
      setState(() => _cropping = Rect.fromPoints(at, at));
      return;
    }
    setState(() => _drawing = Mark(tool: _tool, color: _colour, width: _width, points: [at, at]));
  }

  void _update(Offset p) {
    final at = _toImage(p);
    final clamped = Offset(at.dx.clamp(_full.left, _full.right), at.dy.clamp(_full.top, _full.bottom));
    if (_cropping != null) {
      setState(() => _cropping = Rect.fromPoints(_cropStart!, clamped));
      return;
    }
    final d = _drawing;
    if (d == null) return;
    setState(() {
      if (d.tool == Tool.pen || d.tool == Tool.highlight) {
        d.points.add(at);
      } else {
        d.points[d.points.length - 1] = at;
      }
    });
  }

  Offset? _cropStart;

  void _end() {
    if (_cropping != null) {
      final r = _cropping!.intersect(_full);
      if (r.width >= 8 && r.height >= 8) {
        _remember();
        setState(() => _crop = Rect.fromLTRB(r.left.roundToDouble(), r.top.roundToDouble(),
            r.right.roundToDouble(), r.bottom.roundToDouble()));
      }
      setState(() => _cropping = null);
      return;
    }
    final d = _drawing;
    if (d == null) return;
    final size = (d.points.last - d.points.first).distance;
    if (size > 3 || d.points.length > 2) {
      _remember();
      _marks.add(d);
    }
    setState(() => _drawing = null);
  }

  void _commitText() {
    final at = _textAt;
    final text = _textController.text.trim();
    if (at == null) return;
    setState(() {
      if (text.isNotEmpty) {
        _remember();
        _marks.add(Mark(tool: Tool.text, color: _colour, width: _width, points: [at], text: text));
      }
      _textAt = null;
    });
    _focus.requestFocus();
  }

  // --- Output ----------------------------------------------------------------

  Future<Uint8List> _png() async => Store.png(await flatten(widget.image, _blocks, _marks, _crop));

  Future<String> _temp(Uint8List bytes) async {
    final dir = Directory('${Platform.environment['XDG_RUNTIME_DIR'] ?? Directory.systemTemp.path}/forge-shot')
      ..createSync(recursive: true);
    final f = File('${dir.path}/edited.png');
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  void _say(String s) => setState(() => _status = s);

  Future<void> _copy() async {
    _commitText();
    final ok = await Native.copyImage(await _temp(await _png()));
    _say(ok ? 'Copied' : 'Couldn\'t copy');
  }

  Future<void> _copyText() async {
    _commitText();
    _say('Reading the text…');
    try {
      final text = await Store.text(await _temp(await _png()));
      if (text.isEmpty) return _say('No text found');
      await Native.copyText(text);
      _say('Text copied (${text.split(RegExp(r'\s+')).length} words)');
    } catch (e) {
      _say('$e');
    }
  }

  Future<void> _save() async {
    _commitText();
    final bytes = await _png();
    final folder = (await Store.folder()).path;
    if (widget.path.startsWith('$folder/')) {
      await File(widget.path).writeAsBytes(bytes, flush: true);
      _say('Saved');
    } else {
      final f = await Store.save(bytes);
      _say('Saved as ${f.uri.pathSegments.last}');
    }
  }

  Future<void> _saveAs() async {
    _commitText();
    final start = '${(await Store.folder()).path}/${Store.fileName()}';
    ProcessResult r;
    try {
      r = await Process.run('kdialog', ['--getsavefilename', start, 'image/png', '--title', 'Save screenshot']);
    } on ProcessException {
      return _say('Saving elsewhere needs kdialog');
    }
    final path = (r.stdout as String).trim();
    if (r.exitCode != 0 || path.isEmpty) return;
    await File(path.endsWith('.png') ? path : '$path.png').writeAsBytes(await _png(), flush: true);
    _say('Saved to $path');
  }

  // --- Keys ------------------------------------------------------------------

  static final _toolKeys = {
    LogicalKeyboardKey.keyA: Tool.arrow, LogicalKeyboardKey.keyR: Tool.rect, LogicalKeyboardKey.keyO: Tool.ellipse,
    LogicalKeyboardKey.keyL: Tool.line, LogicalKeyboardKey.keyP: Tool.pen, LogicalKeyboardKey.keyH: Tool.highlight,
    LogicalKeyboardKey.keyT: Tool.text, LogicalKeyboardKey.keyB: Tool.pixelate, LogicalKeyboardKey.keyN: Tool.step,
    LogicalKeyboardKey.keyC: Tool.crop, //
  };

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (_textAt != null || (e is! KeyDownEvent && e is! KeyRepeatEvent)) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (ctrl && k == LogicalKeyboardKey.keyZ) {
      shift ? _redoOne() : _undoOne();
    } else if (ctrl && k == LogicalKeyboardKey.keyY) {
      _redoOne();
    } else if (ctrl && k == LogicalKeyboardKey.keyC) {
      _copy();
    } else if (ctrl && k == LogicalKeyboardKey.keyS) {
      shift ? _saveAs() : _save();
    } else if (!ctrl && _toolKeys.containsKey(k)) {
      setState(() => _tool = _toolKeys[k]!);
    } else if (k == LogicalKeyboardKey.escape && _crop != _full && _tool == Tool.crop) {
      _remember();
      setState(() => _crop = _full);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // --- UI ------------------------------------------------------------------------

  static const _toolInfo = [
    (Tool.arrow, Icons.north_east_rounded, 'Arrow (A)'),
    (Tool.rect, Icons.crop_square_rounded, 'Box (R)'),
    (Tool.ellipse, Icons.circle_outlined, 'Ellipse (O)'),
    (Tool.line, Icons.horizontal_rule_rounded, 'Line (L)'),
    (Tool.pen, Icons.edit_rounded, 'Pen (P)'),
    (Tool.highlight, Icons.border_color_rounded, 'Highlighter (H)'),
    (Tool.text, Icons.title_rounded, 'Text (T)'),
    (Tool.pixelate, Icons.blur_on_rounded, 'Pixelate, to hide things (B)'),
    (Tool.step, Icons.looks_one_rounded, 'Numbered step (N)'),
    (Tool.crop, Icons.crop_rounded, 'Crop (C); Esc: uncrop'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _key,
      child: Scaffold(
        backgroundColor: p.window,
        body: Column(children: [
          _toolbar(p),
          Expanded(child: _canvas(p)),
          _statusBar(p),
        ]),
      ),
    );
  }

  Widget _toolbar(ForgePalette p) {
    Widget sep() => Container(width: 1, height: 26, margin: const EdgeInsets.symmetric(horizontal: 8), color: p.rim);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      color: p.sidebar,
      child: Row(children: [
        for (final (tool, icon, tip) in _toolInfo)
          _ToolButton(
            palette: p, icon: icon, tooltip: tip, selected: _tool == tool,
            onTap: () {
              _commitText();
              setState(() => _tool = tool);
            },
          ),
        sep(),
        for (final c in _colours)
          GestureDetector(
            onTap: () => setState(() => _colour = c),
            child: Container(
              width: 22, height: 22,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: c, shape: BoxShape.circle,
                border: Border.all(color: c == _colour ? p.accent : p.rim, width: c == _colour ? 3 : 1),
              ),
            ),
          ),
        sep(),
        for (final w in _widths.entries)
          Tooltip(
            message: w.key,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _width = w.value),
              child: Container(
                width: 30, height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _width == w.value ? p.accent.withValues(alpha: 0.2) : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Container(width: 6 + w.value, height: 6 + w.value,
                    decoration: BoxDecoration(color: p.text, shape: BoxShape.circle)),
              ),
            ),
          ),
        sep(),
        _ToolButton(palette: p, icon: Icons.undo_rounded, tooltip: 'Undo (Ctrl+Z)', onTap: _undo.isEmpty ? null : _undoOne),
        _ToolButton(palette: p, icon: Icons.redo_rounded, tooltip: 'Redo (Ctrl+Shift+Z)', onTap: _redo.isEmpty ? null : _redoOne),
        const Spacer(),
        _ToolButton(palette: p, icon: Icons.text_snippet_rounded, tooltip: 'Copy the text in it', onTap: _copyText),
        const SizedBox(width: 6),
        PillButton(palette: p, label: 'Copy', icon: Icons.content_copy_rounded, onTap: _copy),
        const SizedBox(width: 6),
        PillButton(palette: p, label: 'Save as…', onTap: _saveAs),
        const SizedBox(width: 6),
        PillButton(palette: p, label: 'Save', icon: Icons.save_alt_rounded, filled: true, onTap: _save),
      ]),
    );
  }

  Widget _canvas(ForgePalette p) {
    return LayoutBuilder(builder: (context, box) {
      const pad = 28.0;
      _scale = math.min(1.0, math.min((box.maxWidth - 2 * pad) / _crop.width, (box.maxHeight - 2 * pad) / _crop.height));
      final size = _crop.size * _scale;
      return Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 8))]),
                child: MouseRegion(
                  cursor: _tool == Tool.text ? SystemMouseCursors.text : SystemMouseCursors.precise,
                  child: GestureDetector(
                    onPanStart: (d) => _start(d.localPosition),
                    onPanUpdate: (d) => _update(d.localPosition),
                    onPanEnd: (_) => _end(),
                    onTapUp: (d) {
                      if (_tool == Tool.text || _tool == Tool.step) _start(d.localPosition);
                    },
                    child: ClipRect(
                      child: CustomPaint(
                        painter: _CanvasPainter(
                          image: widget.image, blocks: _blocks, marks: _marks, drawing: _drawing,
                          crop: _crop, scale: _scale, cropping: _cropping, accent: p.accent),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_textAt != null) _textField(),
          ]),
        ),
      );
    });
  }

  Widget _textField() {
    final at = (_textAt! - _crop.topLeft) * _scale;
    return Positioned(
      left: at.dx,
      top: at.dy - 6,
      width: 320,
      child: TextField(
        controller: _textController,
        focusNode: _textFocus,
        autofocus: true,
        style: TextStyle(color: _colour, fontSize: _width * 6 * _scale, fontWeight: FontWeight.w700),
        cursorColor: _colour,
        decoration: const InputDecoration(border: InputBorder.none, isDense: true, hintText: 'Type, then Enter'),
        onSubmitted: (_) => _commitText(),
        onTapOutside: (_) => _commitText(),
      ),
    );
  }

  Widget _statusBar(ForgePalette p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(children: [
        Text('${_crop.width.round()} × ${_crop.height.round()}  ·  ${(_scale * 100).round()}%',
            style: TextStyle(color: p.dimText, fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()])),
        const Spacer(),
        Text(_status, style: TextStyle(color: p.text, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.palette, required this.icon, required this.tooltip, this.selected = false, this.onTap});

  final ForgePalette palette;
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          width: 36, height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? p.accent : null,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 20,
              color: selected ? p.onAccent : (onTap == null ? p.dimText.withValues(alpha: 0.5) : p.text)),
        ),
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter({
    required this.image, required this.blocks, required this.marks, required this.drawing,
    required this.crop, required this.scale, required this.cropping, required this.accent,
  });

  final ui.Image image;
  final ui.Image? blocks;
  final List<Mark> marks;
  final Mark? drawing;
  final Rect crop;
  final double scale;
  final Rect? cropping;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    canvas.translate(-crop.left, -crop.top);
    paintShot(canvas, image, blocks, [...marks, ?drawing]);
    if (cropping != null) {
      final shade = Path()
        ..addRect(crop)
        ..addRect(cropping!)
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(shade, Paint()..color = const Color(0x88000000));
      canvas.drawRect(cropping!, Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 / scale);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CanvasPainter old) => true;
}
