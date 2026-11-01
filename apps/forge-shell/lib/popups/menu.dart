// A Forge menu: the dock's and the desktop's right-click menus, and any
// other list of choices. Hover or arrow keys pick a row, click or Enter
// takes it.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

import 'style.dart';

class MenuSpec {
  MenuSpec.fromJson(Map<String, dynamic> m)
    : title = m['title'] as String?,
      items = [
        for (final i in m['items'] as List? ?? const [])
          MenuRow.fromJson(i as Map<String, dynamic>),
      ];

  MenuSpec({this.title, required this.items});

  final String? title;
  final List<MenuRow> items;
}

class MenuRow {
  MenuRow.fromJson(Map<String, dynamic> m)
    : id = m['id'] as String? ?? '',
      label = m['label'] as String? ?? '',
      icon = popupIcons[m['icon']],
      danger = m['danger'] == true,
      enabled = m['enabled'] != false,
      checked = m['checked'] as bool?,
      hint = m['hint'] as String?,
      separator = m['separator'] == true;

  MenuRow(
    this.id,
    this.label, {
    this.icon,
    this.danger = false,
    this.enabled = true,
    this.checked,
    this.hint,
  }) : separator = false;

  MenuRow.separator()
    : id = '',
      label = '',
      icon = null,
      danger = false,
      enabled = false,
      checked = null,
      hint = null,
      separator = true;

  final String id;
  final String label;
  final IconData? icon;
  final bool danger;
  final bool enabled;
  final bool? checked;
  final String? hint;
  final bool separator;

  bool get pickable => !separator && enabled;
}

class MenuCard extends StatefulWidget {
  const MenuCard({
    super.key,
    required this.palette,
    required this.spec,
    required this.onPick,
  });

  final ForgePalette palette;
  final MenuSpec spec;

  /// The row's id; '' when closed without picking.
  final ValueChanged<String> onPick;

  @override
  State<MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<MenuCard> {
  int _selected = -1;
  final _focus = FocusNode();

  List<MenuRow> get _rows => widget.spec.items;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _move(int by) {
    if (!_rows.any((r) => r.pickable)) return;
    var i = _selected;
    do {
      i = (i + by) % _rows.length;
      if (i < 0) i += _rows.length;
    } while (!_rows[i].pickable);
    setState(() => _selected = i);
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.tab) {
      _move(1);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _move(-1);
    } else if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.space) {
      if (_selected >= 0 && _rows[_selected].pickable) {
        widget.onPick(_rows[_selected].id);
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final title = widget.spec.title;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _key,
      child: PopupCard(
        palette: p,
        padding: const EdgeInsets.all(5),
        radius: 13,
        child: IntrinsicWidth(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null && title.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(11, 7, 11, 5),
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.dimText,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                for (final (i, row) in _rows.indexed)
                  row.separator
                      ? Container(
                          height: 1,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          color: p.text.withValues(alpha: 0.1),
                        )
                      : _Row(
                          palette: p,
                          row: row,
                          selected: i == _selected,
                          onHover: () => setState(() => _selected = i),
                          onTap: () => widget.onPick(row.id),
                        ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.palette,
    required this.row,
    required this.selected,
    required this.onHover,
    required this.onTap,
  });

  final ForgePalette palette;
  final MenuRow row;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final fg = !row.enabled
        ? p.dimText.withValues(alpha: 0.6)
        : row.danger
        ? p.negative
        : p.text;
    return MouseRegion(
      cursor: row.enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) {
        if (row.enabled) onHover();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: row.enabled ? onTap : null,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? (row.danger ? p.negative : p.accent).withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: row.checked == true
                    ? Icon(Icons.check_rounded, size: 16, color: p.accent)
                    : row.icon != null
                    ? Icon(row.icon, size: 16, color: fg)
                    : null,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  row.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (row.hint != null) ...[
                const SizedBox(width: 16),
                Text(
                  row.hint!,
                  style: TextStyle(color: p.dimText, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
