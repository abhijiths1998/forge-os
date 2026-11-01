// The dock: pinned apps, then any other running ones, on a compact glass
// strip centred at the bottom. A dot under an app that has windows (wider
// for the focused one), minimised ones included. Click: launch it, or bring
// its window forward (back from minimised if it was), or with its window
// already focused, the next one of its windows. Middle click: a new window.
// Right click: Forge's menu (its windows, new window, pin, close). Pins are
// ~/.config/forge/dock.json, a list of desktop ids (pins.dart).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'wm.dart';
import 'native.dart';
import 'pins.dart';
import 'popups/client.dart';

const _iconSize = 48.0;
const _gap = 6.0;
const _padding = 10.0;
// As in the runner: the dock's surface height and its gap to the screen edge.
const _dockHeight = 76.0;
const _dockMargin = 8.0;

/// Parts of the desktop that are windows but not apps of their own.
const _notInDock = {'org.forgeos.launcher', 'org.forgeos.control'};

class Dock extends StatefulWidget {
  const Dock({super.key, required this.palette});

  final ForgePalette palette;

  @override
  State<Dock> createState() => _DockState();
}

class _Entry {
  _Entry(this.app, this.windows);

  final App app;
  final List<Window> windows;
}

class _DockState extends State<Dock> {
  final _wm = Wm.connect();
  List<App> _apps = [];
  List<String> _pins = Pins.dock.read();
  final _popups = Popups();
  List<Window> _windows = [];
  StreamSubscription<void>? _events;
  int _lastWidth = 0;

  @override
  void initState() {
    super.initState();
    Native.apps().then((apps) {
      if (mounted) setState(() => _apps = apps);
    });
    _refresh();
    _events = _wm.changes().listen((_) => _refresh());
  }

  @override
  void didUpdateWidget(Dock old) {
    super.didUpdateWidget(old);
    // The palette changes with theme.json; the pins live beside it.
    _pins = Pins.dock.read();
  }

  Future<void> _refresh() async {
    try {
      final windows = await _wm.windows();
      if (!mounted) return;
      setState(
        () => _windows = windows
            .where((w) => w.mapped && !_notInDock.contains(w.appClass))
            .toList(),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  /// Pinned apps in order, then running apps that aren't pinned, each with
  /// its windows (most recently focused first).
  List<_Entry> _entries() {
    final byId = {for (final a in _apps) a.id: a};
    final left = [..._windows]
      ..sort((a, b) => a.focusHistory.compareTo(b.focusHistory));
    List<Window> take(App app) {
      final mine = left.where((w) => app.owns(w.appClass)).toList();
      left.removeWhere(mine.contains);
      return mine;
    }

    final entries = <_Entry>[
      for (final id in _pins)
        if (byId[id] != null) _Entry(byId[id]!, take(byId[id]!)),
    ];
    for (final app in _apps) {
      if (left.isEmpty) break;
      final mine = take(app);
      if (mine.isNotEmpty) entries.add(_Entry(app, mine));
    }
    return entries;
  }

  Future<void> _activate(_Entry e) async {
    if (e.windows.isEmpty) {
      await Native.launch(e.app.id);
      return;
    }
    // Focused already: the next of its windows, the least recent first.
    final focused = e.windows.first.focusHistory == 0;
    final target = focused && e.windows.length > 1
        ? e.windows.last
        : e.windows.first;
    await _wm.activate(target);
  }

  /// Forge's menu for an app, opening upwards from where it was clicked
  /// ([local] is in the dock's own coordinates).
  Future<void> _menu(_Entry e, Offset local) async {
    final measured = context.size?.width ?? 0;
    final width = _lastWidth > 0 ? _lastWidth.toDouble() : measured;
    final screen = await Native.screen();
    final x = (screen.width - width) / 2 + local.dx;
    final y = screen.height - _dockMargin - _dockHeight + 4;
    final windows = e.windows;
    final pinned = _pins.contains(e.app.id);
    final picked = await _popups.menu(
      x: x,
      y: y,
      above: true,
      title: e.app.name,
      items: [
        for (final (i, w) in windows.take(8).indexed)
          MenuItem(
            'w$i',
            w.title.isEmpty ? e.app.name : w.title,
            icon: 'window',
            checked: w.focusHistory == 0 && !w.minimized ? true : null,
            hint: w.minimized ? 'minimised' : null,
          ),
        if (windows.isNotEmpty) const MenuItem.separator(),
        MenuItem(
          'new',
          windows.isEmpty ? 'Open' : 'New window',
          icon: 'new',
        ),
        MenuItem(
          'pin',
          pinned ? 'Remove from Dock' : 'Keep in Dock',
          icon: pinned ? 'unpin' : 'pin',
        ),
        if (windows.isNotEmpty) ...[
          const MenuItem.separator(),
          MenuItem(
            'close',
            windows.length == 1
                ? 'Close window'
                : 'Close all ${windows.length} windows',
            icon: 'close',
            danger: true,
          ),
        ],
      ],
    );
    if (picked.startsWith('w')) {
      final i = int.tryParse(picked.substring(1));
      if (i != null && i < windows.length) await _wm.activate(windows[i]);
    }
    switch (picked) {
      case 'new':
        await Native.launch(e.app.id);
      case 'pin':
        Pins.dock.toggle(e.app.id);
        if (mounted) setState(() => _pins = Pins.dock.read());
      case 'close':
        for (final w in windows) {
          await _wm.close(w);
        }
    }
  }

  void _fitWidth(int count) {
    final width = (count * (_iconSize + _gap) - _gap + 2 * _padding).round();
    if (width == _lastWidth || count == 0) return;
    _lastWidth = width;
    Native.setWidth(width);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final entries = _entries();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _fitWidth(entries.length),
    );
    final focusedClass = _windows
        .where((w) => w.focusHistory == 0)
        .map((w) => w.appClass)
        .firstOrNull;

    return Container(
      decoration: BoxDecoration(
        color: p.window,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _padding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final (i, e) in entries.indexed) ...[
            if (i > 0) const SizedBox(width: _gap),
            _DockIcon(
              key: ValueKey(e.app.id),
              palette: p,
              app: e.app,
              running: e.windows.isNotEmpty,
              focused: focusedClass != null && e.app.owns(focusedClass),
              onTap: () => _activate(e),
              onMiddle: () => Native.launch(e.app.id),
              onMenu: (at) => _menu(e, at),
            ),
          ],
        ],
      ),
    );
  }
}

class _DockIcon extends StatefulWidget {
  const _DockIcon({
    super.key,
    required this.palette,
    required this.app,
    required this.running,
    required this.focused,
    required this.onTap,
    required this.onMiddle,
    required this.onMenu,
  });

  final ForgePalette palette;
  final App app;
  final bool running;
  final bool focused;
  final VoidCallback onTap;
  final VoidCallback onMiddle;
  final ValueChanged<Offset> onMenu;

  @override
  State<_DockIcon> createState() => _DockIconState();
}

class _DockIconState extends State<_DockIcon> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final scale = _pressed ? 0.9 : (_hover ? 1.12 : 1.0);
    // No tooltip yet: it would have to draw outside the dock's surface.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        onPointerDown: (e) {
          if (e.buttons == 4) widget.onMiddle(); // middle button
        },
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onTap();
          },
          onSecondaryTapUp: (d) => widget.onMenu(d.globalPosition),
          child: SizedBox(
            width: _iconSize,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 6),
                AnimatedScale(
                  scale: scale,
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutBack,
                  child: FutureBuilder(
                    future: Native.icon(
                      app: widget.app.id,
                      size: _iconSize.round(),
                    ),
                    builder: (context, snap) => snap.data == null
                        ? const SizedBox(width: _iconSize, height: _iconSize)
                        : Image.memory(
                            snap.data!,
                            width: _iconSize,
                            height: _iconSize,
                            filterQuality: FilterQuality.medium,
                            gaplessPlayback: true,
                          ),
                  ),
                ),
                const SizedBox(height: 5),
                // The running dot: solid accent when focused.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: widget.focused ? 12 : 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: !widget.running
                        ? Colors.transparent
                        : widget.focused
                        ? p.accent
                        : p.text.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(3),
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
