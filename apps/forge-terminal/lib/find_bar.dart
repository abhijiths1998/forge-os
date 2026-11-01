// Find in the scrollback (Ctrl+Shift+F): every match highlighted, Enter and
// Shift+Enter step through them and scroll each into view.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:xterm/xterm.dart';

import 'session.dart';

class FindBar extends StatefulWidget {
  const FindBar({
    super.key,
    required this.palette,
    required this.session,
    required this.lineHeight,
    required this.onClose,
  });

  final ForgePalette palette;
  final Session session;
  final double lineHeight;
  final VoidCallback onClose;

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final List<(int, int, int)> _hits = []; // line, start, end
  final List<TerminalHighlight> _marks = [];
  int _current = -1;
  bool _caseSensitive = false;

  @override
  void initState() {
    super.initState();
    // Start from the selection, if there is one.
    final sel = widget.session.controller.selection;
    if (sel != null) {
      final t = widget.session.terminal.buffer.getText(sel).trim();
      if (t.isNotEmpty && !t.contains('\n')) _text.text = t;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
      _search();
    });
  }

  @override
  void dispose() {
    _clear();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _clear() {
    for (final m in _marks) {
      m.dispose();
    }
    _marks.clear();
    _hits.clear();
    _current = -1;
  }

  void _search() {
    _clear();
    final q = _text.text;
    if (q.isEmpty) {
      setState(() {});
      return;
    }
    final buffer = widget.session.terminal.buffer;
    final needle = _caseSensitive ? q : q.toLowerCase();
    for (var y = 0; y < buffer.lines.length; y++) {
      var line = buffer.lines[y].getText();
      if (!_caseSensitive) line = line.toLowerCase();
      var at = line.indexOf(needle);
      while (at >= 0) {
        _hits.add((y, at, at + needle.length));
        at = line.indexOf(needle, at + needle.length);
      }
    }
    for (final (y, s, e) in _hits) {
      _marks.add(widget.session.controller.highlight(
        p1: buffer.createAnchor(s, y),
        p2: buffer.createAnchor(e, y),
        color: const Color(0x66F6CFA8),
      ));
    }
    // Start from the last match: the newest output.
    if (_hits.isNotEmpty) _go(_hits.length - 1);
    setState(() {});
  }

  void _go(int i) {
    if (_hits.isEmpty) return;
    _current = i % _hits.length;
    final (y, s, e) = _hits[_current];
    final buffer = widget.session.terminal.buffer;
    widget.session.controller.setSelection(buffer.createAnchor(s, y), buffer.createAnchor(e, y));
    final scroll = widget.session.scroll;
    if (scroll.hasClients) {
      final target = y * widget.lineHeight - scroll.position.viewportDimension / 2;
      scroll.jumpTo(target.clamp(0, scroll.position.maxScrollExtent));
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Material(
      color: p.surface,
      elevation: 6,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_rounded, size: 18, color: p.dimText),
          const SizedBox(width: 8),
          SizedBox(
            width: 220,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
                const SingleActivator(LogicalKeyboardKey.enter): () => _go(_current - 1),
                const SingleActivator(LogicalKeyboardKey.enter, shift: true): () => _go(_current + 1),
              },
              child: TextField(
                controller: _text,
                focusNode: _focus,
                onChanged: (_) => _search(),
                style: TextStyle(color: p.text, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Find',
                  hintStyle: TextStyle(color: p.dimText),
                ),
              ),
            ),
          ),
          Text(
            _text.text.isEmpty ? '' : _hits.isEmpty ? 'None' : '${_current + 1} of ${_hits.length}',
            style: TextStyle(color: p.dimText, fontSize: 12),
          ),
          const SizedBox(width: 4),
          _toggle(p, 'Aa', _caseSensitive, () {
            _caseSensitive = !_caseSensitive;
            _search();
          }),
          IconButton(
            iconSize: 18,
            tooltip: 'Previous (Enter)',
            icon: Icon(Icons.keyboard_arrow_up_rounded, color: p.text),
            onPressed: _hits.isEmpty ? null : () => _go(_current - 1),
          ),
          IconButton(
            iconSize: 18,
            tooltip: 'Next (Shift+Enter)',
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: p.text),
            onPressed: _hits.isEmpty ? null : () => _go(_current + 1),
          ),
          IconButton(
            iconSize: 18,
            tooltip: 'Close (Esc)',
            icon: Icon(Icons.close_rounded, color: p.text),
            onPressed: widget.onClose,
          ),
        ]),
      ),
    );
  }

  Widget _toggle(ForgePalette p, String label, bool on, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: on ? p.accent.withValues(alpha: 0.3) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label, style: TextStyle(color: p.text, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      );
}
