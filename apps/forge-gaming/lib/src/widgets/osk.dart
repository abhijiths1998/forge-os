// Typing with a pad: a text field that, on A, opens an on-screen keyboard
// whose keys are ordinary focusable buttons (so the d-pad moves over them).
// Y deletes, X types a space, Start finishes, B closes, LB/RB move the cursor.
import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../pad.dart';
import 'glass.dart';

/// A glass text field. Keyboard users type into it as usual; with a pad, A
/// on the field opens [showPadKeyboard].
class GlassField extends StatefulWidget {
  const GlassField({
    super.key,
    required this.palette,
    required this.controller,
    this.label,
    this.hint,
    this.icon,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.focusNode,
    this.trailing,
    this.maxLines = 1,
  });

  final ForgePalette palette;
  final TextEditingController controller;
  final String? label;
  final String? hint;
  final IconData? icon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final FocusNode? focusNode;
  final Widget? trailing;
  final int maxLines;

  @override
  State<GlassField> createState() => _GlassFieldState();
}

class _GlassFieldState extends State<GlassField> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() => setState(() => _focused = _focus.hasFocus);

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  Future<void> _openKeyboard() async {
    final text = await showPadKeyboard(context,
        palette: widget.palette, initial: widget.controller.text, title: widget.label ?? widget.hint ?? '');
    if (text == null) return;
    widget.controller.text = text;
    widget.controller.selection = TextSelection.collapsed(offset: text.length);
    widget.onChanged?.call(text);
    widget.onSubmitted?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return PadShortcuts(
      bindings: padBindings({PadButton.a: _openKeyboard}),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(widget.label!,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.dimText)),
          ),
        FocusGlow(
          palette: p,
          focused: _focused,
          radius: 14,
          scale: 1.0,
          child: Container(
            color: Colors.white.withValues(alpha: _focused ? 0.14 : (p.dark ? 0.06 : 0.3)),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 18, color: p.dimText),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  maxLines: widget.maxLines,
                  minLines: 1,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  style: TextStyle(color: p.text, fontSize: 14),
                  cursorColor: p.accent,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: TextStyle(color: p.dimText),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
              ?widget.trailing,
            ]),
          ),
        ),
      ]),
    );
  }
}

const _rows = [
  '1234567890',
  'qwertyuiop',
  'asdfghjkl\'',
  'zxcvbnm,.-',
];

/// Shows the pad keyboard; returns the text, or null when cancelled.
Future<String?> showPadKeyboard(
  BuildContext context, {
  required ForgePalette palette,
  String initial = '',
  String title = '',
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close keyboard',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, _) => _PadKeyboard(palette: palette, initial: initial, title: title),
    transitionBuilder: (context, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 0.25), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: FadeTransition(opacity: anim, child: child),
    ),
  );
}

class _PadKeyboard extends StatefulWidget {
  const _PadKeyboard({required this.palette, required this.initial, required this.title});
  final ForgePalette palette;
  final String initial;
  final String title;

  @override
  State<_PadKeyboard> createState() => _PadKeyboardState();
}

class _PadKeyboardState extends State<_PadKeyboard> {
  late String _text = widget.initial;
  bool _shift = false;

  void _type(String s) => setState(() {
        _text += _shift ? s.toUpperCase() : s;
        _shift = false;
      });
  void _backspace() => setState(() {
        if (_text.isNotEmpty) _text = _text.substring(0, _text.length - 1);
      });
  void _done() => Navigator.of(context).pop(_text);

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return PadShortcuts(
      bindings: padBindings({
        PadButton.y: _backspace,
        PadButton.x: () => _type(' '),
        PadButton.start: _done,
        PadButton.lt: () => setState(() => _shift = !_shift),
      }),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Material(
              type: MaterialType.transparency,
              child: Glass(
                palette: p,
                strength: 1.4,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (widget.title.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(widget.title,
                          style: TextStyle(color: p.dimText, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('$_text▏', style: TextStyle(color: p.text, fontSize: 20)),
                  ),
                  const SizedBox(height: 14),
                  FocusTraversalGroup(
                    child: Column(children: [
                      for (final (r, row) in _rows.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(children: [
                            for (final (c, ch) in row.split('').indexed)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 3),
                                  child: _Key(
                                    palette: p,
                                    label: _shift ? ch.toUpperCase() : ch,
                                    autofocus: r == 1 && c == 0,
                                    onTap: () => _type(ch),
                                  ),
                                ),
                              ),
                          ]),
                        ),
                      Row(children: [
                        Expanded(
                            flex: 2,
                            child: _Key(
                                palette: p,
                                label: '⇧ Shift',
                                highlight: _shift,
                                onTap: () => setState(() => _shift = !_shift))),
                        const SizedBox(width: 6),
                        Expanded(flex: 4, child: _Key(palette: p, label: 'Space', onTap: () => _type(' '))),
                        const SizedBox(width: 6),
                        Expanded(flex: 2, child: _Key(palette: p, label: '⌫', onTap: _backspace)),
                        const SizedBox(width: 6),
                        Expanded(flex: 2, child: _Key(palette: p, label: 'Done', highlight: true, onTap: _done)),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  PadHintBar(palette: p, hints: const [
                    PadHint(PadButton.a, 'Type'),
                    PadHint(PadButton.y, 'Delete'),
                    PadHint(PadButton.x, 'Space'),
                    PadHint(PadButton.lt, 'Shift'),
                    PadHint(PadButton.start, 'Done'),
                    PadHint(PadButton.b, 'Cancel'),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.palette,
    required this.label,
    required this.onTap,
    this.autofocus = false,
    this.highlight = false,
  });

  final ForgePalette palette;
  final String label;
  final VoidCallback onTap;
  final bool autofocus;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Focusable(
        autofocus: autofocus,
        onActivate: onTap,
        builder: (context, focused, hovered) => FocusGlow(
          palette: palette,
          focused: focused,
          hovered: hovered,
          radius: 10,
          scale: 1.08,
          child: Container(
            height: 46,
            alignment: Alignment.center,
            color: highlight
                ? palette.accent.withValues(alpha: 0.8)
                : Colors.white.withValues(alpha: focused ? 0.25 : 0.08),
            child: Text(label,
                style: TextStyle(color: palette.text, fontSize: 17, fontWeight: FontWeight.w600)),
          ),
        ),
      );
}
