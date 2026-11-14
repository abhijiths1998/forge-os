// The thumbnail in the bottom-right corner after a capture, macOS-style:
// what was taken and what happened to it (saved, copied), and what else to
// do with it. Clicking the picture opens the editor. It goes away after a
// few seconds, unless the pointer is on it.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

class Thumbnail extends StatefulWidget {
  const Thumbnail({
    super.key,
    required this.image,
    required this.status,
    required this.palette,
    required this.onEdit,
    required this.onCopy,
    required this.onFolder,
    required this.onDelete,
    required this.onClose,
    this.saved = true,
  });

  final ui.Image image;
  final String status;
  final ForgePalette palette;
  final bool saved;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback onFolder;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  State<Thumbnail> createState() => _ThumbnailState();
}

class _ThumbnailState extends State<Thumbnail> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _wait(const Duration(seconds: 6));
  }

  void _wait(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, widget.onClose);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    Widget action(IconData icon, String tip, VoidCallback onTap) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 19, color: p.text),
          onPressed: onTap,
        );
    return MouseRegion(
      onEnter: (_) => _timer?.cancel(),
      onExit: (_) => _wait(const Duration(seconds: 3)),
      child: Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(p.cornerRadius.toDouble()),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.onEdit,
                child: Tooltip(
                  message: 'Annotate',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: RawImage(image: widget.image, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Text(widget.status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
            action(Icons.draw_rounded, 'Annotate', widget.onEdit),
            action(Icons.content_copy_rounded, 'Copy', widget.onCopy),
            if (widget.saved) action(Icons.folder_open_rounded, 'Show in folder', widget.onFolder),
            if (widget.saved) action(Icons.delete_outline_rounded, 'Delete', widget.onDelete),
            action(Icons.close_rounded, 'Close', widget.onClose),
          ]),
        ]),
      ),
    );
  }
}
