// The folder's contents, as icons or as a list. Click selects (Ctrl adds,
// Shift extends), double-click opens, items drag onto folders.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

import 'controller.dart';
import 'fs.dart';
import 'icons.dart';
import 'thumbs.dart';

typedef MenuAt = void Function(Offset position, int? index);

class Content extends StatelessWidget {
  const Content({super.key, required this.c, required this.palette, required this.places, required this.onMenu, required this.onColumns, required this.scroll});

  final FilesController c;
  final ForgePalette palette;
  final List<Place> places;
  final MenuAt onMenu;
  final ValueChanged<int> onColumns;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    if (c.error != null) return _empty(p, Icons.lock_rounded, c.error!);
    if (c.entries.isEmpty && !c.loading) {
      if (c.searching) return _empty(p, Icons.search_off_rounded, 'Looking for "${c.query}"…');
      if (c.query.isNotEmpty) return _empty(p, Icons.search_off_rounded, 'Nothing called "${c.query}"');
      if (c.inTrash) return _empty(p, Icons.delete_outline_rounded, 'The trash is empty');
      return GestureDetector(
        onSecondaryTapDown: (d) => onMenu(d.globalPosition, null),
        child: _empty(p, Icons.folder_open_rounded, 'This folder is empty'),
      );
    }
    final body = c.view == ViewMode.grid ? _grid(context) : _list(context);
    // A click on the empty space clears the selection; right-click there
    // is the folder's own menu.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: c.clearSelection,
      onSecondaryTapDown: (d) => onMenu(d.globalPosition, null),
      child: Scrollbar(controller: scroll, child: body),
    );
  }

  Widget _empty(ForgePalette p, IconData icon, String text) => Container(
        color: Colors.transparent,
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: p.dimText.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: p.dimText, fontSize: 14)),
        ]),
      );

  Widget _grid(BuildContext context) {
    final tile = 112.0 * c.zoom;
    return LayoutBuilder(builder: (context, box) {
      final columns = ((box.maxWidth - 24) / tile).floor().clamp(1, 100);
      WidgetsBinding.instance.addPostFrameCallback((_) => onColumns(columns));
      return GridView.builder(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: tile * 1.12,
        ),
        itemCount: c.entries.length,
        itemBuilder: (context, i) => _Item(
          c: c,
          index: i,
          palette: palette,
          places: places,
          onMenu: onMenu,
          builder: (selected, hover, drop) => _gridTile(c.entries[i], selected, hover, drop, tile),
        ),
      );
    });
  }

  Widget _gridTile(Entry e, bool selected, bool hover, bool drop, double tile) {
    final p = palette;
    final icon = tile * 0.52;
    return Container(
      margin: const EdgeInsets.all(3),
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
      decoration: BoxDecoration(
        color: drop
            ? p.accent.withValues(alpha: 0.35)
            : selected
                ? p.accent.withValues(alpha: 0.22)
                : hover
                    ? p.hover
                    : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        Opacity(
          opacity: e.hidden || c.isCut(e.path) ? 0.55 : 1,
          child: FileThumb(entry: e, size: icon, accent: p.accent, badge: e.isDir ? folderBadge(e.path, places) : null),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Text(
            e.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.text, fontSize: 12.5, height: 1.25, fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
          ),
        ),
      ]),
    );
  }

  Widget _list(BuildContext context) {
    final p = palette;
    final showWhere = c.inTrash || c.query.isNotEmpty;
    final row = 34.0 * c.zoom.clamp(0.8, 1.6);
    TextStyle head = TextStyle(color: p.dimText, fontSize: 12, fontWeight: FontWeight.w600);
    Widget headCell(String label, SortBy? by, {int flex = 1, TextAlign align = TextAlign.left}) => Expanded(
          flex: flex,
          child: InkWell(
            onTap: by == null ? null : () => c.setSort(by),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              child: Text(
                '$label${c.sortBy == by ? (c.descending ? '  ↓' : '  ↑') : ''}',
                textAlign: align,
                style: head,
              ),
            ),
          ),
        );
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 0),
        child: Row(children: [
          SizedBox(width: row + 6),
          headCell('Name', SortBy.name, flex: 5),
          if (showWhere) headCell(c.inTrash ? 'From' : 'Where', null, flex: 4),
          headCell('Size', SortBy.size, flex: 2, align: TextAlign.right),
          headCell('Modified', SortBy.modified, flex: 3),
          headCell('Kind', SortBy.type, flex: 2),
        ]),
      ),
      Container(height: 1, color: p.rim, margin: const EdgeInsets.symmetric(horizontal: 18)),
      Expanded(
        child: ListView.builder(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 24),
          itemExtent: row,
          itemCount: c.entries.length,
          itemBuilder: (context, i) => _Item(
            c: c,
            index: i,
            palette: palette,
            places: places,
            onMenu: onMenu,
            builder: (selected, hover, drop) {
              final e = c.entries[i];
              final cell = TextStyle(color: p.dimText, fontSize: 12.5);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: drop
                      ? p.accent.withValues(alpha: 0.35)
                      : selected
                          ? p.accent.withValues(alpha: 0.22)
                          : hover
                              ? p.hover
                              : i.isOdd
                                  ? p.text.withValues(alpha: 0.02)
                                  : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Opacity(
                    opacity: e.hidden ? 0.55 : 1,
                    child: FileThumb(entry: e, size: row - 8, accent: p.accent, badge: null),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 5,
                    child: Text(e.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.text, fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
                  ),
                  if (showWhere)
                    Expanded(
                      flex: 4,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(pretty(c.inTrash ? dirname(e.trashOrigin ?? '') : dirname(e.path)),
                            overflow: TextOverflow.ellipsis, style: cell),
                      ),
                    ),
                  Expanded(
                    flex: 2,
                    child: Text(e.isDir ? '—' : sizeText(e.size), textAlign: TextAlign.right, style: cell),
                  ),
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(dateText(e.modified), overflow: TextOverflow.ellipsis, style: cell),
                    ),
                  ),
                  Expanded(flex: 2, child: Text(kindName(e), overflow: TextOverflow.ellipsis, style: cell)),
                ]),
              );
            },
          ),
        ),
      ),
    ]);
  }
}

/// One item, either view: selection, hover, double-click, drag source and
/// (for folders) drop target.
class _Item extends StatefulWidget {
  const _Item({required this.c, required this.index, required this.palette, required this.places, required this.onMenu, required this.builder});

  final FilesController c;
  final int index;
  final ForgePalette palette;
  final List<Place> places;
  final MenuAt onMenu;
  final Widget Function(bool selected, bool hover, bool drop) builder;

  @override
  State<_Item> createState() => _ItemState();
}

class _ItemState extends State<_Item> {
  bool _hover = false;
  DateTime? _lastTap;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final i = widget.index;
    final e = c.entries[i];
    final selected = c.selected.contains(e.path);

    Widget item(bool drop) => MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Listener(
            // Selection on pointer-down feels instant and lets a drag start
            // from an item that wasn't selected yet.
            onPointerDown: (ev) {
              if (ev.buttons != kPrimaryButton) return;
              final k = HardwareKeyboard.instance;
              final now = DateTime.now();
              final double = _lastTap != null && now.difference(_lastTap!) < const Duration(milliseconds: 400);
              _lastTap = now;
              if (double && !k.isControlPressed && !k.isShiftPressed) {
                _lastTap = null;
                c.open(e);
                return;
              }
              if (selected && !k.isControlPressed && !k.isShiftPressed && c.selected.length > 1) return;
              c.click(i, ctrl: k.isControlPressed, shift: k.isShiftPressed);
            },
            child: GestureDetector(
              onTap: () {}, // keeps the background's tap from clearing it
              onSecondaryTapDown: (d) {
                c.ensureSelected(i);
                widget.onMenu(d.globalPosition, i);
              },
              child: widget.builder(selected, _hover, drop),
            ),
          ),
        );

    final paths = selected ? c.selected.toList() : [e.path];
    final draggable = Draggable<List<String>>(
      data: paths,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragFeedback(entry: e, count: paths.length, palette: widget.palette),
      childWhenDragging: Opacity(opacity: 0.5, child: item(false)),
      child: e.isDir && !c.inTrash
          ? DragTarget<List<String>>(
              onWillAcceptWithDetails: (d) => !d.data.contains(e.path),
              onAcceptWithDetails: (d) => c.drop(d.data, e.path, copy: HardwareKeyboard.instance.isControlPressed),
              builder: (context, cand, _) => item(cand.isNotEmpty),
            )
          : item(false),
    );
    return draggable;
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.entry, required this.count, required this.palette});
  final Entry entry;
  final int count;
  final ForgePalette palette;

  @override
  Widget build(BuildContext context) => Transform.translate(
        offset: const Offset(8, 8),
        child: Material(
          color: palette.surface,
          borderRadius: BorderRadius.circular(12),
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              FileIcon(entry: entry, size: 28, accent: palette.accent),
              const SizedBox(width: 8),
              Text(count == 1 ? entry.name : '$count items',
                  style: TextStyle(color: palette.text, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}
