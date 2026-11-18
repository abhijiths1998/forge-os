// The top bar: back/forward/up, the path as breadcrumbs (click the empty
// part or press Ctrl+L to type one), search, and the view and sort.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

import 'controller.dart';
import 'fs.dart';

class Toolbar extends StatefulWidget {
  const Toolbar({super.key, required this.c, required this.palette, required this.searchFocus, required this.pathEditing, required this.onPathEditing});

  final FilesController c;
  final ForgePalette palette;
  final FocusNode searchFocus;
  final bool pathEditing;
  final ValueChanged<bool> onPathEditing;

  @override
  State<Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<Toolbar> {
  final _search = TextEditingController();
  final _pathText = TextEditingController();
  final _pathFocus = FocusNode();

  @override
  void didUpdateWidget(Toolbar old) {
    super.didUpdateWidget(old);
    if (widget.pathEditing && !old.pathEditing) {
      _pathText.text = widget.c.inTrash ? trashFolder : widget.c.path;
      _pathText.selection = TextSelection(baseOffset: 0, extentOffset: _pathText.text.length);
      WidgetsBinding.instance.addPostFrameCallback((_) => _pathFocus.requestFocus());
    }
    if (widget.c.query.isEmpty && _search.text.isNotEmpty && !widget.searchFocus.hasFocus) _search.clear();
  }

  @override
  void dispose() {
    _search.dispose();
    _pathText.dispose();
    _pathFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final p = widget.palette;
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(children: [
        _Btn(p, Icons.arrow_back_rounded, 'Back (Alt+Left)', c.canBack ? c.back : null),
        _Btn(p, Icons.arrow_forward_rounded, 'Forward (Alt+Right)', c.canForward ? c.forward : null),
        _Btn(p, Icons.arrow_upward_rounded, 'Up (Alt+Up)', c.canUp ? c.up : null),
        const SizedBox(width: 6),
        Expanded(child: widget.pathEditing ? _pathField(p) : _crumbs(c, p)),
        const SizedBox(width: 8),
        SizedBox(width: 220, child: _searchField(c, p)),
        const SizedBox(width: 6),
        _Btn(
          p,
          c.view == ViewMode.grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
          c.view == ViewMode.grid ? 'List (Ctrl+2)' : 'Icons (Ctrl+1)',
          () => c.setView(c.view == ViewMode.grid ? ViewMode.list : ViewMode.grid),
        ),
        _menu(c, p),
      ]),
    );
  }

  Widget _pathField(ForgePalette p) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(10)),
        alignment: Alignment.centerLeft,
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => widget.onPathEditing(false)},
          child: TextField(
            controller: _pathText,
            focusNode: _pathFocus,
            style: TextStyle(color: p.text, fontSize: 13.5),
            decoration: const InputDecoration(isDense: true, border: InputBorder.none),
            onSubmitted: (t) {
              widget.onPathEditing(false);
              widget.c.go(t.trim() == trashFolder ? trashFolder : t.trim());
            },
            onTapOutside: (_) => widget.onPathEditing(false),
          ),
        ),
      );

  Widget _crumbs(FilesController c, ForgePalette p) {
    final parts = <(String, String)>[];
    if (c.inTrash) {
      parts.add(('Trash', trashFolder));
    } else {
      final inHome = c.path == home || c.path.startsWith('$home/');
      var acc = inHome ? home : '';
      parts.add(inHome ? ('Home', home) : ('/', '/'));
      final rest = inHome ? c.path.substring(home.length) : c.path;
      for (final seg in rest.split('/').where((s) => s.isNotEmpty)) {
        acc = acc == '/' ? '/$seg' : '$acc/$seg';
        parts.add((seg, acc));
      }
    }
    return GestureDetector(
      onTap: () => widget.onPathEditing(true),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(children: [
                for (var i = 0; i < parts.length; i++) ...[
                  if (i > 0) Icon(Icons.chevron_right_rounded, size: 16, color: p.dimText),
                  DragTarget<List<String>>(
                    onWillAcceptWithDetails: (d) => !c.inTrash && !d.data.contains(parts[i].$2),
                    onAcceptWithDetails: (d) =>
                        c.drop(d.data, parts[i].$2, copy: HardwareKeyboard.instance.isControlPressed),
                    builder: (context, cand, _) => InkWell(
                      onTap: () => c.go(parts[i].$2),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: cand.isNotEmpty ? p.accent.withValues(alpha: 0.3) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(parts[i].$1,
                            style: TextStyle(
                              color: i == parts.length - 1 ? p.text : p.dimText,
                              fontSize: 13.5,
                              fontWeight: i == parts.length - 1 ? FontWeight.w600 : FontWeight.w500,
                            )),
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          ),
          // The empty part of the bar: click to type a path.
          const SizedBox(width: 24),
        ]),
      ),
    );
  }

  Widget _searchField(FilesController c, ForgePalette p) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(Icons.search_rounded, size: 18, color: p.dimText),
          const SizedBox(width: 6),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () {
                  _search.clear();
                  c.clearSearch();
                  widget.searchFocus.unfocus();
                },
              },
              child: TextField(
                controller: _search,
                focusNode: widget.searchFocus,
                style: TextStyle(color: p.text, fontSize: 13.5),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: c.inTrash ? 'Search the trash' : 'Search ${basename(c.path) == '/' ? 'everywhere' : basename(c.path)}',
                  hintStyle: TextStyle(color: p.dimText, fontSize: 13.5),
                ),
                onChanged: c.setQuery,
              ),
            ),
          ),
          if (c.query.isNotEmpty)
            InkResponse(
              onTap: () {
                _search.clear();
                c.clearSearch();
              },
              radius: 14,
              child: Icon(Icons.close_rounded, size: 16, color: p.dimText),
            ),
        ]),
      );

  Widget _menu(FilesController c, ForgePalette p) {
    PopupMenuItem<VoidCallback> check(String label, bool on, VoidCallback f, {String keys = ''}) => PopupMenuItem(
          value: f,
          height: 36,
          child: Row(children: [
            SizedBox(width: 22, child: on ? Icon(Icons.check_rounded, size: 16, color: p.accent) : null),
            Expanded(child: Text(label, style: TextStyle(color: p.text, fontSize: 13))),
            Text(keys, style: TextStyle(color: p.dimText, fontSize: 12)),
          ]),
        );
    String arrow(SortBy by) => c.sortBy == by ? (c.descending ? '  ↓' : '  ↑') : '';
    return PopupMenuButton<VoidCallback>(
      tooltip: 'View',
      icon: Icon(Icons.more_vert_rounded, color: p.text.withValues(alpha: 0.8), size: 20),
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (f) => f(),
      itemBuilder: (_) => [
        check('Icons', c.view == ViewMode.grid, () => c.setView(ViewMode.grid), keys: 'Ctrl+1'),
        check('List', c.view == ViewMode.list, () => c.setView(ViewMode.list), keys: 'Ctrl+2'),
        const PopupMenuDivider(height: 8),
        check('Sort by name${arrow(SortBy.name)}', c.sortBy == SortBy.name, () => c.setSort(SortBy.name)),
        check('Sort by date${arrow(SortBy.modified)}', c.sortBy == SortBy.modified, () => c.setSort(SortBy.modified)),
        check('Sort by size${arrow(SortBy.size)}', c.sortBy == SortBy.size, () => c.setSort(SortBy.size)),
        check('Sort by type${arrow(SortBy.type)}', c.sortBy == SortBy.type, () => c.setSort(SortBy.type)),
        const PopupMenuDivider(height: 8),
        check('Hidden files', c.showHidden, c.toggleHidden, keys: 'Ctrl+H'),
        check('Bigger icons', false, () => c.zoomBy(0.2), keys: 'Ctrl+='),
        check('Smaller icons', false, () => c.zoomBy(-0.2), keys: 'Ctrl+−'),
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn(this.p, this.icon, this.tip, this.onTap);
  final ForgePalette p;
  final IconData icon;
  final String tip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        waitDuration: const Duration(milliseconds: 600),
        child: InkResponse(
          onTap: onTap,
          radius: 18,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon, size: 20, color: p.text.withValues(alpha: onTap == null ? 0.3 : 0.85)),
          ),
        ),
      );
}
