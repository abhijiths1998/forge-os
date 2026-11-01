// What Forge Files knows about the file system: folder listings, places,
// drives, the trash, and the operations (copy, move, trash, rename...).
// Heavy lifting goes to the system's own tools (cp, mv, gio, udisksctl),
// which already handle every corner case.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mime/mime.dart';

final String home = Platform.environment['HOME'] ?? '/';

class Entry {
  Entry({
    required this.path,
    required this.isDir,
    required this.size,
    required this.modified,
    required this.isLink,
    required this.mode,
    this.trashOrigin,
  });

  final String path;
  final bool isDir;
  final int size;
  final DateTime modified;
  final bool isLink;
  final int mode;

  /// In the trash: where it came from.
  final String? trashOrigin;

  String get name => basename(path);
  bool get hidden => name.startsWith('.');
  String get ext {
    final i = name.lastIndexOf('.');
    return i <= 0 ? '' : name.substring(i + 1).toLowerCase();
  }

  String? get mime => isDir ? 'inode/directory' : lookupMimeType(path);
  bool get executable => !isDir && (mode & 0x49) != 0; // any x bit
}

String basename(String path) {
  if (path == '/') return '/';
  final p = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  return p.substring(p.lastIndexOf('/') + 1);
}

String dirname(String path) {
  final i = path.lastIndexOf('/');
  return i <= 0 ? '/' : path.substring(0, i);
}

String join(String dir, String name) => dir == '/' ? '/$name' : '$dir/$name';

/// "~/Documents" for display.
String pretty(String path) {
  if (path == home) return '~';
  if (path.startsWith('$home/')) return '~/${path.substring(home.length + 1)}';
  return path;
}

String sizeText(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var u = 0;
  while (v >= 1000 && u < units.length - 1) {
    v /= 1000;
    u++;
  }
  return u == 0 ? '$bytes B' : '${v.toStringAsFixed(v < 10 ? 1 : 0)} ${units[u]}';
}

String dateText(DateTime t) {
  final now = DateTime.now();
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String two(int n) => n.toString().padLeft(2, '0');
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final time = '${two(t.hour)}:${two(t.minute)}';
  if (day == today) return 'Today, $time';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday, $time';
  if (t.year == now.year) return '${t.day} ${months[t.month - 1]}, $time';
  return '${t.day} ${months[t.month - 1]} ${t.year}';
}

Future<Entry?> stat(String path, {String? trashOrigin}) async {
  try {
    final link = await FileSystemEntity.isLink(path);
    final s = await FileStat.stat(path); // follows links
    final type = s.type == FileSystemEntityType.notFound ? FileSystemEntityType.file : s.type;
    return Entry(
      path: path,
      isDir: type == FileSystemEntityType.directory,
      size: s.size < 0 ? 0 : s.size,
      modified: s.modified,
      isLink: link,
      mode: s.mode,
      trashOrigin: trashOrigin,
    );
  } catch (_) {
    return null;
  }
}

Future<List<Entry>> listFolder(String dir) async {
  if (dir == trashFolder) return listTrash();
  final names = <String>[];
  await for (final e in Directory(dir).list(followLinks: false)) {
    names.add(e.path);
  }
  final out = <Entry>[];
  // Stat in batches: thousands of files shouldn't wait one by one.
  for (var i = 0; i < names.length; i += 64) {
    final batch = await Future.wait(names.skip(i).take(64).map((p) => stat(p)));
    out.addAll(batch.whereType<Entry>());
  }
  return out;
}

enum SortBy { name, modified, size, type }

int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+|\D+)');
  final x = re.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
  final y = re.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    final nx = int.tryParse(x[i]), ny = int.tryParse(y[i]);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : x[i].compareTo(y[i]);
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}

void sortEntries(List<Entry> list, SortBy by, bool descending) {
  list.sort((a, b) {
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1; // folders first, always
    final c = switch (by) {
      SortBy.name => naturalCompare(a.name, b.name),
      SortBy.modified => a.modified.compareTo(b.modified),
      SortBy.size => a.size.compareTo(b.size),
      SortBy.type => a.ext.compareTo(b.ext) != 0 ? a.ext.compareTo(b.ext) : naturalCompare(a.name, b.name),
    };
    return descending ? -c : c;
  });
}

// ---------------------------------------------------------------- places

class Place {
  const Place(this.name, this.path, this.icon);
  final String name;
  final String path;
  final String icon; // a key for icons.dart
}

/// Home and the XDG user folders that exist, in the usual order.
List<Place> places() {
  final dirs = <String, String>{};
  try {
    for (final line in File('$home/.config/user-dirs.dirs').readAsLinesSync()) {
      final m = RegExp(r'^XDG_(\w+)_DIR="(.*)"').firstMatch(line);
      if (m != null) dirs[m.group(1)!] = m.group(2)!.replaceAll(r'$HOME', home);
    }
  } catch (_) {}
  String dir(String key, String fallback) => dirs[key] ?? '$home/$fallback';
  final out = [const Place('Home', '', 'home')];
  for (final (key, name, fallback, icon) in const [
    ('DESKTOP', 'Desktop', 'Desktop', 'desktop'),
    ('DOCUMENTS', 'Documents', 'Documents', 'documents'),
    ('DOWNLOAD', 'Downloads', 'Downloads', 'downloads'),
    ('MUSIC', 'Music', 'Music', 'music'),
    ('PICTURES', 'Pictures', 'Pictures', 'pictures'),
    ('VIDEOS', 'Videos', 'Videos', 'videos'),
    ('PROJECTS', 'Projects', 'Projects', 'projects'),
  ]) {
    final p = dir(key, fallback);
    if (p != home && Directory(p).existsSync()) out.add(Place(name, p, icon));
  }
  return [for (final p in out) p.path.isEmpty ? Place(p.name, home, p.icon) : p];
}

/// GTK's bookmarks (shared with every GTK file dialog).
List<Place> bookmarks() {
  try {
    return [
      for (final line in File('$home/.config/gtk-3.0/bookmarks').readAsLinesSync())
        if (line.startsWith('file://'))
          () {
            final parts = line.split(' ');
            final path = Uri.decodeFull(parts.first.substring(7));
            return Place(parts.length > 1 ? parts.sublist(1).join(' ') : basename(path), path, 'bookmark');
          }(),
    ];
  } catch (_) {
    return [];
  }
}

void addBookmark(String path) {
  final f = File('$home/.config/gtk-3.0/bookmarks');
  f.parent.createSync(recursive: true);
  final uri = Uri.file(path).toString();
  final lines = f.existsSync() ? f.readAsLinesSync() : <String>[];
  if (lines.any((l) => l.split(' ').first == uri)) return;
  f.writeAsStringSync('${[...lines, uri].join('\n')}\n');
}

void removeBookmark(String path) {
  final f = File('$home/.config/gtk-3.0/bookmarks');
  if (!f.existsSync()) return;
  final uri = Uri.file(path).toString();
  f.writeAsStringSync('${f.readAsLinesSync().where((l) => l.split(' ').first != uri).join('\n')}\n');
}

// ---------------------------------------------------------------- drives

class Drive {
  Drive({
    required this.device,
    required this.label,
    required this.size,
    required this.mountpoint,
    required this.removable,
  });

  final String device;
  final String label;
  final String size;
  final String? mountpoint;
  final bool removable;
  bool get mounted => mountpoint != null;
}

/// Partitions worth showing: removable ones, and fixed ones that aren't
/// the system's own (/, /boot, /home, swap...).
Future<List<Drive>> listDrives() async {
  try {
    final r = await Process.run('lsblk', ['-J', '-b', '-o', 'PATH,LABEL,SIZE,MOUNTPOINTS,FSTYPE,RM,HOTPLUG,TYPE,PARTTYPENAME']);
    final j = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    final out = <Drive>[];
    void walk(List<dynamic> devices, bool removableParent) {
      for (final d in devices.cast<Map<String, dynamic>>()) {
        final removable = removableParent || d['rm'] == true || d['hotplug'] == true;
        final children = d['children'] as List<dynamic>?;
        if (children != null) walk(children, removable);
        final fs = d['fstype'] as String?;
        if (fs == null || fs == 'swap' || fs.contains('LUKS') || fs == 'linux_raid_member') continue;
        if (d['type'] == 'loop') continue;
        final mounts = (d['mountpoints'] as List<dynamic>? ?? []).whereType<String>().toList();
        final system = mounts.any((m) =>
            m == '/' || m.startsWith('/boot') || m == '/home' || m.startsWith('/var') ||
            m.startsWith('/efi') || m == '[SWAP]' || m.startsWith('/.snapshots') || m.startsWith('/opt') ||
            m.startsWith('/srv') || m.startsWith('/root') || m.startsWith('/usr') || m.startsWith('/tmp'));
        if (system) continue;
        final ptype = (d['parttypename'] as String? ?? '').toLowerCase();
        if (ptype.contains('efi') || ptype.contains('microsoft reserved') || ptype.contains('recovery')) continue;
        final bytes = (d['size'] as num?)?.toInt() ?? 0;
        if (bytes < 64 * 1024 * 1024 && mounts.isEmpty) continue;
        final label = (d['label'] as String?)?.trim();
        out.add(Drive(
          device: d['path'] as String,
          label: (label == null || label.isEmpty) ? '${sizeText(bytes)} Volume' : label,
          size: sizeText(bytes),
          mountpoint: mounts.isEmpty ? null : mounts.first,
          removable: removable,
        ));
      }
    }

    walk(j['blockdevices'] as List<dynamic>, false);
    return out;
  } catch (_) {
    return [];
  }
}

/// Mount through udisks (polkit asks for a password where it must);
/// returns the mount point or an error message.
Future<(String?, String?)> mount(Drive d) async {
  final r = await Process.run('udisksctl', ['mount', '--no-user-interaction', '-b', d.device]);
  var out = '${r.stdout}${r.stderr}';
  if (r.exitCode != 0 && out.contains('NotAuthorized')) {
    final r2 = await Process.run('udisksctl', ['mount', '-b', d.device]);
    out = '${r2.stdout}${r2.stderr}';
    if (r2.exitCode != 0) return (null, _udisksError(out));
  } else if (r.exitCode != 0) {
    return (null, _udisksError(out));
  }
  final m = RegExp(r' at (.+?)\.?\s*$').firstMatch(out.trim());
  return (m?.group(1), null);
}

Future<String?> unmount(Drive d, {bool eject = false}) async {
  final r = await Process.run('udisksctl', ['unmount', '-b', d.device]);
  if (r.exitCode != 0) return _udisksError('${r.stderr}');
  if (eject) await Process.run('udisksctl', ['power-off', '-b', d.device]);
  return null;
}

String _udisksError(String s) {
  if (s.contains('target is busy') || s.contains('DeviceBusy')) return 'Something is still using it';
  final m = RegExp(r'GDBus\.Error:[\w.]+: (.*)').firstMatch(s);
  return (m?.group(1) ?? s).trim();
}

/// Free and total bytes on the file system holding [path].
Future<(int, int)?> diskSpace(String path) async {
  try {
    final r = await Process.run('df', ['-B1', '--output=avail,size', path]);
    final f = (r.stdout as String).trim().split('\n').last.trim().split(RegExp(r'\s+'));
    return (int.parse(f[0]), int.parse(f[1]));
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------- trash

/// The trash, as a pseudo-folder.
const trashFolder = 'trash:///';

String get _trashDir {
  final data = Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share';
  return '$data/Trash';
}

Future<List<Entry>> listTrash() async {
  final files = Directory('$_trashDir/files');
  if (!files.existsSync()) return [];
  final out = <Entry>[];
  await for (final e in files.list(followLinks: false)) {
    String? origin;
    try {
      final info = File('$_trashDir/info/${basename(e.path)}.trashinfo').readAsLinesSync();
      final line = info.firstWhere((l) => l.startsWith('Path='));
      origin = Uri.decodeFull(line.substring(5));
    } catch (_) {}
    final s = await stat(e.path, trashOrigin: origin);
    if (s != null) out.add(s);
  }
  return out;
}

bool get trashEmpty {
  final d = Directory('$_trashDir/files');
  return !d.existsSync() || d.listSync().isEmpty;
}

Future<String?> trash(List<String> paths) async {
  final r = await Process.run('gio', ['trash', '--', ...paths]);
  return r.exitCode == 0 ? null : (r.stderr as String).trim();
}

Future<String?> restore(List<Entry> entries) async {
  for (final e in entries) {
    final r = await Process.run('gio', ['trash', '--restore', 'trash:///${Uri.encodeComponent(e.name)}']);
    if (r.exitCode != 0) return (r.stderr as String).trim();
  }
  return null;
}

Future<void> emptyTrash() => Process.run('gio', ['trash', '--empty']);

// ---------------------------------------------------------------- operations

/// A free name for [name] in [dir]: "name", then "name (2)"...
String freeName(String dir, String name) {
  if (FileSystemEntity.typeSync(join(dir, name), followLinks: false) == FileSystemEntityType.notFound) {
    return join(dir, name);
  }
  final dot = name.lastIndexOf('.');
  final hasExt = dot > 0 && !Directory(join(dir, name)).existsSync();
  final stem = hasExt ? name.substring(0, dot) : name;
  final ext = hasExt ? name.substring(dot) : '';
  for (var i = 2;; i++) {
    final p = join(dir, '$stem ($i)$ext');
    if (FileSystemEntity.typeSync(p, followLinks: false) == FileSystemEntityType.notFound) return p;
  }
}

/// Copy or move [paths] into [dir]. Never overwrites: a name that's taken
/// gets " (2)". Returns an error message or null.
Future<String?> transfer(List<String> paths, String dir, {required bool move}) async {
  for (final src in paths) {
    if (move && dirname(src) == dir) continue; // already here
    if (dir == src || dir.startsWith('$src/')) return 'Can\'t put a folder inside itself';
    final target = freeName(dir, basename(src));
    final r = move
        ? await Process.run('mv', ['-n', '--', src, target])
        : await Process.run('cp', ['-a', '--reflink=auto', '--', src, target]);
    if (r.exitCode != 0) return (r.stderr as String).trim().split('\n').first;
  }
  return null;
}

Future<String?> deleteForever(List<String> paths) async {
  try {
    for (final p in paths) {
      final type = FileSystemEntity.typeSync(p, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await Directory(p).delete(recursive: true);
      } else {
        await File(p).delete();
      }
      // Its trash record, if it was in the trash.
      final info = File('$_trashDir/info/${basename(p)}.trashinfo');
      if (p.startsWith('$_trashDir/files/') && info.existsSync()) info.deleteSync();
    }
    return null;
  } on FileSystemException catch (e) {
    return e.osError?.message ?? e.message;
  }
}

Future<String?> rename(String path, String newName) async {
  if (newName.isEmpty || newName.contains('/')) return 'A name can\'t be empty or contain "/"';
  final target = join(dirname(path), newName);
  if (target == path) return null;
  if (FileSystemEntity.typeSync(target, followLinks: false) != FileSystemEntityType.notFound) {
    return '"$newName" already exists';
  }
  try {
    await FileSystemEntity.isDirectory(path)
        ? await Directory(path).rename(target)
        : await File(path).rename(target);
    return null;
  } on FileSystemException catch (e) {
    return e.osError?.message ?? e.message;
  }
}

Future<(String?, String?)> create(String dir, String name, {required bool folder}) async {
  if (name.isEmpty || name.contains('/')) return (null, 'A name can\'t be empty or contain "/"');
  final path = join(dir, name);
  if (FileSystemEntity.typeSync(path, followLinks: false) != FileSystemEntityType.notFound) {
    return (null, '"$name" already exists');
  }
  try {
    folder ? await Directory(path).create() : await File(path).create();
    return (path, null);
  } on FileSystemException catch (e) {
    return (null, e.osError?.message ?? e.message);
  }
}

/// Size of a folder's contents (du), for Properties.
Future<int?> folderSize(String path) async {
  try {
    final r = await Process.run('du', ['-sb', '--', path]);
    return int.parse((r.stdout as String).split('\t').first);
  } catch (_) {
    return null;
  }
}

/// Find files under [dir] whose names contain [query], newest matches as
/// they're found. Hidden folders are skipped unless [hidden].
Stream<Entry> search(String dir, String query, {bool hidden = false, int limit = 2000}) async* {
  final q = query.toLowerCase();
  var found = 0;
  final queue = <String>[dir];
  while (queue.isNotEmpty && found < limit) {
    final d = queue.removeAt(0);
    List<FileSystemEntity> items;
    try {
      items = await Directory(d).list(followLinks: false).toList();
    } catch (_) {
      continue;
    }
    for (final e in items) {
      final name = basename(e.path);
      if (!hidden && name.startsWith('.')) continue;
      if (e is Directory) queue.add(e.path);
      if (name.toLowerCase().contains(q)) {
        final s = await stat(e.path);
        if (s != null) {
          found++;
          yield s;
        }
      }
    }
  }
}

// ---------------------------------------------------------------- apps

class App {
  App(this.id, this.name, this.icon, this.mimes);
  final String id; // desktop file name
  final String name;
  final String? icon;
  final List<String> mimes;
}

/// Installed applications that say they open [mime] (their desktop files'
/// MimeType), the default one first.
Future<List<App>> appsFor(String mime) async {
  final dirs = [
    '${Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share'}/applications',
    ...(Platform.environment['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share')
        .split(':')
        .map((d) => '$d/applications'),
  ];
  final seen = <String>{};
  final out = <App>[];
  final group = mime.split('/').first;
  for (final d in dirs) {
    final dir = Directory(d);
    if (!dir.existsSync()) continue;
    for (final f in dir.listSync().whereType<File>()) {
      final id = basename(f.path);
      if (!id.endsWith('.desktop') || !seen.add(id)) continue;
      final app = _readDesktop(f, id);
      if (app == null) continue;
      if (app.mimes.contains(mime) || app.mimes.contains('$group/*')) out.add(app);
    }
  }
  final def = await defaultApp(mime);
  out.sort((a, b) {
    if (a.id == def) return -1;
    if (b.id == def) return 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return out;
}

App? _readDesktop(File f, String id) {
  try {
    String? name, icon;
    var mimes = <String>[];
    var inEntry = false;
    var hidden = false;
    for (final line in f.readAsLinesSync()) {
      if (line.startsWith('[')) {
        inEntry = line.trim() == '[Desktop Entry]';
        continue;
      }
      if (!inEntry) continue;
      if (line.startsWith('Name=')) name = line.substring(5);
      if (line.startsWith('Icon=')) icon = line.substring(5);
      if (line.startsWith('MimeType=')) mimes = line.substring(9).split(';').where((m) => m.isNotEmpty).toList();
      if (line.startsWith('NoDisplay=true') || line.startsWith('Hidden=true')) hidden = true;
    }
    if (name == null || mimes.isEmpty || hidden) return null;
    return App(id, name, icon, mimes);
  } catch (_) {
    return null;
  }
}

Future<String?> defaultApp(String mime) async {
  try {
    final r = await Process.run('xdg-mime', ['query', 'default', mime]);
    final s = (r.stdout as String).trim();
    return s.isEmpty ? null : s;
  } catch (_) {
    return null;
  }
}

Future<void> setDefaultApp(String mime, String appId) => Process.run('xdg-mime', ['default', appId, mime]);

Future<String> mimeOf(String path) async {
  try {
    final r = await Process.run('xdg-mime', ['query', 'filetype', path]);
    final s = (r.stdout as String).trim();
    if (s.isNotEmpty) return s;
  } catch (_) {}
  return lookupMimeType(path) ?? 'application/octet-stream';
}

/// Open with the default app (gio follows mimeapps.list like everyone).
Future<String?> openFile(String path) async {
  final r = await Process.run('gio', ['open', path]);
  return r.exitCode == 0 ? null : (r.stderr as String).trim();
}

Future<void> openWith(App app, List<String> paths) =>
    Process.start('gio', ['launch', _desktopPath(app.id) ?? app.id, ...paths], mode: ProcessStartMode.detached);

String? _desktopPath(String id) {
  for (final d in [
    '${Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share'}/applications',
    ...(Platform.environment['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share').split(':').map((d) => '$d/applications'),
  ]) {
    if (File('$d/$id').existsSync()) return '$d/$id';
  }
  return null;
}

/// A terminal in [dir]: Forge Terminal, else whatever's there.
Future<void> terminalHere(String dir) async {
  for (final (cmd, args) in [
    ('forge-terminal', ['--workdir', dir]),
    ('konsole', ['--workdir', dir]),
    ('kgx', ['--working-directory=$dir']),
    ('xterm', <String>[]),
  ]) {
    try {
      await Process.start(cmd, args, workingDirectory: dir, mode: ProcessStartMode.detached);
      return;
    } on ProcessException {
      continue;
    }
  }
}
