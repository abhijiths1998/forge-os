// The sidebar: places, bookmarks, drives and the trash. Everything in it is
// a drop target, so files can be dragged straight onto a place.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

import 'controller.dart';
import 'fs.dart';
import 'icons.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.c, required this.palette, required this.places, required this.onBookmarksChanged});

  final FilesController c;
  final ForgePalette palette;
  final List<Place> places;
  final VoidCallback onBookmarksChanged;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final marks = bookmarks();
    return Container(
      width: 220,
      color: p.sidebar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
        children: [
          for (final pl in places)
            _Item(
              palette: p,
              icon: placeIcon(pl.icon),
              label: pl.name,
              selected: c.path == pl.path,
              dropTo: pl.path,
              c: c,
              onTap: () => c.go(pl.path),
            ),
          if (marks.isNotEmpty) ...[
            _Header('Bookmarks', palette: p),
            for (final b in marks)
              _Item(
                palette: p,
                icon: Icons.bookmark_rounded,
                label: b.name,
                selected: c.path == b.path,
                dropTo: b.path,
                c: c,
                onTap: () => c.go(b.path),
                onSecondary: (pos) async {
                  final r = await showMenu<String>(
                    context: context,
                    color: p.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
                    items: [
                      PopupMenuItem(value: 'remove', height: 36, child: Text('Remove bookmark', style: TextStyle(color: p.text, fontSize: 13))),
                    ],
                  );
                  if (r == 'remove') {
                    removeBookmark(b.path);
                    onBookmarksChanged();
                  }
                },
              ),
          ],
          _Header('Drives', palette: p),
          _Item(
            palette: p,
            icon: Icons.dns_rounded,
            label: 'This computer',
            selected: c.path == '/',
            c: c,
            onTap: () => c.go('/'),
          ),
          for (final d in c.drives)
            _Item(
              palette: p,
              icon: d.removable ? Icons.usb_rounded : Icons.storage_rounded,
              label: d.label,
              dim: !d.mounted,
              selected: d.mounted && c.path == d.mountpoint,
              dropTo: d.mountpoint,
              c: c,
              onTap: () => c.openDrive(d),
              trailing: d.mounted
                  ? Tooltip(
                      message: d.removable ? 'Eject' : 'Unmount',
                      child: InkResponse(
                        onTap: () => c.ejectDrive(d),
                        radius: 14,
                        child: Icon(Icons.eject_rounded, size: 16, color: p.dimText),
                      ),
                    )
                  : null,
            ),
          const SizedBox(height: 10),
          _Item(
            palette: p,
            icon: Icons.delete_rounded,
            label: 'Trash',
            selected: c.inTrash,
            dropTo: trashFolder,
            c: c,
            onTap: () => c.go(trashFolder),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text, {required this.palette});
  final String text;
  final ForgePalette palette;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 0, 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(color: palette.dimText, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      );
}

class _Item extends StatelessWidget {
  const _Item({
    required this.palette,
    required this.icon,
    required this.label,
    required this.selected,
    required this.c,
    required this.onTap,
    this.dropTo,
    this.trailing,
    this.dim = false,
    this.onSecondary,
  });

  final ForgePalette palette;
  final IconData icon;
  final String label;
  final bool selected;
  final FilesController c;
  final VoidCallback onTap;
  final String? dropTo;
  final Widget? trailing;
  final bool dim;
  final void Function(Offset)? onSecondary;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    Widget row(bool hovering) => Material(
          color: hovering
              ? p.accent.withValues(alpha: 0.3)
              : selected
                  ? p.accent.withValues(alpha: 0.2)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            onSecondaryTapDown: onSecondary == null ? null : (d) => onSecondary!(d.globalPosition),
            borderRadius: BorderRadius.circular(10),
            hoverColor: p.hover,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Icon(icon, size: 18, color: selected ? p.accent : p.text.withValues(alpha: dim ? 0.45 : 0.75)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.text.withValues(alpha: dim ? 0.55 : 1),
                        fontSize: 13.5,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      )),
                ),
                ?trailing,
              ]),
            ),
          ),
        );
    final to = dropTo;
    if (to == null) return Padding(padding: const EdgeInsets.only(bottom: 2), child: row(false));
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: DragTarget<List<String>>(
        onWillAcceptWithDetails: (d) => !d.data.contains(to),
        onAcceptWithDetails: (d) => c.drop(d.data, to, copy: HardwareKeyboard.instance.isControlPressed),
        builder: (context, candidates, _) => row(candidates.isNotEmpty),
      ),
    );
  }
}
