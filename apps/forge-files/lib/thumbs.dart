// Thumbnails: pictures are decoded small straight from the file; videos
// (ffmpeg) and PDFs (pdftoppm) are rendered once into our own cache,
// ~/.cache/forgeos/files/thumbs, keyed by path and modification time.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import 'fs.dart';
import 'icons.dart';

const _imageExts = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'avif'};
const _videoExts = {'mp4', 'mkv', 'webm', 'mov', 'avi', 'm4v', 'wmv', 'flv'};

final String _cache = '${Platform.environment['XDG_CACHE_HOME'] ?? '$home/.cache'}/forgeos/files/thumbs';

bool hasThumbnail(Entry e) =>
    !e.isDir && (_imageExts.contains(e.ext) || _videoExts.contains(e.ext) || e.ext == 'pdf');

class Thumbnails {
  static final _done = <String, Future<String?>>{};
  static int _running = 0;
  static final _waiting = <Completer<void>>[];

  static Future<String?> of(Entry e) {
    if (_imageExts.contains(e.ext)) return Future.value(e.path);
    final key = md5.convert(utf8.encode('${e.path}:${e.modified.millisecondsSinceEpoch}')).toString();
    return _done.putIfAbsent(key, () => _make(e, '$_cache/$key.png'));
  }

  static Future<String?> _make(Entry e, String out) async {
    if (File(out).existsSync()) return out;
    // Big files over slow drives: a few at a time.
    if (_running >= 3) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    }
    _running++;
    try {
      Directory(_cache).createSync(recursive: true);
      final ProcessResult r;
      if (e.ext == 'pdf') {
        r = await Process.run('pdftoppm', [
          '-png', '-singlefile', '-f', '1', '-l', '1', '-scale-to', '256', e.path, out.substring(0, out.length - 4),
        ]).timeout(const Duration(seconds: 15));
      } else {
        r = await Process.run('ffmpeg', [
          '-v', 'error', '-y', '-ss', '3', '-i', e.path, '-frames:v', '1',
          '-vf', 'thumbnail,scale=256:-2', out,
        ]).timeout(const Duration(seconds: 20));
        // Shorter than 3 s: the first frame.
        if (!File(out).existsSync()) {
          await Process.run('ffmpeg', ['-v', 'error', '-y', '-i', e.path, '-frames:v', '1', '-vf', 'scale=256:-2', out])
              .timeout(const Duration(seconds: 20));
        }
      }
      return r.exitCode == 0 || File(out).existsSync() ? (File(out).existsSync() ? out : null) : null;
    } catch (_) {
      return null;
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }
}

/// A file's thumbnail if it has one, else its icon.
class FileThumb extends StatefulWidget {
  const FileThumb({super.key, required this.entry, required this.size, required this.accent, this.badge});

  final Entry entry;
  final double size;
  final Color accent;
  final IconData? badge;

  @override
  State<FileThumb> createState() => _ThumbState();
}

class _ThumbState extends State<FileThumb> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FileThumb old) {
    super.didUpdateWidget(old);
    if (old.entry.path != widget.entry.path || old.entry.modified != widget.entry.modified) {
      _path = null;
      _load();
    }
  }

  void _load() {
    if (!hasThumbnail(widget.entry) || widget.size < 28) return;
    Thumbnails.of(widget.entry).then((p) {
      if (mounted && p != null) setState(() => _path = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final icon = FileIcon(entry: widget.entry, size: widget.size, accent: widget.accent, badge: widget.badge);
    final p = _path;
    if (p == null) return SizedBox(width: widget.size, height: widget.size, child: Center(child: icon));
    final video = _videoExts.contains(widget.entry.ext);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Center(
        child: Stack(alignment: Alignment.center, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(widget.size * 0.08),
            child: Image.file(
              File(p),
              cacheWidth: (widget.size * dpr * 1.5).round(),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => icon,
            ),
          ),
          if (video)
            Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
              child: Icon(Icons.play_arrow_rounded, size: widget.size * 0.22, color: Colors.white),
            ),
        ]),
      ),
    );
  }
}
