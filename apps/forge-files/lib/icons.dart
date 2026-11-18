// File icons: Forge's own, a glyph on a tinted tile, coloured by kind, so
// every theme and accent gets matching icons. Folders take the accent.
import 'package:flutter/material.dart';

import 'fs.dart';

enum Kind { folder, image, video, audio, document, sheet, slides, pdf, archive, code, text, app, disk, font, other }

const _byExt = <String, Kind>{
  'png': Kind.image, 'jpg': Kind.image, 'jpeg': Kind.image, 'gif': Kind.image, 'webp': Kind.image,
  'bmp': Kind.image, 'svg': Kind.image, 'avif': Kind.image, 'heic': Kind.image, 'tif': Kind.image,
  'tiff': Kind.image, 'ico': Kind.image, 'xcf': Kind.image, 'kra': Kind.image, 'psd': Kind.image,
  'mp4': Kind.video, 'mkv': Kind.video, 'webm': Kind.video, 'mov': Kind.video, 'avi': Kind.video,
  'm4v': Kind.video, 'wmv': Kind.video, 'flv': Kind.video, 'ts': Kind.video,
  'mp3': Kind.audio, 'flac': Kind.audio, 'ogg': Kind.audio, 'opus': Kind.audio, 'wav': Kind.audio,
  'm4a': Kind.audio, 'aac': Kind.audio, 'wma': Kind.audio,
  'doc': Kind.document, 'docx': Kind.document, 'odt': Kind.document, 'rtf': Kind.document, 'epub': Kind.document,
  'xls': Kind.sheet, 'xlsx': Kind.sheet, 'ods': Kind.sheet, 'csv': Kind.sheet,
  'ppt': Kind.slides, 'pptx': Kind.slides, 'odp': Kind.slides,
  'pdf': Kind.pdf,
  'zip': Kind.archive, 'tar': Kind.archive, 'gz': Kind.archive, 'xz': Kind.archive, 'zst': Kind.archive,
  'bz2': Kind.archive, '7z': Kind.archive, 'rar': Kind.archive, 'tgz': Kind.archive, 'deb': Kind.archive,
  'rpm': Kind.archive, 'jar': Kind.archive,
  'dart': Kind.code, 'py': Kind.code, 'rs': Kind.code, 'c': Kind.code, 'cc': Kind.code, 'cpp': Kind.code,
  'h': Kind.code, 'hpp': Kind.code, 'js': Kind.code, 'mjs': Kind.code, 'tsx': Kind.code, 'jsx': Kind.code,
  'go': Kind.code, 'java': Kind.code, 'kt': Kind.code, 'sh': Kind.code, 'zsh': Kind.code, 'bash': Kind.code,
  'html': Kind.code, 'css': Kind.code, 'json': Kind.code, 'yaml': Kind.code, 'yml': Kind.code,
  'toml': Kind.code, 'xml': Kind.code, 'qml': Kind.code, 'lua': Kind.code, 'rb': Kind.code, 'php': Kind.code,
  'cmake': Kind.code, 'swift': Kind.code, 'cs': Kind.code, 'sql': Kind.code,
  'txt': Kind.text, 'md': Kind.text, 'log': Kind.text, 'conf': Kind.text, 'ini': Kind.text, 'cfg': Kind.text,
  'desktop': Kind.app, 'appimage': Kind.app, 'exe': Kind.app, 'flatpakref': Kind.app,
  'iso': Kind.disk, 'img': Kind.disk, 'qcow2': Kind.disk, 'vdi': Kind.disk,
  'ttf': Kind.font, 'otf': Kind.font, 'woff': Kind.font, 'woff2': Kind.font,
};

Kind kindOf(Entry e) {
  if (e.isDir) return Kind.folder;
  final k = _byExt[e.ext];
  if (k != null) return k;
  if (e.executable) return Kind.app;
  final mime = e.mime ?? '';
  if (mime.startsWith('image/')) return Kind.image;
  if (mime.startsWith('video/')) return Kind.video;
  if (mime.startsWith('audio/')) return Kind.audio;
  if (mime.startsWith('text/')) return Kind.text;
  return Kind.other;
}

String kindName(Entry e) => switch (kindOf(e)) {
      Kind.folder => 'Folder',
      Kind.image => 'Image',
      Kind.video => 'Video',
      Kind.audio => 'Audio',
      Kind.document => 'Document',
      Kind.sheet => 'Spreadsheet',
      Kind.slides => 'Presentation',
      Kind.pdf => 'PDF document',
      Kind.archive => 'Archive',
      Kind.code => 'Source code',
      Kind.text => 'Text',
      Kind.app => 'Program',
      Kind.disk => 'Disk image',
      Kind.font => 'Font',
      Kind.other => e.ext.isEmpty ? 'File' : '${e.ext.toUpperCase()} file',
    };

(IconData, Color) kindStyle(Kind k, Color accent) => switch (k) {
      Kind.folder => (Icons.folder_rounded, accent),
      Kind.image => (Icons.image_rounded, const Color(0xFF4FB6A0)),
      Kind.video => (Icons.movie_rounded, const Color(0xFFE0667E)),
      Kind.audio => (Icons.music_note_rounded, const Color(0xFFB07BE0)),
      Kind.document => (Icons.description_rounded, const Color(0xFF5B8DEF)),
      Kind.sheet => (Icons.table_chart_rounded, const Color(0xFF3FA66B)),
      Kind.slides => (Icons.slideshow_rounded, const Color(0xFFE88A3C)),
      Kind.pdf => (Icons.picture_as_pdf_rounded, const Color(0xFFE05555)),
      Kind.archive => (Icons.inventory_2_rounded, const Color(0xFFC59A4A)),
      Kind.code => (Icons.code_rounded, const Color(0xFF6A8FD8)),
      Kind.text => (Icons.notes_rounded, const Color(0xFF8C93AE)),
      Kind.app => (Icons.terminal_rounded, const Color(0xFF7C8AA8)),
      Kind.disk => (Icons.album_rounded, const Color(0xFF8C93AE)),
      Kind.font => (Icons.font_download_rounded, const Color(0xFFCF6FB0)),
      Kind.other => (Icons.insert_drive_file_rounded, const Color(0xFF8C93AE)),
    };

/// Special folders get their own glyph on the folder.
IconData? folderBadge(String path, List<Place> places) {
  for (final p in places) {
    if (p.path == path) return placeIcon(p.icon);
  }
  return null;
}

IconData placeIcon(String key) => switch (key) {
      'home' => Icons.home_rounded,
      'desktop' => Icons.desktop_windows_rounded,
      'documents' => Icons.description_rounded,
      'downloads' => Icons.download_rounded,
      'music' => Icons.music_note_rounded,
      'pictures' => Icons.image_rounded,
      'videos' => Icons.movie_rounded,
      'projects' => Icons.code_rounded,
      'trash' => Icons.delete_rounded,
      'drive' => Icons.storage_rounded,
      'usb' => Icons.usb_rounded,
      'root' => Icons.dns_rounded,
      'bookmark' => Icons.bookmark_rounded,
      _ => Icons.folder_rounded,
    };

/// A file's icon tile at [size].
class FileIcon extends StatelessWidget {
  const FileIcon({super.key, required this.entry, required this.size, required this.accent, this.badge});

  final Entry entry;
  final double size;
  final Color accent;
  final IconData? badge;

  @override
  Widget build(BuildContext context) {
    final kind = kindOf(entry);
    final (icon, colour) = kindStyle(kind, accent);
    if (kind == Kind.folder) {
      return SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          Icon(Icons.folder_rounded, size: size, color: colour.withValues(alpha: 0.9)),
          if (badge != null)
            Padding(
              padding: EdgeInsets.only(top: size * 0.14),
              child: Icon(badge, size: size * 0.34, color: Colors.white.withValues(alpha: 0.9)),
            ),
          if (entry.isLink)
            Positioned(right: 0, bottom: size * 0.1, child: Icon(Icons.link_rounded, size: size * 0.3, color: Colors.white)),
        ]),
      );
    }
    return Container(
      width: size * 0.78,
      height: size * 0.92,
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(size * 0.14),
      ),
      alignment: Alignment.center,
      child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
        Icon(icon, size: size * 0.42, color: colour),
        if (size >= 48 && entry.ext.isNotEmpty && entry.ext.length <= 5)
          Positioned(
            bottom: -size * 0.3,
            child: Text(entry.ext.toUpperCase(),
                style: TextStyle(fontSize: size * 0.13, fontWeight: FontWeight.w800, color: colour, letterSpacing: 0.5)),
          ),
      ]),
    );
  }
}
