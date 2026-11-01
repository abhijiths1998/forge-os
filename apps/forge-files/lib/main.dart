// Forge Files: Forge OS's file manager, in the Forge Glass look and the
// desktop's accent. Places, drives (mount and eject through udisks), the
// trash, thumbnails, search, drag and drop, and the usual keys.
//
//   forge-files [FOLDER | FILE]   (a file opens its folder with it selected)
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

import 'content.dart';
import 'controller.dart';
import 'dialogs.dart';
import 'fs.dart';
import 'sidebar.dart';
import 'toolbar.dart';

void main(List<String> args) {
  var start = home;
  String? select;
  for (final a in args) {
    if (a.startsWith('-')) continue;
    if (a == trashFolder) {
      start = trashFolder;
      continue;
    }
    var p = a.startsWith('file://') ? Uri.parse(a).toFilePath() : a;
    if (!p.startsWith('/')) p = '${Directory.current.path}/$p';
    if (Directory(p).existsSync()) {
      start = Directory(p).absolute.path;
    } else if (File(p).existsSync()) {
      start = dirname(p);
      select = p;
    }
  }
  runApp(FilesApp(start: start, select: select));
}

class FilesApp extends StatefulWidget {
  const FilesApp({super.key, required this.start, this.select});
  final String start;
  final String? select;

  @override
  State<FilesApp> createState() => _FilesAppState();
}

class _FilesAppState extends State<FilesApp> {
  static const _window = MethodChannel('forge/window');

  late final FilesController c = FilesController(widget.start, select: widget.select);
  ForgePalette _p = ForgePalette.current();
  List<Place> _places = places();
  final _navigator = GlobalKey<NavigatorState>();
  final _focus = FocusNode();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();
  bool _pathEditing = false;
  int _columns = 1;
  Timer? _themePoll;
  String _title = '';

  BuildContext get _ctx => _navigator.currentContext!;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    // The theme (accent, light/dark) can change while we're open.
    _themePoll = Timer.periodic(const Duration(seconds: 3), (_) {
      final p = ForgePalette.current();
      if (p.theme.toJson().toString() != _p.theme.toJson().toString()) setState(() => _p = p);
    });
  }

  @override
  void dispose() {
    _themePoll?.cancel();
    c.removeListener(_changed);
    c.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    final t = c.inTrash ? 'Trash' : (c.path == home ? 'Home' : basename(c.path));
    if (t != _title) {
      _title = t;
      _window.invokeMethod('setTitle', '$t — Files').catchError((_) => null);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    _revealCursor();
  }

  // Keep the keyboard's item on screen.
  void _revealCursor() {
    final i = c.cursor;
    if (i == null || !_scroll.hasClients) return;
    final double rowH, top;
    if (c.view == ViewMode.grid) {
      rowH = 112.0 * c.zoom * 1.12;
      top = (i ~/ _columns) * rowH + 8;
    } else {
      rowH = 34.0 * c.zoom.clamp(0.8, 1.6);
      top = i * rowH + 4;
    }
    final view = _scroll.position.viewportDimension;
    final off = _scroll.offset;
    if (top < off) {
      _scroll.jumpTo(top);
    } else if (top + rowH > off + view) {
      _scroll.jumpTo((top + rowH - view).clamp(0, _scroll.position.maxScrollExtent));
    }
  }

  // ------------------------------------------------------------ actions

  void _rename() {
    final s = c.selection;
    if (s.length != 1 || c.inTrash) return;
    askName(_ctx, _p,
        title: 'Rename', action: 'Rename', initial: s.first.name, selectStem: !s.first.isDir,
        validate: (n) => c.renameEntry(s.first, n));
  }

  void _newFolder() {
    if (c.inTrash) return;
    askName(_ctx, _p,
        title: 'New folder', action: 'Create', initial: basename(freeName(c.path, 'New Folder')), selectStem: false,
        validate: (n) => c.createNew(n, folder: true));
  }

  void _newFile() {
    if (c.inTrash) return;
    askName(_ctx, _p,
        title: 'New empty file', action: 'Create', initial: basename(freeName(c.path, 'New File.txt')),
        validate: (n) => c.createNew(n, folder: false));
  }

  Future<void> _deleteForever() async {
    final n = c.selected.length;
    if (n == 0) return;
    final what = n == 1 ? '"${basename(c.selected.first)}"' : '$n items';
    if (await confirm(_ctx, _p, 'Delete $what for good?', 'It won\'t go to the trash, and can\'t be brought back.', 'Delete')) {
      c.deleteSelected();
    }
  }

  Future<void> _emptyTrash() async {
    if (await confirm(_ctx, _p, 'Empty the trash?', 'Everything in it is deleted for good.', 'Empty')) c.empty();
  }

  void _properties() {
    final s = c.selection;
    if (s.isNotEmpty) {
      showProperties(_ctx, _p, s);
    } else if (!c.inTrash) {
      stat(c.path).then((e) {
        if (e != null && mounted) showProperties(_ctx, _p, [e]);
      });
    }
  }

  // ------------------------------------------------------------ menus

  Future<void> _menu(Offset at, int? index) async {
    final p = _p;
    final sel = c.selection;
    final one = sel.length == 1 ? sel.first : null;
    PopupMenuEntry<VoidCallback> item(String label, VoidCallback f, {String keys = '', IconData? icon, bool enabled = true}) =>
        PopupMenuItem(
          value: f,
          enabled: enabled,
          height: 36,
          child: Row(children: [
            Icon(icon ?? Icons.circle, size: 17, color: icon == null ? Colors.transparent : p.text.withValues(alpha: enabled ? 0.75 : 0.3)),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(color: enabled ? p.text : p.dimText, fontSize: 13))),
            Text(keys, style: TextStyle(color: p.dimText, fontSize: 12)),
          ]),
        );
    const div = PopupMenuDivider(height: 8);
    final List<PopupMenuEntry<VoidCallback>> items;
    if (index == null) {
      items = c.inTrash
          ? [item('Empty trash', _emptyTrash, icon: Icons.delete_forever_rounded, enabled: c.entries.isNotEmpty)]
          : [
              item('New folder', _newFolder, keys: 'Ctrl+Shift+N', icon: Icons.create_new_folder_rounded),
              item('New empty file', _newFile, icon: Icons.note_add_rounded),
              item('Paste', c.paste, keys: 'Ctrl+V', icon: Icons.content_paste_rounded),
              div,
              item('Open terminal here', () => terminalHere(c.path), keys: 'F4', icon: Icons.terminal_rounded),
              item('Bookmark this folder', () {
                addBookmark(c.path);
                setState(() {});
              }, icon: Icons.bookmark_add_rounded),
              item('Select all', c.selectAll, keys: 'Ctrl+A', icon: Icons.select_all_rounded),
              item(c.showHidden ? 'Hide hidden files' : 'Show hidden files', c.toggleHidden, keys: 'Ctrl+H', icon: Icons.visibility_rounded),
              div,
              item('Properties', _properties, keys: 'Alt+Enter', icon: Icons.info_outline_rounded),
            ];
    } else if (c.inTrash) {
      items = [
        item('Restore', c.restoreSelected, icon: Icons.restore_from_trash_rounded),
        item('Delete for good', _deleteForever, keys: 'Delete', icon: Icons.delete_forever_rounded),
        div,
        item('Properties', _properties, icon: Icons.info_outline_rounded),
      ];
    } else {
      items = [
        item('Open', c.openSelection, keys: 'Enter', icon: Icons.open_in_new_rounded),
        if (one != null && !one.isDir) item('Open with…', () => openWithDialog(_ctx, _p, sel), icon: Icons.apps_rounded),
        if (one != null && one.isDir) item('Open in terminal', () => terminalHere(one.path), icon: Icons.terminal_rounded),
        div,
        item('Cut', () => c.copy(cut: true), keys: 'Ctrl+X', icon: Icons.content_cut_rounded),
        item('Copy', c.copy, keys: 'Ctrl+C', icon: Icons.content_copy_rounded),
        item('Copy path', () => Clipboard.setData(ClipboardData(text: sel.map((e) => e.path).join('\n'))),
            icon: Icons.link_rounded),
        if (one != null && one.isDir) item('Paste into folder', () => _pasteInto(one.path), icon: Icons.content_paste_rounded),
        item('Rename…', _rename, keys: 'F2', icon: Icons.drive_file_rename_outline_rounded, enabled: one != null),
        if (one != null && one.isDir)
          item('Bookmark', () {
            addBookmark(one.path);
            setState(() {});
          }, icon: Icons.bookmark_add_rounded),
        div,
        item('Move to trash', c.moveToTrash, keys: 'Delete', icon: Icons.delete_rounded),
        item('Delete for good', _deleteForever, keys: 'Shift+Delete', icon: Icons.delete_forever_rounded),
        div,
        item('Properties', _properties, keys: 'Alt+Enter', icon: Icons.info_outline_rounded),
      ];
    }
    final f = await showMenu<VoidCallback>(
      context: _ctx,
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: items,
    );
    f?.call();
    _focus.requestFocus();
  }

  Future<void> _pasteInto(String dir) async {
    final old = c.path;
    c.path = dir;
    await c.paste();
    c.path = old;
    await c.reload();
  }

  // ------------------------------------------------------------ keys

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    // Typing in a text field (search, the path): its keys are its own.
    if (FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    final k = HardwareKeyboard.instance;
    final ctrl = k.isControlPressed, shift = k.isShiftPressed, alt = k.isAltPressed;
    final key = e.logicalKey;
    final step = c.view == ViewMode.grid ? _columns : 1;
    bool run(void Function() f) {
      f();
      return true;
    }

    final handled = switch (key) {
      LogicalKeyboardKey.arrowLeft when alt => run(c.back),
      LogicalKeyboardKey.arrowRight when alt => run(c.forward),
      LogicalKeyboardKey.arrowUp when alt => run(c.up),
      LogicalKeyboardKey.backspace => run(c.up),
      LogicalKeyboardKey.arrowLeft when c.view == ViewMode.grid => run(() => c.moveCursor(-1, shift: shift)),
      LogicalKeyboardKey.arrowRight when c.view == ViewMode.grid => run(() => c.moveCursor(1, shift: shift)),
      LogicalKeyboardKey.arrowUp => run(() => c.moveCursor(-step, shift: shift)),
      LogicalKeyboardKey.arrowDown => run(() => c.moveCursor(step, shift: shift)),
      LogicalKeyboardKey.home => run(() => c.moveCursor(-c.entries.length, shift: shift)),
      LogicalKeyboardKey.end => run(() => c.moveCursor(c.entries.length, shift: shift)),
      LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter when alt => run(_properties),
      LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter => run(c.openSelection),
      LogicalKeyboardKey.delete when shift || c.inTrash => run(_deleteForever),
      LogicalKeyboardKey.delete => run(c.moveToTrash),
      LogicalKeyboardKey.f2 => run(_rename),
      LogicalKeyboardKey.f4 => run(() => terminalHere(c.path)),
      LogicalKeyboardKey.f5 => run(c.reload),
      LogicalKeyboardKey.escape => run(() {
          if (c.query.isNotEmpty) {
            c.clearSearch();
          } else {
            c.clearSelection();
          }
        }),
      LogicalKeyboardKey.keyN when ctrl && shift => run(_newFolder),
      LogicalKeyboardKey.keyT when ctrl && alt => run(() => terminalHere(c.path)),
      LogicalKeyboardKey.keyA when ctrl => run(c.selectAll),
      LogicalKeyboardKey.keyC when ctrl => run(c.copy),
      LogicalKeyboardKey.keyX when ctrl => run(() => c.copy(cut: true)),
      LogicalKeyboardKey.keyV when ctrl => run(c.paste),
      LogicalKeyboardKey.keyH when ctrl => run(c.toggleHidden),
      LogicalKeyboardKey.keyL when ctrl => run(() => setState(() => _pathEditing = true)),
      LogicalKeyboardKey.keyF when ctrl => run(_searchFocus.requestFocus),
      LogicalKeyboardKey.keyR when ctrl => run(c.reload),
      LogicalKeyboardKey.keyD when ctrl => run(() {
          addBookmark(c.path);
          setState(() {});
        }),
      LogicalKeyboardKey.digit1 when ctrl => run(() => c.setView(ViewMode.grid)),
      LogicalKeyboardKey.digit2 when ctrl => run(() => c.setView(ViewMode.list)),
      LogicalKeyboardKey.equal || LogicalKeyboardKey.add when ctrl => run(() => c.zoomBy(0.2)),
      LogicalKeyboardKey.minus when ctrl => run(() => c.zoomBy(-0.2)),
      LogicalKeyboardKey.digit0 when ctrl => run(() => c.zoomBy(1 - c.zoom)),
      LogicalKeyboardKey.keyW when ctrl => run(() => exit(0)),
      _ => false,
    };
    if (handled) return KeyEventResult.handled;
    // Plain letters: jump to the name.
    final ch = e.character;
    if (!ctrl && !alt && ch != null && ch.length == 1 && RegExp(r'[\w.\- ]').hasMatch(ch)) {
      c.typeAhead(ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return MaterialApp(
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      title: 'Forge Files',
      color: Colors.transparent,
      theme: p.materialTheme(),
      home: Scaffold(
        backgroundColor: p.window,
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Row(children: [
            Sidebar(c: c, palette: p, places: _places, onBookmarksChanged: () => setState(() => _places = places())),
            Expanded(
              child: Column(children: [
                Toolbar(
                  c: c,
                  palette: p,
                  searchFocus: _searchFocus,
                  pathEditing: _pathEditing,
                  onPathEditing: (on) {
                    setState(() => _pathEditing = on);
                    if (!on) _focus.requestFocus();
                  },
                ),
                if (c.inTrash && c.entries.isNotEmpty) _trashBar(p),
                Expanded(
                  child: Stack(children: [
                    Positioned.fill(
                      child: Content(
                        c: c,
                        palette: p,
                        places: _places,
                        scroll: _scroll,
                        onMenu: _menu,
                        onColumns: (n) => _columns = n,
                      ),
                    ),
                    if (c.loading || c.busy != null)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(minHeight: 2, color: p.accent, backgroundColor: Colors.transparent),
                      ),
                    if (c.toast != null) Positioned(bottom: 40, left: 0, right: 0, child: Center(child: _toast(p))),
                  ]),
                ),
                _statusBar(p),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _trashBar(ForgePalette p) => Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.info_outline_rounded, size: 18, color: p.dimText),
          const SizedBox(width: 10),
          Expanded(child: Text('Items in the trash can be restored to where they were.', style: TextStyle(color: p.dimText, fontSize: 13))),
          if (c.selected.isNotEmpty) ...[
            PillButton(palette: p, label: 'Restore', onTap: c.restoreSelected),
            const SizedBox(width: 8),
          ],
          PillButton(palette: p, label: 'Empty trash', filled: true, onTap: _emptyTrash),
        ]),
      );

  Widget _toast(ForgePalette p) => Material(
        color: c.toastIsError ? Color.alphaBlend(p.negative.withValues(alpha: 0.85), p.surface) : p.surface,
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(c.toast!, style: TextStyle(color: c.toastIsError ? Colors.white : p.text, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      );

  Widget _statusBar(ForgePalette p) {
    final sel = c.selection;
    final selSize = sel.where((e) => !e.isDir).fold<int>(0, (a, e) => a + e.size);
    final left = c.busy ??
        (sel.isEmpty
            ? '${c.entries.length} item${c.entries.length == 1 ? '' : 's'}${c.searching ? ' found so far' : ''}'
            : '${sel.length} of ${c.entries.length} selected${selSize > 0 ? '  ·  ${sizeText(selSize)}' : ''}');
    final s = c.space;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(child: Text(left, style: TextStyle(color: p.dimText, fontSize: 12))),
        if (s != null) ...[
          SizedBox(
            width: 80,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: s.$2 == 0 ? 0 : 1 - s.$1 / s.$2,
                minHeight: 5,
                color: s.$1 / (s.$2 == 0 ? 1 : s.$2) < 0.1 ? p.negative : p.accent,
                backgroundColor: p.text.withValues(alpha: 0.1),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text('${sizeText(s.$1)} free', style: TextStyle(color: p.dimText, fontSize: 12)),
        ],
      ]),
    );
  }
}
