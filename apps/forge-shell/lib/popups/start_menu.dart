// The start menu, from the Forge emblem in the top bar (or a tap on the
// Super key): search at the top, app categories down the side, the apps
// as a grid, and you and the power buttons at the bottom.
//
// Type to search (names, generic names, keywords, descriptions); arrows
// move, Enter opens, Esc closes. Right-click an app to pin it to the start
// menu or the dock.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

import '../native.dart';
import '../pins.dart';
import 'dialog.dart';
import 'menu.dart';
import 'style.dart';

const startMenuWidth = 700.0;
const startMenuHeight = 580.0;
const _columns = 5;

class _Category {
  const _Category(this.name, this.icon, this.matches);

  final String name;
  final IconData icon;

  /// freedesktop main categories that put an app here.
  final List<String> matches;
}

const _pinned = 'Pinned';
const _all = 'All apps';

/// In this order; an app goes in the first that matches.
const _categories = [
  _Category('Games', Icons.sports_esports_rounded, ['Game']),
  _Category('Internet', Icons.public_rounded, ['Network', 'WebBrowser']),
  _Category('Multimedia', Icons.play_circle_rounded, [
    'AudioVideo',
    'Audio',
    'Video',
  ]),
  _Category('Graphics', Icons.brush_rounded, ['Graphics']),
  _Category('Office', Icons.description_rounded, ['Office']),
  _Category('Development', Icons.code_rounded, ['Development']),
  _Category('Education', Icons.school_rounded, ['Education', 'Science']),
  _Category('Settings', Icons.tune_rounded, ['Settings']),
  _Category('System', Icons.memory_rounded, ['System']),
  _Category('Utilities', Icons.handyman_rounded, ['Utility']),
];

String _categoryOf(App a) {
  for (final c in _categories) {
    if (a.categories.any(c.matches.contains)) return c.name;
  }
  return 'Other';
}

class StartMenu extends StatefulWidget {
  const StartMenu({
    super.key,
    required this.palette,
    required this.apps,
    required this.onLaunch,
    required this.onPower,
    required this.onMenu,
  });

  final ForgePalette palette;
  final List<App> apps;
  final ValueChanged<App> onLaunch;
  final ValueChanged<String> onPower;

  /// A menu at a point on the screen, over the start menu; the id picked.
  final Future<String> Function(Offset at, MenuSpec spec) onMenu;

  @override
  State<StartMenu> createState() => _StartMenuState();
}

class _StartMenuState extends State<StartMenu> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();
  String _category = _pinned;
  int _selected = 0;
  List<String> _startPins = Pins.start.read();
  late final List<App> _shown = [
    for (final a in widget.apps)
      if (a.show) a,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_key);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _query => _search.text.trim().toLowerCase();

  List<String> get _usedCategories {
    final used = {for (final a in _shown) _categoryOf(a)};
    return [
      for (final c in _categories)
        if (used.contains(c.name)) c.name,
      if (used.contains('Other')) 'Other',
    ];
  }

  /// What the grid shows: search results, best first, or a category.
  List<App> _visible() {
    final q = _query;
    if (q.isNotEmpty) {
      final scored = <(int, App)>[];
      for (final a in _shown) {
        final s = _score(a, q);
        if (s > 0) scored.add((s, a));
      }
      scored.sort((x, y) => y.$1.compareTo(x.$1));
      return [for (final (_, a) in scored) a];
    }
    if (_category == _pinned) {
      final byId = {for (final a in _shown) a.id: a};
      return [
        for (final id in _startPins)
          if (byId[id] != null) byId[id]!,
      ];
    }
    if (_category == _all) return _shown;
    return [
      for (final a in _shown)
        if (_categoryOf(a) == _category) a,
    ];
  }

  static int _score(App a, String q) {
    final name = a.name.toLowerCase();
    if (name == q) return 1000;
    if (name.startsWith(q)) return 800;
    if (name.split(RegExp(r'[\s\-_.]')).any((w) => w.startsWith(q))) {
      return 600;
    }
    if (name.contains(q)) return 500;
    final generic = a.generic.toLowerCase();
    if (generic.contains(q)) return 400;
    if (a.keywords.any((k) => k.toLowerCase().startsWith(q))) return 350;
    if (a.exec.split('/').last.toLowerCase().startsWith(q)) return 300;
    if (a.comment.toLowerCase().contains(q)) return 150;
    return 0;
  }

  bool _key(KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;
    final visible = _visible();
    final k = e.logicalKey;
    int? move;
    if (k == LogicalKeyboardKey.arrowDown) move = _columns;
    if (k == LogicalKeyboardKey.arrowUp) move = -_columns;
    if (k == LogicalKeyboardKey.tab) {
      move = HardwareKeyboard.instance.isShiftPressed ? -1 : 1;
    }
    // Left and right move the cursor while there's something typed.
    if (_search.text.isEmpty) {
      if (k == LogicalKeyboardKey.arrowRight) move = 1;
      if (k == LogicalKeyboardKey.arrowLeft) move = -1;
    }
    if (move != null) {
      if (visible.isEmpty) return true;
      setState(
        () => _selected = (_selected + move!).clamp(0, visible.length - 1),
      );
      _reveal();
      return true;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      if (visible.isNotEmpty) {
        widget.onLaunch(visible[_selected.clamp(0, visible.length - 1)]);
      }
      return true;
    }
    return false;
  }

  /// Scrolls the selected tile into view.
  void _reveal() {
    if (!_scroll.hasClients) return;
    const rowHeight = 104.0;
    final row = _selected ~/ _columns;
    final top = row * rowHeight;
    final view = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + rowHeight > _scroll.offset + view) {
      _scroll.jumpTo(top + rowHeight - view);
    }
  }

  void _pick(String category) {
    setState(() {
      _category = category;
      _selected = 0;
      _search.clear();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _searchFocus.requestFocus();
  }

  Future<void> _appMenu(App app, Offset at) async {
    final inStart = _startPins.contains(app.id);
    final inDock = Pins.dock.has(app.id);
    final picked = await widget.onMenu(
      at,
      MenuSpec(
        title: app.name,
        items: [
          MenuRow('open', 'Open', icon: popupIcons['new']),
          MenuRow.separator(),
          MenuRow(
            'start',
            inStart ? 'Unpin from Start' : 'Pin to Start',
            icon: popupIcons[inStart ? 'unpin' : 'pin'],
          ),
          MenuRow(
            'dock',
            inDock ? 'Remove from Dock' : 'Add to Dock',
            icon: popupIcons[inDock ? 'unpin' : 'pin'],
          ),
        ],
      ),
    );
    switch (picked) {
      case 'open':
        widget.onLaunch(app);
      case 'start':
        Pins.start.toggle(app.id);
        setState(() => _startPins = Pins.start.read());
      case 'dock':
        Pins.dock.toggle(app.id);
    }
    _searchFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final visible = _visible();
    final searching = _query.isNotEmpty;

    return PopupCard(
      palette: p,
      width: startMenuWidth,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: startMenuHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
              child: ForgeField(
                palette: p,
                controller: _search,
                focusNode: _searchFocus,
                autofocus: true,
                icon: Icons.search_rounded,
                hint: 'Search apps',
                onChanged: (_) => setState(() => _selected = 0),
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 176,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(10, 4, 4, 10),
                      children: [
                        for (final c in [_pinned, _all, ..._usedCategories])
                          _CategoryRow(
                            palette: p,
                            label: c,
                            icon: switch (c) {
                              _pinned => Icons.push_pin_rounded,
                              _all => Icons.apps_rounded,
                              _ =>
                                _categories
                                        .where((x) => x.name == c)
                                        .firstOrNull
                                        ?.icon ??
                                    Icons.category_rounded,
                            },
                            selected: !searching && c == _category,
                            onTap: () => _pick(c),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 18, 6),
                          child: Text(
                            searching
                                ? (visible.isEmpty
                                      ? 'Nothing matches “${_search.text.trim()}”'
                                      : 'Results')
                                : _category,
                            style: TextStyle(
                              color: p.dimText,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        Expanded(
                          child: GridView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(6, 0, 14, 12),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: _columns,
                                  mainAxisExtent: 104,
                                ),
                            itemCount: visible.length,
                            itemBuilder: (context, i) => _AppTile(
                              key: ValueKey(visible[i].id),
                              palette: p,
                              app: visible[i],
                              selected: i == _selected,
                              onTap: () => widget.onLaunch(visible[i]),
                              onMenu: (at) => _appMenu(visible[i], at),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _Footer(palette: p, onPower: widget.onPower),
          ],
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.palette,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final ForgePalette palette;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? p.accent.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          hoverColor: p.hover,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 17, color: selected ? p.accent : p.dimText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.text,
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppTile extends StatefulWidget {
  const _AppTile({
    super.key,
    required this.palette,
    required this.app,
    required this.selected,
    required this.onTap,
    required this.onMenu,
  });

  final ForgePalette palette;
  final App app;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Offset> onMenu;

  @override
  State<_AppTile> createState() => _AppTileState();
}

class _AppTileState extends State<_AppTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final a = widget.app;
    final lit = widget.selected || _hover;
    final tip = [
      if (a.generic.isNotEmpty) a.generic,
      if (a.comment.isNotEmpty) a.comment,
    ].join(' · ');
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapUp: (d) => widget.onMenu(d.globalPosition),
        child: Tooltip(
          message: tip,
          waitDuration: const Duration(milliseconds: 700),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: widget.selected
                  ? p.accent.withValues(alpha: 0.16)
                  : lit
                  ? p.hover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FutureBuilder(
                  future: Native.icon(app: a.id, size: 44),
                  builder: (context, snap) => snap.data == null
                      ? const SizedBox(width: 44, height: 44)
                      : Image.memory(
                          snap.data!,
                          width: 44,
                          height: 44,
                          filterQuality: FilterQuality.medium,
                          gaplessPlayback: true,
                        ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    a.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.text,
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// You (picture and name) on the left, power on the right.
class _Footer extends StatelessWidget {
  const _Footer({required this.palette, required this.onPower});

  final ForgePalette palette;
  final ValueChanged<String> onPower;

  static final _me = _whoAmI();

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final (name, face) = _me;
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: p.text.withValues(alpha: 0.04),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(p.cornerRadius.clamp(10, 22).toDouble()),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: p.accent,
            backgroundImage: face == null ? null : FileImage(face),
            child: face == null
                ? Text(
                    name.isEmpty ? '?' : name[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: p.text,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final a in PowerAction.all)
            Tooltip(
              message: a.label,
              child: IconButton(
                onPressed: () => onPower(a.id),
                icon: Icon(popupIcons[a.icon], size: 19),
                color: p.text,
                hoverColor: a.id == 'shutdown'
                    ? p.negative.withValues(alpha: 0.2)
                    : p.hover,
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Your full name (else the login name) and picture, if you set one.
(String, File?) _whoAmI() {
  final user = Platform.environment['USER'] ?? '';
  var name = user;
  try {
    final r = Process.runSync('getent', ['passwd', user]);
    final gecos = (r.stdout as String).split(':');
    if (gecos.length > 4) {
      final full = gecos[4].split(',').first.trim();
      if (full.isNotEmpty) name = full;
    }
  } catch (_) {}
  final home = Platform.environment['HOME'] ?? '';
  for (final path in [
    '$home/.face',
    '$home/.face.icon',
    '/var/lib/AccountsService/icons/$user',
  ]) {
    final f = File(path);
    try {
      if (f.existsSync() && f.lengthSync() > 0) return (name, f);
    } on FileSystemException catch (_) {}
  }
  return (name, null);
}

