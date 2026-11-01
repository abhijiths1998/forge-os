// The strip of tabs across the top: glass pills like the rest of Forge,
// a dot for output in a tab you're not looking at, a flash for the bell.
import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'session.dart';
import 'settings.dart';

class TabStrip extends StatelessWidget {
  const TabStrip({
    super.key,
    required this.palette,
    required this.colours,
    required this.sessions,
    required this.active,
    required this.onSelect,
    required this.onClose,
    required this.onNew,
    required this.onReorder,
    required this.onMenu,
  });

  final ForgePalette palette;
  final TerminalColours colours;
  final List<Session> sessions;
  final int active;
  final ValueChanged<int> onSelect;
  final ValueChanged<Session> onClose;
  final VoidCallback onNew;
  final void Function(int from, int to) onReorder;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final fg = colours.foreground;
    return Container(
      height: 42,
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 4),
      color: fg.withValues(alpha: 0.035),
      child: Row(children: [
        Expanded(
          child: sessions.length == 1
              // One tab: no strip of one, just its title.
              ? Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(sessions.first.title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg.withValues(alpha: 0.75), fontSize: 13, fontWeight: FontWeight.w600)),
                )
              : ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
                  itemCount: sessions.length,
                  // onReorder takes the index before the removal, like the old callback.
                  onReorderItem: (from, to) => onReorder(from, to > from ? to + 1 : to),
                  itemBuilder: (context, i) => ReorderableDragStartListener(
                    key: ObjectKey(sessions[i]),
                    index: i,
                    child: _Tab(
                      palette: p,
                      foreground: fg,
                      session: sessions[i],
                      selected: i == active,
                      number: i + 1,
                      onTap: () => onSelect(i),
                      onClose: () => onClose(sessions[i]),
                    ),
                  ),
                ),
        ),
        _IconButton(icon: Icons.add_rounded, colour: fg, tip: 'New tab (Ctrl+Shift+T)', onTap: onNew),
        _IconButton(icon: Icons.tune_rounded, colour: fg, tip: 'Settings (Ctrl+Shift+,)', onTap: onMenu),
      ]),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.palette,
    required this.foreground,
    required this.session,
    required this.selected,
    required this.number,
    required this.onTap,
    required this.onClose,
  });

  final ForgePalette palette;
  final Color foreground;
  final Session session;
  final bool selected;
  final int number;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final s = widget.session;
    final fg = widget.foreground;
    final bg = s.bell
        ? p.accent.withValues(alpha: 0.45)
        : widget.selected
            ? fg.withValues(alpha: 0.12)
            : _hover
                ? fg.withValues(alpha: 0.06)
                : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onTertiaryTapUp: (_) => widget.onClose(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 190,
            padding: const EdgeInsets.only(left: 12, right: 4),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              if (s.activity && !widget.selected)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 7),
                  decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                )
              else if (s.exited)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.stop_circle_outlined, size: 14, color: fg.withValues(alpha: 0.5)),
                ),
              Expanded(
                child: Text(
                  s.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg.withValues(alpha: widget.selected ? 0.95 : 0.6),
                    fontSize: 12.5,
                    fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _hover || widget.selected ? 1 : 0,
                child: _IconButton(
                  icon: Icons.close_rounded,
                  colour: fg,
                  size: 15,
                  tip: 'Close tab (Ctrl+Shift+W)',
                  onTap: widget.onClose,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.colour,
    required this.tip,
    required this.onTap,
    this.size = 18,
  });

  final IconData icon;
  final Color colour;
  final String tip;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 600),
      child: InkResponse(
        onTap: onTap,
        radius: size + 2,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: size, color: colour.withValues(alpha: 0.7)),
        ),
      ),
    );
  }
}
